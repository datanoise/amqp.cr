require "socket"
require "./engine"
require "./auth"

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
    DefaultProduct = "http://github.com/datanoise/amqp.cr"
    DefaultVersion = "0.1"

    alias Methods = Protocol::Connection

    getter config

    def initialize(@config = Config.new)
      @engine = Engine.new(@config)
      @channel_id = 0_u16
    end

    def self.start(config = Config.new)
      conn = Connection.new(config)
      conn.handshake
      yield conn
      loop do
        break if conn.closed
        sleep 1
      end
    end

    def close
      close = Methods::Close.new(Protocol::REPLY_SUCCESS.to_u16, "bye now", 0_u16, 0_u16)
      @engine.send(@channel_id, close)
      close_ok = @engine.receive
      @engine.close
    end

    def closed
      @engine.closed
    end

    protected def handshake
      @engine.write_protocol_header
      @engine.start_reader

      start = @engine.receive
      unless start.is_a?(Methods::Start)
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
      auth = Auth.get_authenticator(start.mechanisms)

      start_ok = Methods::StartOk.new(
        client_properties, "PLAIN", auth.response(@config.username, @config.password), "")
      @engine.send(@channel_id, start_ok)

      tune = @engine.receive
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
      @engine.send(@channel_id, tune_ok)

      @engine.start_heartbeater

      open = Methods::Open.new(@config.vhost, "", false)
      @engine.send(@channel_id, open)
      open_ok = @engine.receive
      unless open_ok.is_a?(Methods::OpenOk)
        raise Protocol::FrameError.new("Unexpected method #{open_ok.id}")
      end
    end
  end
end
