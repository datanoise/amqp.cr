require "./protocol"
require "./spec091"
require "./timed_channel"

class AMQP::Engine
  ProtocolHeader = ['A'.ord, 'M'.ord, 'Q'.ord, 'P'.ord, 0, 0, 9, 1].map(&.to_u8)
  ConnectionChannelID = 0_u16

  getter closed

  alias Methods = Protocol::Connection

  def initialize(@config)
    @socket = TCPSocket.new(@config.host, @config.port)
    @io = Protocol::IO.new(@socket)
    @sends = Channel(Time).new(1)
    @closed = false
    @heartbeater_started = false
    @consumers = {} of UInt16 => Channel(Protocol::Method)
  end

  def send(channel, method)
    frame = Protocol::MethodFrame.new(channel, method)
    frame.encode(@io)
    @sends.send(Time.now) if @heartbeater_started
  end

  def register_consumer(channel_id, channel)
    @consumers[channel_id] = channel
  end

  def receive(channel_id)
    consumer = @consumers[channel_id]?
    unless consumer
      raise "not registered consumer for channel #{channel_id}"
    end
    consumer.receive
  end

  def close(code, msg, cls_id = 0_u16, mth_id = 0_u16)
    close_mth = Methods::Close.new(code.to_u16, msg, cls_id, mth_id)
    send(ConnectionChannelID, close_mth)
    close_ok = receive(ConnectionChannelID)
    close
  end

  private def close
    return if @closed
    @closed = true
    @sends.send(Time.now)
    @socket.close
  end

  private def write_protocol_header
    @io.write(Slice.new(ProtocolHeader.buffer, ProtocolHeader.length))
  end

  private def start_reader
    spawn { process_frames }
  end

  private def start_heartbeater
    return if @heartbeater_started
    @heartbeater_started = true
    spawn { run_heartbeater }
  end

  private def process_frames
    loop do
      frame = Protocol::Frame.decode(@io)
      # puts frame

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
      close
    end
  rescue ex
    puts ex
    puts ex.backtrace.join("\n")
    close
  end

  private def on_method(frame: Protocol::MethodFrame)
    puts frame
    case frame.method
    when Methods::Close
      close_ok = Methods::CloseOk.new
      send(frame.channel, close_ok)
    else
      consumer = @consumers[frame.channel]
      unless consumer
        msg = "No consumers found for channel #{frame.channel}"
        puts msg
        close(Protocol::ChannelError::VALUE, msg)
      end
      consumer.send(frame.method)
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
          heartbeat.encode(@io)
        end
      else
        last_sent = send_time
      end
    end
  end

  def handshake
    channel = Channel(Protocol::Method).new
    register_consumer(ConnectionChannelID, channel)

    write_protocol_header
    start_reader

    start = receive(ConnectionChannelID)
    unless start.is_a?(Methods::Start)
      raise Protocol::FrameError.new("Unexpected method #{start.id}")
    end
    @version_major = start.version_major
    @version_minor = start.version_minor
    @server_properties = start.server_properties

    client_properties = Protocol::Table.new
    client_properties["product"] = Connection::DefaultProduct
    client_properties["version"] = Connection::DefaultVersion
    capabilities = client_properties["capabilities"] = Protocol::Table.new
    capabilities["connection.blocked"] = true
    capabilities["consumer_cancel_notify"] = true
    auth = Auth.get_authenticator(start.mechanisms)

    start_ok = Methods::StartOk.new(
      client_properties, "PLAIN", auth.response(@config.username, @config.password), "")
    send(ConnectionChannelID, start_ok)

    tune = receive(ConnectionChannelID)
    unless tune.is_a?(Methods::Tune)
      raise Protocol::FrameError.new("Unexpected method #{tune.id}")
    end

    pick = -> (client: UInt32, server: UInt32) {
      if client == 0 || server == 0
        client > server ? client : server
      else
        client < server ? client : server
      end
    }
    @config.channel_max = pick.call(@config.channel_max.to_u32, tune.channel_max.to_u32).to_u16
    @config.frame_max = pick.call(@config.frame_max.to_u32, tune.frame_max.to_u32).to_u32
    @config.heartbeat = pick.call(@config.heartbeat.total_seconds.to_u32, tune.heartbeat.to_u32).seconds

    tune_ok = Methods::TuneOk.new(
      @config.channel_max, @config.frame_max, @config.heartbeat.total_seconds.to_u16)
    send(ConnectionChannelID, tune_ok)

    start_heartbeater

    open = Methods::Open.new(@config.vhost, "", false)
    send(ConnectionChannelID, open)
    open_ok = receive(ConnectionChannelID)
    unless open_ok.is_a?(Methods::OpenOk)
      raise Protocol::FrameError.new("Unexpected method #{open_ok.id}")
    end
  end
end
