module AMQP
  class AMQPError < Exception; end

  class ConnectionClosed < AMQPError
    def initialize(code, msg)
      super("Connection is closed with code #{code}: #{msg}")
    end
  end

  class ChannelClosed < AMQPError
    def initialize(code, msg)
      super("Channel is closed with code #{code}: #{msg}")
    end
  end
end
