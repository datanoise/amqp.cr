require "./macros"
require "./broker"
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

    getter config

    def initialize(@config = Config.new)
      @rpc = ::Channel(Protocol::Method).new
      @broker = Broker.new(@config)
      @close = ::Channel(Bool).new
      @close_callbacks = [] of UInt16, String ->
    end

    def self.start(config = Config.new)
      conn = Connection.new(config)
      conn.handshake
      yield conn
      conn.run_loop
    end

    protected def run_loop
      loop do
        break if closed
        @close.receive(1.seconds)
      end
    end

    def close
      close(Protocol::REPLY_SUCCESS, "bye")
    end

    def close(code, msg, cls_id = 0, mth_id = 0)
      close_mth = Protocol::Connection::Close.new(code.to_u16, msg, cls_id.to_u16, mth_id.to_u16)
      close_ok = rpc_call(close_mth)
      assert_type(close_ok, Protocol::Connection::CloseOk)
      @close_callbacks.each &.call(code.to_u16, msg)
      @broker.close
    end

    def closed
      @broker.closed
    end

    def on_close(&block: UInt16, String ->)
      @close_callbacks << block
    end

    def channel
      Channel.new(@broker)
    end

    def block(reason)
      block = Protocol::Connection::Blocked.new(reason)
      oneway_call(block)
      self
    end

    def unblock
      unblock = Protocol::Connection::Unblocked.new
      oneway_call(unblock)
      self
    end

    private def oneway_call(method)
      @broker.send(ConnectionChannelID, method)
    end

    private def rpc_call(method)
      oneway_call(method)
      @rpc.receive
    end

    private def register_consumer
      @broker.register_consumer(ConnectionChannelID) do |frame|
        case frame
        when Protocol::MethodFrame
          method = frame.method
          case method
          when Protocol::Connection::Close
            close_ok = Protocol::Connection::CloseOk.new
            @broker.send(frame.channel, close_ok)
            @broker.close
            @close_callbacks.each &.call(method.reply_code, method.reply_text)
          else
            @rpc.send(frame.method)
          end
        else
          raise Protocol::FrameError.new("Unexpected frame: #{frame}")
        end
      end
    end

    protected def handshake
      @broker.write_protocol_header
      @broker.start_reader
      register_consumer

      start = @rpc.receive
      assert_type(start, Protocol::Connection::Start)
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

      start_ok = Protocol::Connection::StartOk.new(
        client_properties, "PLAIN", auth.response(@config.username, @config.password), "")
      @broker.send(ConnectionChannelID, start_ok)

      tune = @rpc.receive
      assert_type(tune, Protocol::Connection::Tune)

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
      @broker.send(ConnectionChannelID, tune_ok)

      @broker.start_heartbeater

      open = Protocol::Connection::Open.new(@config.vhost, "", false)
      @broker.send(ConnectionChannelID, open)
      open_ok = @rpc.receive
      assert_type(open_ok, Protocol::Connection::OpenOk)
      @broker.on_close { @close.send(true) }
    end
  end
end
