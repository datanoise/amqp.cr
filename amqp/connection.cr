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
  end

  class Connection
    DefaultProduct = "http://github.com/datanoise/amqp.cr"
    DefaultVersion = "0.1"
    ConnectionChannelID = 0_u16

    alias Methods = Protocol::Connection

    getter config

    def initialize(@config = Config.new)
      @rpc = ::Channel(Protocol::Method).new
      @engine = Engine.new(@config)
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
      close(Protocol::REPLY_SUCCESS, "bye")
    end

    def close(code, msg, cls_id = 0, mth_id = 0)
      close_mth = Methods::Close.new(code.to_u16, msg, cls_id.to_u16, mth_id.to_u16)
      @engine.send(ConnectionChannelID, close_mth)
      close_ok = @rpc.receive
      @engine.close
    end

    def closed
      @engine.closed
    end

    def channel
      Channel.new(@engine)
    end

    private def register_consumer
      @engine.register_consumer(ConnectionChannelID) do |frame|
        case frame
        when Protocol::MethodFrame
          case frame.method
          when Methods::Close
            close_ok = Methods::CloseOk.new
            @engine.send(frame.channel, close_ok)
            @engine.close
          else
            @rpc.send(frame.method)
          end
        else
          raise Protocol::FrameError.new("Unexpected frame: #{frame}")
        end
      end
    end

    protected def handshake
      @engine.write_protocol_header
      @engine.start_reader
      register_consumer

      start = @rpc.receive
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
      @engine.send(ConnectionChannelID, start_ok)

      tune = @rpc.receive
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
      @engine.send(ConnectionChannelID, tune_ok)

      @engine.start_heartbeater

      open = Methods::Open.new(@config.vhost, "", false)
      @engine.send(ConnectionChannelID, open)
      open_ok = @rpc.receive
      unless open_ok.is_a?(Methods::OpenOk)
        raise Protocol::FrameError.new("Unexpected method #{open_ok.id}")
      end
    end
  end
end
