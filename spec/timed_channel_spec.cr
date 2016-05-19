require "spec"
require "../src/amqp/timed_channel"

describe "Timed::Channel" do
  describe "TimerChannel" do
    it "should periodically generate time values" do
      timer = Timed::TimerChannel.new(10.milliseconds)
      times = (1..2).map{ timer.receive }
      times.size.should eq(2)
      (times.last - times.first).should be >= 10.milliseconds
    end

    it "should raise exception on send" do
      timer = Timed::TimerChannel.new(10.milliseconds)
      expect_raises(Exception) do
        timer.send Time.now
      end
    end

    it "should not time out" do
      ch = Timed::TimedChannel(Bool).new(1)
      spawn { sleep(0.007); ch.send(true) }
      if ch.receive(10.milliseconds).nil?
        fail "channel should not time out"
      end
    end

    it "should time out" do
      ch = Timed:: TimedChannel(Bool).new(1)
      spawn { sleep(0.1); ch.send(true) }
      unless ch.receive(10.milliseconds).nil?
        fail "channel should time out"
      end
    end
  end
end
