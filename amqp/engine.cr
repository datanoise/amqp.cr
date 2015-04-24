require "./protocol"
require "./spec091"
require "./timed_channel"

class AMQP::Engine
  ProtocolHeader = ['A'.ord, 'M'.ord, 'Q'.ord, 'P'.ord, 0, 0, 9, 1].map(&.to_u8)

  getter closed

  def initialize(@config)
    @socket = TCPSocket.new(@config.host, @config.port)
    @io = Protocol::IO.new(@socket)
    @rpc = Channel(Protocol::Method).new
    @sends = Channel(Time).new(1)
    @closed = false
    @heartbeater_started = false
  end

  def write_protocol_header
    @io.write(Slice.new(ProtocolHeader.buffer, ProtocolHeader.length))
  end

  def start_reader
    spawn { process_frames }
  end

  def start_heartbeater
    return if @heartbeater_started
    @heartbeater_started = true
    spawn { run_heartbeater }
  end

  def send(channel, method)
    frame = Protocol::MethodFrame.new(channel, method)
    frame.encode(@io)
    @sends.send(Time.now) if @heartbeater_started
  end

  def receive
    @rpc.receive
  end

  def close
    @closed = true
    @sends.send(Time.now)
    @socket.close
  end

  private def process_frames
    loop do
      frame = Protocol::Frame.decode(@io)

      case frame
      when Protocol::MethodFrame
        @rpc.send(frame.method)

      when Protocol::HeadersFrame

      when Protocol::BodyFrame

      when Protocol::HeartbeatFrame
        on_heartbeat

      else
        raise Protocol::FrameError.new "Invalid frame type received"
      end
    end
  rescue ex
    puts ex
    puts ex.backtrace.join("\n")
    close
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
end
