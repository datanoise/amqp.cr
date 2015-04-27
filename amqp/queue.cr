require "./macros"
require "./protocol"

class AMQP::Queue
  getter channel, name, durable, exclusive, auto_delete, args

  def initialize(@channel, @name, @durable, @exclusive, @auto_delete, @args)
  end

  def declare(passive = false, no_wait = false)
    declare = Protocol::Queue::Declare.new(0_u16, @name, passive, @durable, @exclusive, @auto_delete, no_wait, @args)
    declare_ok = @channel.rpc_call(declare)
    assert_type(declare_ok, Protocol::Queue::DeclareOk)
    {declare_ok.message_count, declare_ok.consumer_count}
  end

  def bind(exchange, key = "", no_wait = false, args = Protocol::Table.new)
    exchange_name = exchange ? exchange.name : ""
    bind = Protocol::Queue::Bind.new(0_u16, @name, exchange_name, key, no_wait, args)
    bind_ok = @channel.rpc_call(bind)
    assert_type(bind_ok, Protocol::Queue::BindOk)
  end

  def unbind(exchange, key = "", args = Protocol::Table.new)
    exchange_name = exchange ? exchange.name : ""
    unbind = Protocol::Queue::Unbind.new(0_u16, @name, exchange_name, key, args)
    unbind_ok = @channel.rpc_call(unbind)
    assert_type(unbind_ok, Protocol::Queue::UnbindOk)
  end

  def purge(no_wait = false)
    purge = Protocol::Queue::Purge.new(0_u16, @name, no_wait)
    purge_ok = @channel.rpc_call(purge)
    assert_type(purge_ok, Protocol::Queue::PurgeOk)
    purge_ok.message_count
  end

  def delete(no_wait = false)
    delete = Protocol::Queue::Delete.new(0_u16, @name, false, false, no_wait)
    delete_ok = @channel.rpc_call(delete)
    assert_type(delete_ok, Protocol::Queue::DeleteOk)
    delete_ok.message_count
  end
end
