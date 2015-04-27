require "socket"
require "./protocol"
require "./spec091"
require "./timed_channel"

class AMQP::Broker
  ProtocolHeader = ['A'.ord, 'M'.ord, 'Q'.ord, 'P'.ord, 0, 0, 9, 1].map(&.to_u8)

  getter closed

  def initialize(@config)
    @socket = TCPSocket.new(@config.host, @config.port)
    @io = Protocol::IO.new(@socket)
    @sends = ::Channel(Time).new(1)
    @closed = false
    @heartbeater_started = false
    @consumers = {} of UInt16 => Protocol::Frame+ ->
  end

  def register_consumer(channel_id, &block: Protocol::Frame+ ->)
    @consumers[channel_id] = block
  end

  def unregister_consumer(channel_id)
    @consumers.delete(channel_id)
  end

  def send(channel, method)
    frame = Protocol::MethodFrame.new(channel, method)
    puts ">> #{frame}"
    frame.encode(@io)
    @sends.send(Time.now) if @heartbeater_started
  end

  def close
    return if @closed
    @closed = true
    @sends.send(Time.now)
    @socket.close
  end

  def start_reader
    spawn { process_frames }
  end

  def start_heartbeater
    return if @heartbeater_started
    @heartbeater_started = true
    spawn { run_heartbeater }
  end

  private def process_frames
    loop do
      frame = Protocol::Frame.decode(@io)

      case frame
      when Protocol::MethodFrame
        on_method(frame)
      when Protocol::HeadersFrame
      when Protocol::BodyFrame
      when Protocol::HeartbeatFrame
        on_heartbeat
      else
        raise Protocol::FrameError.new "Invalid frame type received"
      end
    end
  rescue ex: Errno
    unless ex.errno == Errno::EBADF
      puts ex
      puts ex.backtrace.join("\n")
    end
    close
  rescue ex: IO::EOFError
    close
  rescue ex
    puts ex
    puts ex.backtrace.join("\n")
    close
  end

  private def on_method(frame: Protocol::MethodFrame)
    puts "<< #{frame}"
    consumer = @consumers[frame.channel]
    unless consumer
      raise Protocol::FrameError.new("Invalid channel received: #{frame.channel}")
    end
    consumer.call(frame)
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
          heartbeat.encode(@io)
        end
      else
        last_sent = send_time
      end
    end
  end

  def write_protocol_header
    @io.write(Slice.new(ProtocolHeader.buffer, ProtocolHeader.length))
  end
end
