require "../src/amqp"
require "signal"

QUEUE_NAME = "confirm_mode"
STDOUT.sync = true

AMQP::Connection.start do |conn|
  conn.on_close do |code, msg|
    puts "CONNECTION CLOSED: #{code} - #{msg}"
  end

  channel = conn.channel
  channel.on_close do |code, msg|
    puts "CHANNEL CLOSED: #{code} - #{msg}"
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
  queue.delete
  channel.close
end

