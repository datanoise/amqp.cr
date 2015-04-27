require "./macros"
require "./protocol"
require "./spec091"

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
  getter channel

  def initialize(@broker)
    @channel = Channel.next_channel
    @msgs = ::Channel(Protocol::Method).new
    @rpc = ::Channel(Protocol::Method).new
    @flow_callbacks = [] of Bool ->
    @close_callbacks = [] of UInt16, String ->
    @closed = false
    @exchanges = {} of String => Exchange
    @queues = {} of String => Queue

    register_consumer
    open = Protocol::Channel::Open.new("")
    @broker.send(@channel, open)
    open_ok = @rpc.receive
    assert_type(open_ok, Protocol::Channel::OpenOk)
  end

  def notify_flow(&block: Bool ->)
    @flow_callbacks << block
  end

  def notify_close(&block: UInt16, String ->)
    @close_callbacks << block
  end

  def flow(active)
    flow = Protocol::Channel::Flow.new(active)
    @broker.send(@channel, flow)
    flow_ok = @rpc.receive
    assert_type(flow_ok, Protocol::Channel::FlowOk)
    flow_ok.active
  end

  def close(code = Protocol::REPLY_SUCCESS, msg = "bye", cls_id = 0, mth_id = 0)
    return if @closed
    @broker.send(@channel, Protocol::Channel::Close.new(code.to_u16, msg, cls_id.to_u16, mth_id.to_u16))
    close_ok = @rpc.receive
  end

  def exchange(name, kind, durable = false, auto_delete = false, internal = false,
               no_wait = false, passive = false, args = Protocol::Table.new)
    unless exchange = @exchanges[name]?
      exchange = Exchange.new(self, name, kind, durable, auto_delete, internal, args)
      exchange.declare(passive: passive, no_wait: no_wait)
      @exchanges[name] = exchange
    end
    exchange
  end

  def default_exchange
    @default_exchange ||= Exchange.new("", "direct")
  end

  def fanout(name)
    exchange(name, "fanout")
  end

  def direct(name)
    exchange(name, "direct")
  end

  def topic(name)
    exchange(name, "topic")
  end

  def headers(name)
    exchange(name, "headers")
  end

  def queue(name, durable = false, passive = false, exclusive = false,
            auto_delete = false, no_wait = false, args = Protocol::Table.new)
    unless queue = @queues[name]?
      queue = Queue.new(self, name, durable, exclusive, auto_delete, args)
      queue.declare(passive, no_wait)
      @queues[name] = queue
    end
    queue
  end

  private def do_close
    return if @closed
    @closed = true

    @broker.unregister_consumer(@channel)
  end

  def rpc_call(method)
    @broker.send(@channel, method)
    @rpc.receive
  end

  private def register_consumer
    @broker.register_consumer(@channel) do |frame|
      case frame
      when Protocol::MethodFrame
        method = frame.method
        case method
        when Protocol::Channel::Flow
          @broker.send(@channel, Protocol::Channel::FlowOk.new(method.active))
          @flow_callbacks.each {|block| block.call(method.active)}
        when Protocol::Channel::Close
          @broker.send(@channel, Protocol::Channel::CloseOk.new)
          do_close
          @close_callbacks.each {|block| block.call(method.reply_code, method.reply_text)}
        else
          @rpc.send(method)
        end
      when Protocol::HeadersFrame
      when Protocol::BodyFrame
      end
    end
  end
end
