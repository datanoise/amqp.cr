require "./amqp"
require "signal"

QUEUE_NAME = "confirm_mode"

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

  channel.on_confirm do |tag, ack|
    puts " #{tag} tag #{ack ? "acked" : "nacked"}"
  end
  channel.confirm

  10.times do
    msg = AMQP::Message.new("test message")
    exchange.publish(msg, QUEUE_NAME)
  end
end
puts "Finished"
