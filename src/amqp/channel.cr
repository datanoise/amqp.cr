require "./errors"
require "./macros"
require "./protocol"
require "./exchange"
require "./spec091"
require "./pq"

# Work with channels.
#
# The channel class provides methods for a client to establish a channel to a
# server and for both peers to operate the channel thereafter.
#
class AMQP::Channel
  @default_exchange : Exchange?

  getter closed
  getter broker
  getter rpc
  getter msg

  @channel_id : UInt16
  @content_method : AMQP::Protocol::Method|Nil
  @header_frame : Protocol::HeaderFrame|Nil


  def initialize(@broker : AMQP::Broker)
    @channel_id = @broker.next_channel_id
    @rpc = ::Channel(Protocol::Method).new
    @msg = ::Channel(Message).new(1)
    @flow_callbacks = [] of Bool ->
    @exchanges = {} of String => Exchange
    @queues = {} of String => Queue
    @subscribers = {} of String => Message ->

    @on_return_callback = nil

    # confirm mode attributes
    @in_confirm_mode = false
    @on_confirm_callback = nil
    @pending_confirms = PQ(UInt64).new
    @publish_counter = 0_u64

    # these fields are used to buffer incoming methods with content
    @payload = nil

    # close channel attributes
    @close_callbacks = [] of UInt16, String ->
    @close_code = 0_u16
    @close_msg = ""
    @closed = false

    register
    open = Protocol::Channel::Open.new("")
    open_ok = rpc_call(open)
    assert_type(open_ok, Protocol::Channel::OpenOk)
  end

  def logger
    @broker.logger
  end

  # Registers a flow notification callback.
  # The boolean parameter indicates whether to start sending content frames, or not.
  # See `flow` method.
  def on_flow(&block: Bool ->)
    @flow_callbacks << block
  end

  # Registers a channel close callback.
  # The callback block receives code and description as parameters.
  def on_close(&block: UInt16, String ->)
    @close_callbacks << block
  end

  # Sends a flow indicator to the server.
  # The flows are used  asks the peer to pause or restart the flow of content
  # data sent by a consumer. This is a simple flow-control mechanism that a
  # peer can use to avoid overflowing its queues or otherwise finding itself
  # receiving more messages than it can process.
  def flow(active)
    flow = Protocol::Channel::Flow.new(active)
    flow_ok = rpc_call(flow)
    assert_type(flow_ok, Protocol::Channel::FlowOk)
    flow_ok.active
  end

  # Closes a channel with a specified code and a message
  def close(code = Protocol::REPLY_SUCCESS, msg = "bye", cls_id = 0, mth_id = 0)
    return if @closed
    close_ok = rpc_call(Protocol::Channel::Close.new(code.to_u16, msg, cls_id.to_u16, mth_id.to_u16))
    assert_type(close_ok, Protocol::Channel::CloseOk)
    @close_code, @close_msg = code.to_u16, msg
    do_close
  end

  # Creates a new exchange.
  # Parameters:
  #
  # @param name: a name of the exchange
  #
  # @param kind: a exchange type, could be one of fanout, direct, topic, headers
  #
  # @param durable: If set when creating a new exchange, the exchange will be
  # marked as durable. Durable exchanges remain active when a server restarts.
  # Non-durable exchanges (transient exchanges) are purged if/when a server
  # restarts.
  #
  # @param auto_delete: If set, the exchange is deleted when all queues have
  # finished using it.
  #
  # @param internal: If set, the exchange may not be used directly by
  # publishers, but only when bound to other exchanges. Internal exchanges are
  # used to construct wiring that is not visible to applications.
  #
  # @param no_wait: If set, declare without waiting for a confirmation from the
  # server. The channel may be closed as a result of an error.  Add an
  # `on_close` listener to respond to any exceptions.
  #
  # @param passive: If set, the server will reply with Declare-Ok if the
  # exchange already exists with the same name, and raise an error if not. The
  # client can use this to check whether an exchange exists without modifying
  # the server state. When set, all other method fields except name and no-wait
  # are ignored. A declare with both passive and no-wait has no effect.
  # Arguments are compared for semantic equivalence.
  #
  # @param args: A set of arguments for the declaration. The syntax and
  # semantics of these arguments depends on the server implementation.
  #
  def exchange(name, kind, durable = false, auto_delete = false, internal = false,
               no_wait = false, passive = false, args = Protocol::Table.new)
    unless exchange = @exchanges[name]?
      exchange = Exchange.new(self, name, kind, durable, auto_delete, internal, args)
      exchange.declare(passive: passive, no_wait: no_wait) unless name.empty?
      @exchanges[name] = exchange
    end
    exchange
  end

  # Returns a default exchange.
  def default_exchange
    @default_exchange ||= direct("")
  end

  # Creates a fanout exchange.
  #
  # See `exchange` method.
  def fanout(name, durable = false, auto_delete = false, internal = false,
             no_wait = false, passive = false, args = Protocol::Table.new)
    exchange(name, "fanout", durable, auto_delete, internal, no_wait, passive, args)
  end

  # Creates a direct exchange.
  #
  # See `exchange` method.
  def direct(name, durable = false, auto_delete = false, internal = false,
               no_wait = false, passive = false, args = Protocol::Table.new)
    exchange(name, "direct", durable, auto_delete, internal, no_wait, passive, args)
  end

  # Creates a topic exchange.
  #
  # See `exchange` method.
  def topic(name, durable = false, auto_delete = false, internal = false,
               no_wait = false, passive = false, args = Protocol::Table.new)
    exchange(name, "topic", durable, auto_delete, internal, no_wait, passive, args)
  end

  # Creates a headers exchange.
  #
  # See `exchange` method.
  def headers(name, durable = false, auto_delete = false, internal = false,
               no_wait = false, passive = false, args = Protocol::Table.new)
    exchange(name, "headers", durable, auto_delete, internal, no_wait, passive, args)
  end

  # Creates a new queue.
  #
  # Parameters:
  #
  # @param name: a name of a queue
  #
  # @param durable: If set when creating a new queue, the queue will be marked
  # as durable. Durable queues remain active when a server restarts.
  # Non-durable queues (transient queues) are purged if/when a server restarts.
  # Note that durable queues do not necessarily hold persistent messages,
  # although it does not make sense to send persistent messages to a transient
  # queue.
  #
  # @param passive: If set, the server will reply with Declare-Ok if the queue
  # already exists with the same name, and raise an error if not. The client
  # can use this to check whether a queue exists without modifying the server
  # state. When set, all other method fields except name and no-wait are
  # ignored. A declare with both passive and no-wait has no effect. Arguments
  # are compared for semantic equivalence.
  #
  # @param exclusive: Exclusive queues may only be accessed by the current
  # connection, and are deleted when that connection closes. Passive
  # declaration of an exclusive queue by other connections are not allowed.
  #
  # @param auto_delete: If set, the queue is deleted when all consumers have
  # finished using it. The last consumer can be cancelled either explicitly or
  # because its channel is closed. If there was no consumer ever on the queue,
  # it won't be deleted. Applications can explicitly delete auto-delete queues
  # using the `Queue#delete` method as normal.
  #
  # @param no_wait: If set, declare without waiting for a confirmation from the
  # server. The channel may be closed as a result of an error.  Add an
  # `on_close` listener to respond to any exceptions.
  #
  # @param args: A set of arguments for the declaration. The syntax and
  # semantics of these arguments depends on the server implementation.
  #
  def queue(name, durable = false, passive = false, exclusive = false,
            auto_delete = false, no_wait = false, args = Protocol::Table.new)
    name = "" unless name
    unless queue = @queues[name]?
      queue = Queue.new(self, name, durable, exclusive, auto_delete, args)
      queue.declare(passive, no_wait)
      @queues[name] = queue
    end
    queue
  end

  # Publishes a message.
  #
  # Parameters:
  #
  # @param msg: Message to publish
  #
  # @param exchange_name: A name of exchange to use
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
  def publish(msg, exchange_name, key, mandatory = false, immediate = false)
    msg.properties.delivery_mode = Message::TRANSIENT if msg.properties.delivery_mode == 0
    publish = Protocol::Basic::Publish.new(0_u16, exchange_name, key, mandatory, immediate, msg.properties, msg.body)
    oneway_call(publish)

    if @in_confirm_mode
      @publish_counter += 1
      @pending_confirms << @publish_counter
    end

    self
  end

  def register_subscriber(consumer_tag, block)
    @subscribers[consumer_tag] = block
  end

  def unregister_subscriber(consumer_tag)
    @subscribers.delete(consumer_tag)
  end

  def has_subscriber?(consumer_tag)
    @subscribers.has_key?(consumer_tag)
  end

  # Registers on return callback.
  #
  # This callback is called with an undeliverable message that was published with the
  # "immediate" flag set, or an unroutable message published with the
  # "mandatory" flag set. The reply code and text provide information about the
  # reason that the message was undeliverable.
  def on_return(&block: UInt16, String ->)
    @on_return_callback = block
  end

  # Registers on confirm callback.
  # See `confirm` method.
  def on_confirm(&block: UInt64, Bool ->)
    @on_confirm_callback = block
  end

  # Acknowledge a message by using delivery tag. The acknowledgement can be for a
  # single message or a set of messages up to and including a specific message.
  #
  # @param multiple: If set to true, the delivery tag is treated as "up to and
  # including", so that multiple messages can be acknowledged with a single
  # method. If set to false, the delivery tag refers to a single message. If the
  # multiple field is true, and the delivery tag is zero, this indicates
  # acknowledgement of all outstanding messages.
  #
  def ack(delivery_tag, multiple = false)
    ack = Protocol::Basic::Ack.new(delivery_tag, multiple)
    oneway_call(ack)
    self
  end

  # Rejects a message by using delivery tag. It can be used to interrupt and
  # cancel large incoming messages, or return untreatable messages to their
  # original queue.
  #
  # @param requeue: If requeue is true, the server will attempt to requeue the
  # message. If requeue is false or the requeue attempt fails the messages are
  # discarded or dead-lettered.
  #
  def reject(delivery_tag, requeue = false)
    reject = Protocol::Basic::Reject.new(delivery_tag, requeue)
    oneway_call(reject)
    self
  end

  # This method allows a client to reject one or more incoming messages. It can
  # be used to interrupt and cancel large incoming messages, or return
  # untreatable messages to their original queue. This method is also used by
  # the server to inform publishers on channels in confirm mode of unhandled
  # messages. If a publisher receives this method, it probably needs to
  # republish the offending messages.
  #
  # @param multiple: If set to true, the delivery tag is treated as "up to and
  # including", so that multiple messages can be rejected with a single method.
  # If set to false, the delivery tag refers to a single message. If the
  # multiple field is true, and the delivery tag is false, this indicates
  # rejection of all outstanding messages.
  #
  # @param requeue: If requeue is true, the server will attempt to requeue the
  # message. If requeue is false or the requeue attempt fails the messages are
  # discarded or dead-lettered. Clients receiving the Nack methods should
  # ignore this flag.
  #
  def nack(delivery_tag, multiple = false, requeue = false)
    nack = Protocol::Basic::Nack.new(delivery_tag, multiple, requeue)
    oneway_call(nack)
    self
  end

  # Specifies quality of service.
  #
  # This method requests a specific quality of service. The QoS can be
  # specified for the current channel or for all channels on the connection.
  # The particular properties and semantics of a qos method always depend on
  # the content class semantics. Though the qos method could in principle apply
  # to both peers, it is currently meaningful only for the server.
  #
  # Parameters:
  #
  # @param prefetch_size: The client can request that messages be sent in
  # advance so that when the client finishes processing a message, the
  # following message is already held locally, rather than needing to be sent
  # down the channel. Prefetching gives a performance improvement. This field
  # specifies the prefetch window size in octets. The server will send a
  # message in advance if it is equal to or smaller in size than the available
  # prefetch size (and also falls into other prefetch limits). May be set to
  # zero, meaning "no specific limit", although other prefetch limits may still
  # apply. The prefetch-size is ignored if the no-ack option is set.
  #
  # @param prefetch_count: Specifies a prefetch window in terms of whole
  # messages. This field may be used in combination with the prefetch-size
  # field; a message will only be sent in advance if both prefetch windows (and
  # those at the channel and connection level) allow it. The prefetch-count is
  # ignored if the no-ack option is set.
  #
  # @param global: RabbitMQ has reinterpreted this field. The original
  # specification said: "By default the QoS settings apply to the current
  # channel only. If this field is set, they are applied to the entire
  # connection." Instead, RabbitMQ takes global=false to mean that the QoS
  # settings should apply per-consumer (for new consumers on the channel;
  # existing ones being unaffected) and global=true to mean that the QoS
  # settings should apply per-channel.
  #
  def qos(prefetch_size, prefetch_count, global = false)
    qos = Protocol::Basic::Qos.new(prefetch_size.to_u32, prefetch_count.to_u16, global)
    qos_ok = rpc_call(qos)
    assert_type(qos_ok, Protocol::Basic::QosOk)
    self
  end

  # Redelivers unacknowledged messages.
  #
  # This method asks the server to redeliver all unacknowledged messages on a
  # specified channel. Zero or more messages may be redelivered. This method
  # replaces the asynchronous Recover.
  #
  # @param requeue: If this field is false, the message will be redelivered to
  # the original recipient. If this bit is true, the server will attempt to
  # requeue the message, potentially then delivering it to an alternative
  # subscriber.
  #
  def recover(requeue = false)
    recover = Protocol::Basic::Recover.new(requeue)
    recover_ok = rpc_call(recover)
    assert_type(recover_ok, Protocol::Basic::RecoverOk)
    self
  end

  # Starts a transaction.
  #
  # The transaction allows publish and ack operations to be batched into atomic
  # units of work. The intention is that all publish and ack requests issued
  # within a transaction will complete successfully or none of them will.
  #
  def tx
    sel = Protocol::Tx::Select.new
    select_ok = rpc_call(sel)
    assert_type(select_ok, Protocol::Tx::SelectOk)
    self
  end

  # Invoke a set of method in the transaction boundary.
  # The transaction will be automatically committed if no exceptions are raised,
  # and rolled back otherwise.
  #
  # ```
  # channel.tx do
  #   channel.publish(...)
  #   ...
  # end
  # ```
  def tx
    tx
    yield
    commit
  rescue ex
    rollback
    raise ex
  end

  # Commits the current transaction.
  #
  # This method commits all message publications and acknowledgments performed
  # in the current transaction. A new transaction starts immediately after a
  # commit.
  #
  def commit
    commit = Protocol::Tx::Commit.new
    commit_ok = rpc_call(commit)
    assert_type(commit_ok, Protocol::Tx::CommitOk)
    self
  end

  # Abandons the current transaction.
  #
  # This method abandons all message publications and acknowledgments performed
  # in the current transaction. A new transaction starts immediately after a
  # rollback. Note that unacked messages will not be automatically redelivered
  # by rollback; if that is required an explicit recover call should be issued.
  #
  def rollback
    rollback = Protocol::Tx::Rollback.new
    rollback_ok = rpc_call(rollback)
    assert_type(rollback_ok, Protocol::Tx::RollbackOk)
    self
  end

  # This method puts the channel in confirm mode and subsequently be notified
  # when messages have been handled by the broker. The intention is that all
  # messages published on a channel in confirm mode will be acknowledged at
  # some point. By acknowledging a message the broker assumes responsibility
  # for it and indicates that it has done something it deems reasonable with
  # it. Unroutable mandatory or immediate messages are acknowledged right after
  # the Basic.Return method. Messages are acknowledged when all queues to which
  # the message has been routed have either delivered the message and received
  # an acknowledgement (if required), or enqueued the message (and persisted it
  # if required). Published messages are assigned ascending sequence numbers,
  # starting at 1 with the first `confirm` method. The server confirms messages
  # by sending Basic.Ack methods referring to these sequence numbers.  Use
  # `on_confirm` callback to receive such confirmations.
  #
  def confirm(no_wait = false)
    confirm = Protocol::Confirm::Select.new(no_wait)
    select_ok = rpc_call(confirm)
    assert_type(select_ok, Protocol::Confirm::SelectOk)
    @in_confirm_mode = true
    self
  end

  private def do_close
    return if @closed
    @closed = true

    @close_callbacks.each &.call(@close_code, @close_msg)

    @msg.close
    @rpc.close
    @broker.unregister_consumer(@channel_id)
    @broker.return_channel_id(@channel_id)
  end

  def rpc_call(method)
    oneway_call(method)
    @rpc.receive
  rescue ::Channel::ClosedError
    raise ChannelClosed.new(@close_code, @close_msg)
  end

  def oneway_call(method)
    @broker.send(@channel_id, method)
  rescue ::Channel::ClosedError
    raise ChannelClosed.new(@close_code, @close_msg)
  end

  private def register
    @broker.register_consumer(@channel_id) do |frame|
      process_frame(frame)
    end
    @broker.on_close do
      do_close
    end
  end

  private def process_frame(frame : Protocol::Frame)
    case frame
    when Protocol::MethodFrame
      method = frame.method
      if method.has_content?
        @content_method = method
        return
      end

      case method
      when Protocol::Channel::Flow
        oneway_call(Protocol::Channel::FlowOk.new(method.active))
        @flow_callbacks.each &.call(method.active)
      when Protocol::Channel::Close
        oneway_call(Protocol::Channel::CloseOk.new)
        @close_code, @close_msg = method.reply_code, method.reply_text
        do_close
      when Protocol::Basic::Cancel
        @subscribers.delete(method.consumer_tag)
        # rabbitmq doesn't implement this method
        # oneway_call(Protocol::Basic::CancelOk.new(method.consumer_tag))
      when Protocol::Basic::Ack
        if @in_confirm_mode
          if method.multiple
            confirm_multiple(method.delivery_tag, true)
          else
            confirm_single(method.delivery_tag, true)
          end
        else
          logger.error "Received Basic.Ack when confirm mode is off"
        end
      when Protocol::Basic::Nack
        if @in_confirm_mode
          if method.multiple
            confirm_multiple(method.delivery_tag, false)
          else
            confirm_single(method.delivery_tag, false)
          end
        else
          logger.error "Received Basic.Nack when confirm mode is off"
        end
      else
        @rpc.send(method)
      end
    when Protocol::HeaderFrame
      @header_frame = frame
      @payload = ::IO::Memory.new
      if frame.body_size == 0
        deliver_content
      end
    when Protocol::BodyFrame
      payload = @payload
      header_frame = @header_frame
      if payload && header_frame
        payload.write(frame.body)
        if payload.bytesize >= header_frame.body_size
          deliver_content
        end
      else
        logger.error "Invalid state. Haven't received header frame first."
      end
    end
  end

  private def deliver_content
    msg = Message.new(@payload.not_nil!.to_slice, @header_frame.not_nil!.properties)
    content_method = @content_method.not_nil!
    case content_method
    when Protocol::Basic::Deliver
      msg.delivery_tag = content_method.delivery_tag
      msg.redelivered = content_method.redelivered
      msg.channel = self
      msg.key = content_method.routing_key
      subscriber = @subscribers[content_method.consumer_tag]?
      unless subscriber
        logger.error "No subscriber for consumer_tag #{content_method.consumer_tag} is found"
      else
        subscriber.call(msg)
      end
    when Protocol::Basic::Return
      @on_return_callback.try &.call(content_method.reply_code, content_method.reply_text)
    when Protocol::Basic::GetOk
      msg.delivery_tag = content_method.delivery_tag
      msg.redelivered = content_method.redelivered
      msg.channel = self
      msg.key = content_method.routing_key
      msg.message_count = content_method.message_count
      @msg.send(msg)
      @rpc.send(content_method)
    end
    @content_method = nil
    @payload = nil
    @header_frame = nil
  end

  private def confirm_single(delivery_tag, ack)
    unacked = [] of UInt64
    loop do
      last = @pending_confirms.pop?
      break unless last
      if last != delivery_tag
        unacked << last
      else
        @on_confirm_callback.try &.call(delivery_tag, ack)
        break
      end
    end

    unacked.each {|v| @pending_confirms << v}
  end

  private def confirm_multiple(delivery_tag, ack)
    loop do
      last = @pending_confirms.pop?
      break unless last
      @on_confirm_callback.try &.call(last, ack)
      break if last == delivery_tag
    end
  end
end
