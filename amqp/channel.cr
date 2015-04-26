require "./protocol"
require "./spec091"

class AMQP::Channel

  # TODO:implement better channel id allocation algorithm
  @@next_channel = 0_u16
  protected def self.next_channel
    @@next_channel += 1
    @@next_channel
  end

  alias Methods = Protocol::Channel
  getter closed

  def initialize(@engine)
    @channel = Channel.next_channel
    @msgs = ::Channel(Protocol::Method).new
    @rpc = ::Channel(Protocol::Method).new
    @flows = [] of Bool ->
    @closed = false

    register_consumer
    open = Methods::Open.new("")
    @engine.send(@channel, open)
    open_ok = @rpc.receive
    unless open_ok.is_a?(Methods::OpenOk)
      raise Protocol::FrameError.new("Unexpected method received: #{open_ok}")
    end
  end

  def register_flow(&block: Bool ->)
    @flows << block
    @flows.length - 1
  end

  def unregister_flow(id)
    @flows.delete(id)
  end

  def flow(active)
    flow = Methods::Flow.new(active)
    @engine.send(@channel, flow)
    flow_ok = @rpc.receive
    unless flow_ok.is_a?(Methods::FlowOk)
      raise Protocol::FrameError.new("Unexpected method received: #{flow_ok}")
    end
    flow_ok.active
  end

  def close(code = Protocol::REPLY_SUCCESS, msg = "bye", cls_id = 0, mth_id = 0)
    @engine.send(@channel, Methods::Close.new(code.to_u16, msg, cls_id.to_u16, mth_id.to_u16))
    close_ok = @rpc.receive
  end

  private def close_internal
    return if @closed
    @closed = true

    @engine.unregister_consumer(@channel)
  end

  private def register_consumer
    @engine.register_consumer(@channel) do |frame|
      case frame
      when Protocol::MethodFrame
        method = frame.method
        case method
        when Methods::Flow
          @engine.send(@channel, Methods::FlowOk.new(method.active))
          @flows.each {|block| block.call method.active}
        when Methods::Close
          puts "Received channel close, #{method}"
          @engine.send(@channel, Methods::CloseOk.new)
          close_internal
        else
          @rpc.send(method)
        end
      when Protocol::HeadersFrame
      when Protocol::BodyFrame
      end
    end
  end
end
