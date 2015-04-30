require "spec"
require "../src/amqp/timed_channel"

describe "Timed::Channel" do
  describe "TimerChannel" do
    it "should periodically generate time values" do
      timer = Timed::TimerChannel.new(10.milliseconds)
      times = (1..2).map{ timer.receive }
      times.length.should eq(2)
      (times.last - times.first).should be >= 10.milliseconds
    end

    it "should raise exception on send" do
      timer = Timed::TimerChannel.new(10.milliseconds)
      expect_raises(Timed::ChannelError) do
        timer.send Time.now
      end
    end

    it "should be able to cloe timer channel" do
      timer = Timed::TimerChannel.new(10.milliseconds)
      timer.close
      expect_raises(Timed::ChannelClosed) do
        timer.receive
      end
    end

    it "should time out Channel.select" do
      timer = Timed::TimerChannel.new(5.milliseconds)
      ch = Timed::Channel(Bool).new
      spawn { sleep(0.007); ch.send(true) }

      case Timed::Channel.select(ch, timer)
      when timer
      when ch
        fail "channel should not be ready"
      end
    end

    it "should not time out Channel.select if there is a send issued" do
      timer = Timed::TimerChannel.new(7.milliseconds)
      ch = Timed::Channel(Bool).new
      spawn { sleep(0.005); ch.send(true) }

      case Timed::Channel.select(ch, timer)
      when timer
        fail "timeout is received"
      when ch
        ch.receive.should be_true
      end
    end
  end

  it "should be able to close a channel while receiving" do
    ch = Timed::Channel(Bool).new
    spawn { sleep(0.005); ch.close }
    expect_raises(Timed::ChannelClosed) do
      ch.receive
    end
  end

  it "should be able to close a channel while sending" do
    ch = Timed::Channel(Bool).new
    spawn { sleep(0.005); ch.close }

    # send to fill the channel
    ch.send(true)

    expect_raises(Timed::ChannelClosed) do
      ch.send(true)
    end
  end
end
