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

    getter config

    def initialize(@config = Config.new)
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
      @engine.close(Protocol::REPLY_SUCCESS, "byenow")
    end

    def closed
      @engine.closed
    end

    protected def handshake
      @engine.handshake
    end
  end
end
