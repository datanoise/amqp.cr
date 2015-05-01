require "./macros"
require "./protocol"
require "./message"

# Work with exchanges.
#
# Exchanges match and distribute messages across queues. Exchanges can be
# configured in the server or declared at runtime.
#
class AMQP::Exchange
  BUILTIN_TYPES = %w[fanout direct topic headers]

  getter channel, type, name, durable, auto_delete, internal, args

  def initialize(@channel, @name, @type, @durable, @auto_delete, @internal, @args)
    unless BUILTIN_TYPES.includes?(@type)
      raise "Invalid exchange type: #{@type}"
    end
  end

  # See `channel#exchange` method
  def declare(passive = false, no_wait = false)
    declare = Protocol::Exchange::Declare.new(0_u16, @name, @type, passive, @durable, @auto_delete, @internal, no_wait, @args)
    declare_ok = @channel.rpc_call(declare)
    assert_type(declare_ok, Protocol::Exchange::DeclareOk)
    self
  end

  # Deletes an exchange.
  #
  # This method deletes an exchange. When an exchange is deleted all queue
  # bindings on the exchange are cancelled.
  #
  # @param no_wait: When no_wait is true, do not wait for a server confirmation
  # that the exchange has been deleted. Failing to delete the channel could
  # close the channel.
  #
  def delete(no_wait = false)
    delete = Protocol::Exchange::Delete.new(0_u16, @name, false, no_wait)
    delete_ok = @channel.rpc_call(delete)
    assert_type(delete_ok, Protocol::Exchange::DeleteOk)
    self
  end

  # Binds exchange to an exchange.
  #
  # This method binds an exchange to an exchange.
  #
  # @param source: Specifies the source exchange to bind.
  #
  # @param key: Specifies the routing key for the binding. The routing key is
  # used for routing messages depending on the exchange configuration. Not all
  # exchanges use a routing key - refer to the specific exchange.
  #
  # @param no_wait: When no_wait is true, do not wait for a server confirmation
  # that the exchange has been bound. Failing to bind the channel could
  # close the channel.
  #
  # @param args: A set of arguments for the binding. The syntax and semantics
  # of these arguments depends on the exchange class.
  #
  def bind(source, key, no_wait = false, args = Protocol::Table.new)
    bind = Protocol::Exchange::Bind.new(0_u16, @name, source.name, key, no_wait, args)
    bind_ok = @channel.rpc_call(bind)
    assert_type(bind_ok, Protocol::Exchange::BindOk)
    self
  end

  # Unbinds an exchange from an exchange.
  #
  # This method unbinds an exchange from an exchange.
  #
  # @param source: Specifies the source exchange to unbind.
  #
  # @param key: Specifies the name of the source exchange to unbind.
  #
  # @param no_wait: When no_wait is true, do not wait for a server confirmation
  # that the exchange has been unbound. Failing to unbind the channel could
  # close the channel.
  #
  # @param args: Specifies the arguments of the binding to unbind.
  #
  def unbind(source, key, no_wait = false, args = Protocol::Table.new)
    unbind = Protocol::Exchange::Unbind.new(0_u16, @name, source.name, key, no_wait, args)
    unbind_ok = @channel.rpc_call(unbind)
    assert_type(unbind_ok, Protocol::Exchange::UnbindOk)
    self
  end


  # Publishes a message.
  #
  # Parameters:
  #
  # @param msg: Message to publish
  #
  # @param key: Specifies the routing key for the message. The routing key is
  # used for routing messages depending on the exchange configuration.
  #
  # @param mandatory: This flag tells the server how to react if the message
  # cannot be routed to a queue. If this flag is set, the server will return an
  # unroutable message with a Return method. If this flag is zero, the server
  # silently drops the message.
  #
  # @param immediate: This flag tells the server how to react if the message
  # cannot be routed to a queue consumer immediately. If this flag is set, the
  # server will return an undeliverable message with a Return method. If this
  # flag is zero, the server will queue the message, but with no guarantee that
  # it will ever be consumed.
  #
  def publish(msg, key, mandatory = false, immediate = false)
    @channel.publish(msg, @name, key, mandatory, immediate)
    self
  end

  # Registers on return callback.
  #
  # This callback is called with an undeliverable message that was published with the
  # "immediate" flag set, or an unroutable message published with the
  # "mandatory" flag set. The reply code and text provide information about the
  # reason that the message was undeliverable.
  def on_return(&block: UInt16, String, Message ->)
    @channel.on_return(&block)
  end
end
