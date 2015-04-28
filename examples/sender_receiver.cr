require "../amqp"
require "signal"

COUNT = 20

conn = AMQP::Connection.new
puts "Started"

Signal.trap(Signal::INT) do
  puts "Exiting..."
  spawn do
    conn.loop_break
  end
end

conn.on_close do |code, msg|
  puts "CONNECTION CLOSED: #{code} - #{msg}"
end

channel = conn.channel
channel.on_close do |code, msg|
  puts "CHANNEL CLOSED: #{code} - #{msg}"
end

exchange = channel.direct("my_exchange")
queue = channel.queue("my_queue")
queue.bind(exchange, queue.name)
queue.subscribe do |msg|
  puts "Received msg (1): #{msg.body}"
  msg.ack
end
queue.subscribe do |msg|
  puts "Received msg (2): #{msg.body}"
  msg.ack
end

COUNT.times do
  msg = AMQP::Message.new("test message")
  exchange.publish(msg, "my_queue")
  sleep 0.1
end

conn.run_loop

queue.delete
exchange.delete
channel.close
conn.close

puts "Finished"
