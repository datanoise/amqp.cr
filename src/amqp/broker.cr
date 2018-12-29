require "socket"
require "openssl"
require "./protocol"
require "./spec091"
require "./timed_channel"
require "colorize"

class AMQP::Broker
  ProtocolHeader = ['A'.ord, 'M'.ord, 'Q'.ord, 'P'.ord, 0, 0, 9, 1].map(&.to_u8)

  getter closed

  @socket : IO::Buffered

  def initialize(@config : AMQP::Config)
    @socket = TCPSocket.new(@config.host, @config.port)
    @socket.sync = true
    if @config.ssl?
      context = OpenSSL::SSL::Context::Client.new
      context.add_options OpenSSL::SSL::Options::NO_SSL_V2 | OpenSSL::SSL::Options::NO_SSL_V3

      @socket = OpenSSL::SSL::Socket::Client.new(@socket, context)
      @socket.sync = true
    end
    @io = Protocol::IO.new(@socket.as(IO::Buffered))
    @sends = Timed::TimedChannel(Time).new(1)
    @closed = false
    @heartbeater_started = false
    @sending = false
    @consumers = {} of UInt16 => Protocol::Frame ->
    @close_callbacks = [] of ->
    channel_max = @config.channel_max == 0 ? UInt16::MAX : @config.channel_max
    @channel_slots = Deque(UInt16).new(channel_max.to_i - 1) do |i|
      (i + 1).to_u16
    end
  end

  def next_channel_id
    @channel_slots.shift
  end

  def return_channel_id(id)
    @channel_slots.push(id)
  end

  def register_consumer(channel_id, &block : Protocol::Frame ->)
    @consumers[channel_id] = block
  end

  def unregister_consumer(channel_id)
    @consumers.delete(channel_id)
  end

  def send(channel, method)
    frame = Protocol::MethodFrame.new(channel, method)
    if method.has_content?
      frames = [frame] of Protocol::Frame
      unless method.responds_to?(:content)
        raise Protocol::FrameError.new("unable to obtain the method's content")
      end
      properties, payload = method.content
      frames << Protocol::HeaderFrame.new(channel, method.id.first, 0_u16, payload.size.to_u64, properties)

      limit = @config.frame_max - Protocol::FRAME_HEADER_SIZE
      while payload && !payload.empty?
        if payload.size < limit
          limit = payload.size
        end
        body, payload = payload[0, limit], (limit > payload.size ? Slice(UInt8).new(0) : payload[limit, payload.size - limit])
        frames << Protocol::BodyFrame.new(channel, body)
      end
      send_frames(frames)
    else
      send_frame(frame)
    end
  end

  private def send_frame(frame : Protocol::Frame)
    while @sending
      Fiber.yield
    end
    @sending = true

    transmit_frame(frame)
  ensure
    @sending = false
  end

  private def send_frames(frames : Array(Protocol::Frame))
    while @sending
      Fiber.yield
    end
    @sending = true

    frames.each {|frame| transmit_frame(frame)}
  ensure
    @sending = false
  end

  private def transmit_frame(frame)
    logger.debug ">> #{frame}".colorize.green
    frame.encode(@io)
    @sends.send(Time.now) if @heartbeater_started
  end

  def on_close(&block : ->)
    @close_callbacks.unshift block
  end

  def close
    return if @closed
    @closed = true
    @sends.send(Time.now)
    @socket.close
    @close_callbacks.each &.call
  end

  def start_reader
    spawn { process_frames }
  end

  def start_heartbeater
    return if @heartbeater_started
    return if @config.heartbeat.total_nanoseconds == 0
    @heartbeater_started = true
    spawn { run_heartbeater }
  end

  def logger
    @config.logger
  end

  private def process_frames
    loop do
      frame = Protocol::Frame.decode(@io)
      logger.debug "<< #{frame}".colorize.blue

      case frame
      when Protocol::MethodFrame
        on_frame(frame)
      when Protocol::HeaderFrame
        on_frame(frame)
      when Protocol::BodyFrame
        on_frame(frame)
      when Protocol::HeartbeatFrame
        on_heartbeat
      else
        logger.error "Invalid frame type received: #{frame}"
      end
    end
  rescue ex : Errno
    unless ex.errno == Errno::EBADF
      puts ex
      puts ex.backtrace.join("\n")
    end
    close
  rescue ex : IO::Error
    close
  rescue ex
    puts ex.inspect
    puts ex.backtrace.join("\n")
    close
  end

  private def on_frame(frame)
    consumer = @consumers[frame.channel]
    if consumer
      consumer.call(frame)
    else
      logger.error "Invalid channel received: #{frame.channel}"
    end
  end

  private def on_heartbeat
  end

  private def run_heartbeater
    interval = @config.heartbeat
    loop do
      last_sent = Time.now
      send_time = @sends.receive(interval)
      break if @closed
      unless send_time
        # timeout received, fill the channel with heartbeats
        if Time.now - last_sent > interval
          heartbeat = Protocol::HeartbeatFrame.new
          send_frame(heartbeat)
        end
      else
        last_sent = send_time
      end
    end
  end

  def write_protocol_header
    @io.write(Slice.new(ProtocolHeader.to_unsafe, ProtocolHeader.size))
  end
end
