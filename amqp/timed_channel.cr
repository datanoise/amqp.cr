class BufferedChannel(T)
  def receive(timeout)
    start_time = Time.now
    while empty?
      diff = Time.now - start_time
      if diff > timeout
        return nil
      else
        Scheduler.sleep(timeout.total_seconds)
      end
      @receivers << Fiber.current
      Scheduler.reschedule
    end

    @queue.shift.tap do
      Scheduler.enqueue @senders
      @senders.clear
    end
  end
end

class UnbufferedChannel(T)
  def receive(timeout)
    start_time = Time.now
    while @value.nil?
      diff = Time.now - start_time
      if diff > timeout
        return nil
      else
        Scheduler.sleep(timeout.total_seconds)
      end
      @receivers << Fiber.current
      if sender = @senders.pop?
        sender.resume
      else
        Scheduler.reschedule
      end
    end

    @value.not_nil!.tap do
      @value = nil
      Scheduler.enqueue @sender.not_nil!
    end
  end
end
