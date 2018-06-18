# require "./exchange"
require "./channel"

class AMQP::Message

  TRANSIENT  = 1_u8
  PERSISTENT = 2_u8

  getter! body
  getter! properties

  # the following properties are provided by 'get' and 'deliver' methods
  property delivery_tag : UInt64?
  property redelivered : Bool?
  # these two properties are also provider by 'return' method
  property channel : AMQP::Channel?
  property key : String?

  # provided by amqp 'get' method
  property message_count : UInt32?

  def initialize(body : String, @properties = Protocol::Properties.new)
    @body = body.to_slice
  end

  def initialize(@body : Slice(UInt8), @properties = Protocol::Properties.new)
  end

  def ack
    if channel = @channel
      if tag = @delivery_tag
        channel.ack(tag)
      end
    end
  end

  def reject(requeue = false)
    if channel = @channel
      if tag = @delivery_tag
        channel.reject(tag, requeue)
      end
    end
  end

  def nack(requeue = false)
    if channel = @channel
      if tag = @delivery_tag
        channel.nack(tag, requeue: requeue)
      end
    end
  end

  def to_s
    String.new(@body)
  end
end
