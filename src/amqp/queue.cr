require "./macros"
require "./protocol"

# Work with queues.
#
# Queues store and forward messages. Queues can be configured in the server or
# created at runtime. Queues must be attached to at least one exchange in order
# to receive messages from publishers.
#
class AMQP::Queue
  getter channel, name, durable, exclusive, auto_delete, args

  def initialize(@channel, @name, @durable, @exclusive, @auto_delete, @args)
  end

  # See `channel#queue` method.
  def declare(passive = false, no_wait = false)
    declare = Protocol::Queue::Declare.new(0_u16, @name, passive, @durable, @exclusive, @auto_delete, no_wait, @args)
    declare_ok = @channel.rpc_call(declare)
    assert_type(declare_ok, Protocol::Queue::DeclareOk)
    @name = declare_ok.queue if @name.empty?
    {declare_ok.message_count, declare_ok.consumer_count}
  end

  # Binds queue to an exchange.
  #
  # This method binds a queue to an exchange. Until a queue is bound it will
  # not receive any messages. In a classic messaging model, store-and-forward
  # queues are bound to a direct exchange and subscription queues are bound to
  # a topic exchange.
  #
  # Parameters:
  #
  # @param exchange: an exchange to bind to
  #
  # @param key: Specifies the routing key for the binding. The routing key is
  # used for routing messages depending on the exchange configuration. Not all
  # exchanges use a routing key - refer to the specific exchange documentation.
  # If the queue name is empty, the server uses the last queue declared on the
  # channel. If the routing key is also empty, the server uses this queue name
  # for the routing key as well. If the queue name is provided but the routing
  # key is empty, the server does the binding with that empty routing key. The
  # meaning of empty routing keys depends on the exchange implementation.
  #
  # @param no_wait: When no_wait is true, the queue will assume to be declared
  # on the server.  A channel exception will arrive if the conditions are met
  # for existing queues or attempting to modify an existing queue from a
  # different connection.
  #
  # @param args:  set of arguments for the binding. The syntax and semantics of
  # these arguments depends on the exchange class.
  #
  def bind(exchange, key = "", no_wait = false, args = Protocol::Table.new)
    exchange_name = exchange ? exchange.name : ""
    bind = Protocol::Queue::Bind.new(0_u16, @name, exchange_name, key, no_wait, args)
    bind_ok = @channel.rpc_call(bind)
    assert_type(bind_ok, Protocol::Queue::BindOk)
    self
  end

  # Unbinds a queue from an exchange.
  #
  # This method unbinds a queue from an exchange.
  #
  # @param exchange: an exchange to unbind from.
  # 
  # @param key: Specifies the routing key of the binding to unbind.
  #
  # @param args: Specifies the arguments of the binding to unbind.
  #
  def unbind(exchange, key = "", args = Protocol::Table.new)
    exchange_name = exchange ? exchange.name : ""
    unbind = Protocol::Queue::Unbind.new(0_u16, @name, exchange_name, key, args)
    unbind_ok = @channel.rpc_call(unbind)
    assert_type(unbind_ok, Protocol::Queue::UnbindOk)
    self
  end

  # This method removes all messages from a queue which are not awaiting acknowledgment.
  def purge(no_wait = false)
    purge = Protocol::Queue::Purge.new(0_u16, @name, no_wait)
    purge_ok = @channel.rpc_call(purge)
    assert_type(purge_ok, Protocol::Queue::PurgeOk)
    purge_ok.message_count
  end

  # Deletes a queue.
  def delete(no_wait = false)
    delete = Protocol::Queue::Delete.new(0_u16, @name, false, false, no_wait)
    delete_ok = @channel.rpc_call(delete)
    assert_type(delete_ok, Protocol::Queue::DeleteOk)
    delete_ok.message_count
  end

  # Starts a queue consumer.
  #
  # This method asks the server to start a "consumer", which is a transient
  # request for messages from a specific queue. Consumers last as long as the
  # channel they were declared on, or until the client cancels them.
  #
  # @param consumer_tag: Specifies the identifier for the consumer. The
  # consumer tag is local to a channel, so two clients can use the same
  # consumer tags. If this field is empty the server will generate a unique
  # tag.
  #
  # @param no_local: When no_local is true, the server will not deliver
  # publishing sent from the same connection to this consumer.  It's advisable
  # to use separate connections for Channel.Publish and Channel.Consume so not
  # to have TCP pushback on publishing affect the ability to consume messages,
  # so this parameter is here mostly for completeness.
  #
  # @param no_ack: If this field is set the server does not expect
  # acknowledgements for messages. That is, when a message is delivered to the
  # client the server assumes the delivery will succeed and immediately
  # dequeues it. This functionality may increase performance but at the cost of
  # reliability. Messages can get lost if a client dies before they are
  # delivered to the application.
  #
  # @param exclusive: Request exclusive consumer access, meaning only this
  # consumer can access the queue.
  #
  # @param no_wait: When no_wait is true, do not wait for the server to confirm
  # the request and immediately begin deliveries.  If it is not possible to
  # consume, a channel exception will be raised and the channel will be closed.
  #
  # @param args: A set of arguments for the consume. The syntax and semantics
  # of these arguments depends on the server implementation.
  #
  # @return consumer_tag used to with `unsubscribe` method
  def subscribe(consumer_tag = "", no_local = false, no_ack = false,
                exclusive = false, no_wait = false, args = Protocol::Table.new,
                &block: Message ->)
    consume = Protocol::Basic::Consume.new(0_u16, @name, consumer_tag, no_local, no_ack, exclusive, no_wait, args)
    consume_ok = @channel.rpc_call(consume)
    assert_type(consume_ok, Protocol::Basic::ConsumeOk)
    consumer_tag = consume_ok.consumer_tag
    @channel.register_subscriber(consumer_tag, block)
    consumer_tag
  end

  # Ends a queue consumer.
  #
  # This method cancels a consumer. This does not affect already delivered
  # messages, but it does mean the server will not send any more messages for
  # that consumer. The client may receive an arbitrary number of messages in
  # between sending the cancel method and receiving the cancel-ok reply. It may
  # also be sent from the server to the client in the event of the consumer
  # being unexpectedly cancelled (i.e. cancelled for any reason other than the
  # server receiving the corresponding basic.cancel from the client). This
  # allows clients to be notified of the loss of consumers due to events such
  # as queue deletion. Note that as it is not a MUST for clients to accept this
  # method from the client, it is advisable for the broker to be able to
  # identify those clients that are capable of accepting the method, through
  # some means of capability negotiation.
  #
  # @param consumer_tag: see method `subscribe`
  def unsubscribe(consumer_tag, no_wait = false)
    return false unless @channel.has_subscriber?(consumer_tag)
    cancel = Protocol::Basic::Cancel.new(consumer_tag, no_wait)
    cancel_ok = @channel.rpc_call(cancel)
    assert_type(cancel_ok, Protocol::Basic::CancelOk)
    @channel.unregister_subscriber(consumer_tag)
    true
  end

  # Direct access to a queue.
  # 
  # This method provides a direct access to the messages in a queue using a
  # synchronous dialogue that is designed for specific types of application
  # where synchronous functionality is more important than performance.
  #
  # @param no_ack: If this field is set the server does not expect
  # acknowledgements for messages. That is, when a message is delivered to the
  # client the server assumes the delivery will succeed and immediately
  # dequeues it. This functionality may increase performance but at the cost of
  # reliability. Messages can get lost if a client dies before they are
  # delivered to the application.
  #
  def get(no_ack = false)
    get = Protocol::Basic::Get.new(0_u16, @name, no_ack)
    response = @channel.rpc_call(get)
    case response
    when Protocol::Basic::GetOk
      return @channel.msg.receive
    when Protocol::Basic::GetEmpty
      return nil
    else
      raise Protocol::FrameError.new("Invalid method received: #{response}")
    end
  end
end
