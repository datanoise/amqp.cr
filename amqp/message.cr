class AMQP::Message
  getter! body
  getter! properties
  property delivery_tag
  property redelivered
  property exchange
  property key

  def initialize(@body, @properties = Protocol::Properties.new)
  end

  def ack
    if exchange = @exchange
      if tag = @delivery_tag
        exchange.channel.ack(tag)
      end
    end
  end

  def reject(requeue = false)
    if exchange = @exchange
      if tag = @delivery_tag
        exchange.channel.reject(tag, requeue)
      end
    end
  end

  def nack(requeue = false)
    if exchange = @exchange
      if tag = @delivery_tag
        exchange.channel.nack(tag, requeue: requeue)
      end
    end
  end
end
