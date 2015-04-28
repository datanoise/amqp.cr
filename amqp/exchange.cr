require "./macros"
require "./protocol"
require "./message"

class AMQP::Exchange
  BUILTIN_TYPES = %w[fanout direct topic headers]

  getter channel, type, name, durable, auto_delete, internal, args

  def initialize(@channel, @name, @type, @durable, @auto_delete, @internal, @args)
    unless BUILTIN_TYPES.includes?(@type)
      raise "Invalid exchange type: #{@type}"
    end
  end

  def declare(passive = false, no_wait = false)
    declare = Protocol::Exchange::Declare.new(0_u16, @name, @type, passive, @durable, @auto_delete, @internal, no_wait, @args)
    declare_ok = @channel.rpc_call(declare)
    assert_type(declare_ok, Protocol::Exchange::DeclareOk)
    self
  end

  def delete(no_wait = false)
    delete = Protocol::Exchange::Delete.new(0_u16, @name, false, no_wait)
    delete_ok = @channel.rpc_call(delete)
    assert_type(delete_ok, Protocol::Exchange::DeleteOk)
    self
  end

  def bind(source, key, no_wait = false, args = Protocol::Table.new)
    bind = Protocol::Exchange::Bind.new(0_u16, @name, source, key, no_wait, args)
    bind_ok = @channel.rpc_call(bind)
    assert_type(bind_ok, Protocol::Exchange::BindOk)
    self
  end

  def unbind(source, key, no_wait = false, args = Protocol::Table.new)
    unbind = Protocol::Exchange::Unbind.new(0_u16, @name, source, key, no_wait, args)
    unbind_ok = @channel.rpc_call(unbind)
    assert_type(unbind_ok, Protocol::Exchange::UnbindOk)
    self
  end

  def publish(msg, key, mandatory = false, immediate = false)
    msg.properties.delivery_mode = 2 if msg.properties.delivery_mode == 0
    msg.properties.content_type = "application/octet-stream" if msg.properties.content_type.empty?
    publish = Protocol::Basic::Publish.new(0_u16, @name, key, mandatory, immediate, msg.properties, msg.body)
    @channel.oneway_call(publish)
    self
  end

  def on_return(&block: UInt16, String, Message ->)
    @channel.on_return(&block)
  end
end
