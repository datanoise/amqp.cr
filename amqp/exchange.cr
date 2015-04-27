require "./macros"
require "./protocol"

class AMQP::Exchange
  BUILTIN_TYPES = %w[fanout direct topic headers]

  getter channel, type, name, durable, auto_delete, internal, args

  def initialize(@channel, @name, @type, @durable, @auto_delete, @internal, @args)
    unless BUILTIN_TYPES.includes?(@type)
      raise "Invalid exchange type"
    end
    @broker = @channel.broker
    @rpc = @channel.rpc
  end

  def declare(passive = false, no_wait = false)
    declare = Protocol::Exchange::Declare.new(0_u16, @name, @type, passive, @durable, @auto_delete, @internal, no_wait, @args)
    @broker.send(@channel.channel, declare)
    declare_ok = @rpc.receive
    assert_type(declare_ok, Protocol::Exchange::DeclareOk)
  end

  def delete(no_wait = false)
    delete = Protocol::Exchange::Delete.new(0_u16, @name, false, no_wait)
    @broker.send(@channel.channel, delete)
    delete_ok = @rpc.receive
    assert_type(delete_ok, Protocol::Exchange::DeleteOk)
  end

  def bind(source, key, no_wait = false, args = Protocol::Table.new)
    bind = Protocol::Exchange::Bind.new(0_u16, @name, source, key, no_wait, args)
    @broker.send(@channel.channel, bind)
    bind_ok = @rpc.receive
    assert_type(bind_ok, Protocol::Exchange::BindOk)
  end

  def unbind(source, key, no_wait = false, args = Protocol::Table.new)
    unbind = Protocol::Exchange::Unbind.new(0_u16, @name, source, key, no_wait, args)
    @broker.send(@channel.channel, unbind)
    unbind_ok = @rpc.receive
    assert_type(unbind_ok, Protocol::Exchange::UnbindOk)
  end
end
