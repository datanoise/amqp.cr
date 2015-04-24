require "socket"
require "./protocol"
require "./spec091"
require "./auth"
require "./timed_channel"

module AMQP
  class Config
    getter host
    getter port
    getter username
    getter password
    getter vhost
    property! channel_max
    property! frame_max
    property! heartbeat

    def initialize(@host = "127.0.0.1",
                   @port = 5672,
                   @username = "guest",
                   @password = "guest",
                   @vhost = "/",
                   @channel_max = 0_u16,
                   @frame_max = 0_u32,
                   @heartbeat = 0.seconds)
    end

    def to_s(io)
      io << "host: #{@host}, port: #{@port}, username: #{@username}, password: #{@password}, vhost: #{@vhost} "
      io << "channel_max: #{@channel_max}, frame_max: #{@frame_max}, heartbeat: #{@heartbeat.total_seconds} secs"
    end
  end

  class Connection
    ProtocolHeader = ['A'.ord, 'M'.ord, 'Q'.ord, 'P'.ord, 0, 0, 9, 1].map(&.to_u8)
    DefaultProduct = "http://github.com/datanoise/amqp.cr"
    DefaultVersion = "0.1"

    getter closed

    def initialize(@config = Config.new)
      @socket = TCPSocket.new(@config.host, @config.port)
      @io = Protocol::IO.new(@socket)
      @rpc = Channel(Protocol::Method).new
      @sends = BufferedChannel(Time).new
      @closed = false
    end

    def open
      write_protocol_header
      spawn { process_frames }

      start = @rpc.receive
      unless start.is_a?(Protocol::Connection::Start)
        raise Protocol::FrameError.new("Unexpected method #{start.id}")
      end
      @version_major = start.version_major
      @version_minor = start.version_minor
      @server_properties = start.server_properties

      client_properties = Protocol::Table.new
      client_properties["product"] = DefaultProduct
      client_properties["version"] = DefaultVersion
      capabilities = client_properties["capabilities"] = Protocol::Table.new
      capabilities["connection.blocked"] = true
      capabilities["consumer_cancel_notify"] = true
      auth = get_authenticator(start)
      start_ok = Protocol::Connection::StartOk.new(
        client_properties, "PLAIN", auth.response(@config.username, @config.password), "")
      start_ok.call(@io, 0_u16)

      tune = @rpc.receive
      unless tune.is_a?(Protocol::Connection::Tune)
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

      tune_ok = Protocol::Connection::TuneOk.new(
        @config.channel_max, @config.frame_max, @config.heartbeat.total_seconds.to_u16)
      tune_ok.call(@io, 0_u16)

      spawn { run_heartbeater }

      open = Protocol::Connection::Open.new(@config.vhost, "", false)
      open.call(@io, 0_u16)
      open_ok = @rpc.receive
      unless open_ok.is_a?(Protocol::Connection::OpenOk)
        raise Protocol::FrameError.new("Unexpected method #{open_ok.id}")
      end
    end

    def self.start(config = Config.new)
      conn = Connection.new(config)
      conn.open
      yield conn
      loop do
        break if conn.closed
        sleep 1
      end
    end

    def close
      @closed = true
      @socket.close
    end

    private def get_authenticator(method)
      mechanisms = method.mechanisms
      unless mechanisms
        raise Protocol::FrameError.new("Server returned empty list of auth mechanisms")
      end
      mechanisms = mechanisms.split(' ')
      auth = nil
      mechanisms.each do |mech|
        auth = Authenticators[mech]?
        break if auth
      end
      unless auth
        raise Protocol::NotImplemented.new("Unable to use any of these auth methods #{method.mechanisms}")
      end
      auth
    end

    private def on_heartbeat
      puts "HeartBeat"
    end

    private def write_protocol_header
      @io.write(Slice.new(ProtocolHeader.buffer, ProtocolHeader.length))
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
        end
      end
    rescue ex
      puts ex
      puts ex.backtrace.join("\n")
      close
    end

    private def run_heartbeater
      loop do
        now = Time.now

      end
    end
  end
end

AMQP::Connection.start do |conn|

end

