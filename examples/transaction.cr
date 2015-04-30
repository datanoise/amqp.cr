require "../amqp"
require "signal"

QUEUE_NAME = "tx_queue"

AMQP::Connection.start(AMQP::Config.new(log_level: Logger::DEBUG)) do |conn|
  puts "Started"
  Signal.trap(Signal::INT) do
    puts "Exiting..."
    conn.loop_break
  end

  conn.on_close do |code, msg|
    puts "CONNECTION CLOSED: #{code} - #{msg}"
  end

  channel = conn.channel
  channel.on_close do |code, msg|
    puts "PUBLISH CHANNEL CLOSED: #{code} - #{msg}"
  end

  exchange = channel.default_exchange
  queue = channel.queue(QUEUE_NAME, auto_delete: true)

  channel.tx
  10.times do
    msg = AMQP::Message.new("test message")
    exchange.publish(msg, QUEUE_NAME)
  end
  channel.rollback

  if queue.get
    puts "first transaction failed to rollback"
  else
    puts "first transaction worked"
  end

  channel.tx
  msg = AMQP::Message.new("test message")
  exchange.publish(msg, QUEUE_NAME)
  channel.commit
  if queue.get
    puts "second transaction worked"
  else
    puts "second transaction failed"
  end
end
puts "Finished"
