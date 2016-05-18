require "logger"
require "./errors"
require "./macros"
require "./broker"
require "./auth"

module AMQP
  # Provides settings used to establish a connection to an AMQP server.
  class Config
    # The server host name
    getter host
    # The server port
    getter port
    # The server user name
    getter username
    # The server password
    getter password
    # Provides the name of the virtual host
    getter vhost
    # Logger to use
    getter logger
    # Defines the maximum number of channels for the connection
    property! channel_max
    # Defines the maximum length of a frame in bytes. Default is 0, which is unlimited.
    # This value sill could be limited by the server.
    property! frame_max
    # A number of seconds of inactivity before sending a heartbeat frame.
    property! heartbeat

    def initialize(@host = "127.0.0.1",
                   @port = 5672,
                   @username = "guest",
                   @password = "guest",
                   @vhost = "/",
                   @channel_max = 0_u16,
                   @frame_max = 0_u32,
                   @heartbeat : Time::Span = 0.seconds,
                   @logger = Logger.new(STDOUT),
                   @log_level : Logger::Severity = Logger::INFO)
      @logger.level = @log_level
    end

    def log_level=(level)
      @logger.level = level
    end
  end

  # The connection class provides methods to establish a network connection to a server.
  class Connection
    DefaultProduct = "http://github.com/datanoise/amqp.cr"
    DefaultVersion = "0.1"
    ConnectionChannelID = 0_u16

    getter config
    getter closed

    def initialize(@config = Config.new)
      @rpc = Timed::Channel(Protocol::Method).new
      @broker = Broker.new(@config)
      @break_loop = Timed::Channel(Bool).new

      # close connection attributes
      @close_callbacks = [] of UInt16, String ->
      @close_code = 0_u16
      @close_msg = ""
      @closed = false

      handshake
    end

    # Establishes a connection to the server and passes it to the provided block.
    #
    # ```
    # AMQP::Connection.start do |conn|
    #   channel = conn.channel
    #   ...
    # end
    # ```
    def self.start(config = Config.new)
      conn = Connection.new(config)
      begin
        yield conn
      ensure
        conn.close
      end
    end

    # Enters a processing loop which prevents the program termination. Useful when
    # subscribing to message queues.
    #
    # ```
    # AMQP::Connection.start do |conn|
    #   channel = conn.channel
    #   ...
    #   conn.run_loop
    # end
    # ```
    def run_loop
      @running_loop = true
      loop do
        break if closed
        break if @break_loop.receive(1.seconds)
      end
    ensure
      @running_loop = false
    end

    # Breaks from the run loop
    #
    # ```
    # require 'signal'
    # AMQP::Connection.start do |conn|
    #   channel = conn.channel
    #   ...
    #   trap(INT) { conn.loop_break }
    #   conn.run_loop
    # end
    # ```
    def loop_break
      @break_loop.send(true) if @running_loop
    end

    # Closes the connection to a server
    def close
      close(Protocol::REPLY_SUCCESS, "bye")
    end

    # Closes the connection to a server by providing error code and message.
    def close(code, msg, cls_id = 0, mth_id = 0)
      return if closed
      close_mth = Protocol::Connection::Close.new(code.to_u16, msg, cls_id.to_u16, mth_id.to_u16)
      close_ok = rpc_call(close_mth)
      assert_type(close_ok, Protocol::Connection::CloseOk)
      @close_code, @close_msg = code.to_u16, msg
      do_close
    end

    # Registers the callback to be invoked in case when the connection is closed.
    def on_close(&block : UInt16, String ->)
      @close_callbacks.unshift block
    end

    private def do_close
      return if @closed
      @closed = true

      @broker.close
      @rpc.close
      @close_callbacks.each &.call(@close_code, @close_msg)
      loop_break
    end

    # Creates a new channel.
    def channel
      Channel.new(@broker)
    end

    # This method indicates that a connection has been blocked and does not accept new publishes.
    def block(reason)
      block = Protocol::Connection::Blocked.new(reason)
      oneway_call(block)
      self
    end

    # This method indicates that a connection has been unblocked and now accepts publishes.
    def unblock
      unblock = Protocol::Connection::Unblocked.new
      oneway_call(unblock)
      self
    end

    # Checks the existence of a queue.
    def queue_exists?(name)
      ch = channel
      ch.queue(name, passive: true)
      ch.close
      return true
    rescue ChannelClosed
      return false
    end

    # Checks the existence of an exchange.
    def exchange_exists?(name)
      ch = channel
      ch.exchange(name, passive: true)
      ch.close
      return true
    rescue ChannelClosed
      return false
    end

    private def oneway_call(method)
      @broker.send(ConnectionChannelID, method)
    rescue Timed::ChannelClosed
      raise ConnectionClosed.new(@close_code, @close_msg)
    end

    private def rpc_call(method)
      oneway_call(method)
      @rpc.receive
    rescue Timed::ChannelClosed
      raise ConnectionClosed.new(@close_code, @close_msg)
    end

    private def register_consumer
      @broker.register_consumer(ConnectionChannelID) do |frame|
        case frame
        when Protocol::MethodFrame
          method = frame.method
          case method
          when Protocol::Connection::Close
            @close_code, @close_msg = method.reply_code, method.reply_text
            close_ok = Protocol::Connection::CloseOk.new
            @broker.send(frame.channel, close_ok)
            @broker.close
          else
            @rpc.send(frame.method)
          end
        else
          raise Protocol::FrameError.new("Unexpected frame: #{frame}")
        end
      end
      @broker.on_close { do_close }
    end

    @version_major =  0_u8
    @version_minor =  0_u8
    @server_properties = Hash(String, AMQP::Protocol::Field).new


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
        client_properties, auth.mechanism, auth.response(@config.username, @config.password), "")
      @broker.send(ConnectionChannelID, start_ok)

      tune = @rpc.receive
      assert_type(tune, Protocol::Connection::Tune)

      pick = -> (client : UInt32, server : UInt32) {
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
    end
  end
end
