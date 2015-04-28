require "../amqp"
require "signal"

COUNT = 20
EXCHANGE_NAME = "sender_receiver"
QUEUE_NAME = "sender_receiver"

conn = AMQP::Connection.new #(AMQP::Config.new(logger_level: Logger::DEBUG))
puts "Started"

conn.on_close do |code, msg|
  puts "CONNECTION CLOSED: #{code} - #{msg}"
end

channel = conn.channel
channel.on_close do |code, msg|
  puts "CHANNEL CLOSED: #{code} - #{msg}"
end

exchange = channel.direct(EXCHANGE_NAME)
queue = channel.queue(QUEUE_NAME)
queue.bind(exchange, queue.name)
queue.subscribe do |msg|
  puts "Received msg (1): #{msg.body}"
  msg.ack
end
queue.subscribe do |msg|
  puts "Received msg (2): #{msg.body}"
  msg.ack
end

COUNT.times do |idx|
  msg = AMQP::Message.new("test message: #{idx+1}")
  exchange.publish(msg, QUEUE_NAME)
  sleep 0.1
end

Signal.trap(Signal::INT) do
  puts "Exiting..."
  conn.loop_break
end
conn.run_loop

queue.delete
exchange.delete
channel.close
conn.close

puts "Finished"
