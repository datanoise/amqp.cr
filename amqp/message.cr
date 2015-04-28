class AMQP::Message
  getter! body
  getter! properties
  property delivery_tag
  property redelivered
  property exchange
  property key

  def initialize(@body, @properties = Protocol::Properties.new)
  end
end
