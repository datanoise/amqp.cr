require "./macros"
require "./protocol"
require "./spec091"
require "./pq"

class AMQP::Channel
  # TODO:implement better channel id allocation algorithm
  @@next_channel = 0_u16
  protected def self.next_channel
    @@next_channel += 1
    @@next_channel
  end

  getter closed
  getter broker
  getter rpc
  getter msg

  def initialize(@broker)
    @channel_id = Channel.next_channel
    @rpc = Timed::Channel(Protocol::Method).new
    @msg = Timed::Channel(Message).new(1)
    @flow_callbacks = [] of Bool ->
    @close_callbacks = [] of UInt16, String ->
    @closed = false
    @exchanges = {} of String => Exchange
    @queues = {} of String => Queue
    @subscribers = {} of String => Message ->

    @on_return_callback = -> (code: UInt16, text: String, msg: Message) {}

    # confirm mode attributes
    @in_confirm_mode = false
    @on_confirm_ack = -> (delivery_tag: UInt64) {}
    @on_confirm_nack = -> (delivery_tag: UInt64) {}
    @pending_confirms = PQ(UInt64).new
    @publish_counter = 0_u64

    # these fields are used to buffer incoming methods with content
    @content_method = nil
    @payload = nil
    @header_frame = nil

    register
    open = Protocol::Channel::Open.new("")
    open_ok = rpc_call(open)
    assert_type(open_ok, Protocol::Channel::OpenOk)
  end

  def logger
    @broker.logger
  end

  def on_flow(&block: Bool ->)
    @flow_callbacks << block
  end

  def on_close(&block: UInt16, String ->)
    @close_callbacks << block
  end

  def flow(active)
    flow = Protocol::Channel::Flow.new(active)
    flow_ok = rpc_call(flow)
    assert_type(flow_ok, Protocol::Channel::FlowOk)
    flow_ok.active
  end

  def close(code = Protocol::REPLY_SUCCESS, msg = "bye", cls_id = 0, mth_id = 0)
    return if @closed
    close_ok = rpc_call(Protocol::Channel::Close.new(code.to_u16, msg, cls_id.to_u16, mth_id.to_u16))
    assert_type(close_ok, Protocol::Channel::CloseOk)
  end

  def exchange(name, kind, durable = false, auto_delete = false, internal = false,
               no_wait = false, passive = false, args = Protocol::Table.new)
    unless exchange = @exchanges[name]?
      exchange = Exchange.new(self, name, kind, durable, auto_delete, internal, args)
      exchange.declare(passive: passive, no_wait: no_wait) unless name.empty?
      @exchanges[name] = exchange
    end
    exchange
  end

  def default_exchange
    @default_exchange ||= direct("")
  end

  def fanout(name, durable = false, auto_delete = false, internal = false,
             no_wait = false, passive = false, args = Protocol::Table.new)
    exchange(name, "fanout", durable, auto_delete, internal, no_wait, passive, args)
  end

  def direct(name, durable = false, auto_delete = false, internal = false,
               no_wait = false, passive = false, args = Protocol::Table.new)
    exchange(name, "direct", durable, auto_delete, internal, no_wait, passive, args)
  end

  def topic(name, durable = false, auto_delete = false, internal = false,
               no_wait = false, passive = false, args = Protocol::Table.new)
    exchange(name, "topic", durable, auto_delete, internal, no_wait, passive, args)
  end

  def headers(name, durable = false, auto_delete = false, internal = false,
               no_wait = false, passive = false, args = Protocol::Table.new)
    exchange(name, "headers", durable, auto_delete, internal, no_wait, passive, args)
  end

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

  def publish(msg, exchange_name, key, mandatory = false, immediate = false)
    msg.properties.delivery_mode = 2 if msg.properties.delivery_mode == 0
    msg.properties.content_type = "application/octet-stream" if msg.properties.content_type.empty?
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

  def on_return(&block: UInt16, String, Message ->)
    @on_return_callback = block
  end

  def on_confirm_ack(&block: UInt64 ->)
    @on_confirm_ack = block
  end

  def on_confirm_nack(&block: UInt64 ->)
    @on_confirm_nack = block
  end

  def ack(delivery_tag, multiple = false)
    ack = Protocol::Basic::Ack.new(delivery_tag, multiple)
    oneway_call(ack)
    self
  end

  def reject(delivery_tag, requeue = false)
    reject = Protocol::Basic::Reject.new(delivery_tag, requeue)
    oneway_call(reject)
    self
  end

  def nack(delivery_tag, multiple = false, requeue = false)
    nack = Protocol::Basic::Nack.new(delivery_tag, multiple, requeue)
    oneway_call(nack)
    self
  end

  def qos(prefetch_size, prefetch_count, global = false)
    qos = Protocol::Basic::Qos.new(prefetch_size.to_u32, prefetch_count.to_u16, global)
    qos_ok = rpc_call(qos)
    assert_type(qos_ok, Protocol::Basic::QosOk)
    self
  end

  def recover(requeue = false)
    recover = Protocol::Basic::Recover.new(requeue)
    recover_ok = rpc_call(recover)
    assert_type(recover_ok, Protocol::Basic::RecoverOk)
    self
  end

  def tx
    select = Protocol::Tx::Select.new
    select_ok = rpc_call(select)
    assert_type(select_ok, Protocol::Tx::SelectOk)
    self
  end

  def commit
    commit = Protocol::Tx::Commit.new
    commit_ok = rpc_call(commit)
    assert_type(commit_ok, Protocol::Tx::CommitOk)
    self
  end

  def rollback
    rollback = Protocol::Tx::Rollback.new
    rollback_ok = rpc_call(rollback)
    assert_type(rollback_ok, Protocol::Tx::RollbackOk)
    self
  end

  def confirm(no_wait = false)
    confirm = Protocol::Confirm::Select.new(no_wait)
    select_ok = rpc_call(confirm)
    assert_type(select_ok, Protocol::Confirm::SelectOk)
    self
  end

  private def do_close
    return if @closed
    @closed = true

    @msg.close
    @rpc.close
    @broker.unregister_consumer(@channel_id)
  end

  def rpc_call(method)
    oneway_call(method)
    @rpc.receive
  end

  def oneway_call(method)
    @broker.send(@channel_id, method)
  end

  private def register
    @broker.register_consumer(@channel_id) do |frame|
      process_frame(frame)
    end
    @broker.on_close do
      do_close
    end
  end

  private def process_frame(frame)
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
        @close_callbacks.each &.call(method.reply_code, method.reply_text)
        do_close
      when Protocol::Basic::Cancel
        @subscribers.delete(method.consumer_tag)
        # rabbitmq doesn't implement this method
        # oneway_call(Protocol::Basic::CancelOk.new(method.consumer_tag))
      when Protocol::Basic::Ack
        if @in_confirm_mode
          if method.multiple
            confirm_multiple(method.delivery_tag, @on_confirm_ack)
          else
            confirm_single(method.delivery_tag, @on_confirm_ack)
          end
        else
          logger.error "Received Basic.Ack when confirm mode is off"
        end
      when Protocol::Basic::Nack
        if @in_confirm_mode
          if method.multiple
            confirm_multiple(method.delivery_tag, @on_confirm_nack)
          else
            confirm_single(method.delivery_tag, @on_confirm_nack)
          end
        else
          logger.error "Received Basic.Nack when confirm mode is off"
        end
      else
        @rpc.send(method)
      end
    when Protocol::HeaderFrame
      @header_frame = frame
      @payload = StringIO.new
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
    msg = Message.new(@payload.not_nil!.to_s, @header_frame.not_nil!.properties)
    content_method = @content_method.not_nil!
    case content_method
    when Protocol::Basic::Deliver
      msg.delivery_tag = content_method.delivery_tag
      msg.redelivered = content_method.redelivered
      msg.exchange = @exchanges[content_method.exchange]
      msg.key = content_method.routing_key
      subscriber = @subscribers[content_method.consumer_tag]?
      unless subscriber
        logger.error "No subscriber for consumer_tag #{content_method.consumer_tag} is found"
      else
        subscriber.call(msg)
      end
    when Protocol::Basic::Return
      msg.exchange = @exchanges[content_method.exchange]
      msg.key = content_method.routing_key
      @on_return_callback.call(content_method.reply_code, content_method.reply_text, msg)
    when Protocol::Basic::GetOk
      msg.delivery_tag = content_method.delivery_tag
      msg.redelivered = content_method.redelivered
      msg.exchange = @exchanges[content_method.exchange]
      msg.key = content_method.routing_key
      msg.message_count = content_method.message_count
      @msg.send(msg)
      @rpc.send(content_method)
    end
    @content_method = nil
    @payload = nil
    @header_frame = nil
  end

  private def confirm_single(delivery_tag, callback)
    unacked = [] of UInt64

    loop do
      last = @pending_confirms.pop?
      break unless last
      if last != delivery_tag
        unacked << last
      else
        callback.call(delivery_tag)
        break
      end
    end

    unacked.each {|v| @pending_confirms << v}
  end

  private def confirm_multiple(delivery_tag, callback)
    loop do
      last = @pending_confirms.pop?
      break unless last
      callback.call(last)
      break if last == delivery_tag
    end
  end
end
