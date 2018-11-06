# Extended Channel::Buffered implementation from the standard library by an ability
# to receive from channel with a timeout.
module Timed
  class TimerChannel < Channel(Time)
    def initialize(@interval : Time::Span)
      raise ArgumentError.new("invalid timespan") if @interval.total_nanoseconds == 0
      @start_time = Time.now
      super()
    end

    def send(value : Time)
      raise Exception.new("not implemented")
    end

    private def sleep
      interval = Time.now - @start_time
      interval = @interval - interval
      sleep interval.total_seconds
    end

    private def receive_impl
      until ready?
        yield if @closed
        @receivers << Fiber.current
        sleep
      end

      yield if @closed

      @start_time = Time.now
    end

    def ready?
      Time.now - @start_time > @interval
    end
  end

  class TimedChannel(T) < Channel::Buffered(T)
    def initialize(capacity)
      super(capacity)
    end

    def receive(interval : Time::Span)
      raise ArgumentError.new("invalid timespan") if interval.total_nanoseconds == 0
      start_time = Time.now

      while empty?
        raise ClosedError.new if @closed
        return if expired?(start_time, interval)
        @receivers << Fiber.current
        sleep(start_time, interval)
      end

      @queue.shift.tap do
        Crystal::Scheduler.enqueue @senders
        @senders.clear
      end
    end

    private def expired?(start_time, interval)
      Time.now - start_time > interval
    end

    private def sleep(start_time, interval)
      cur_interval = Time.now - start_time
      interval = interval - cur_interval
      sleep interval.total_seconds
    end
  end
end
