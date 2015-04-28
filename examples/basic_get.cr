require "../amqp"
require "signal"

COUNT = 20

AMQP::Connection.start do |conn|
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

  spawn do
    channel = conn.channel
    channel.on_close do |code, msg|
      puts "PUBLISH CHANNEL CLOSED: #{code} - #{msg}"
    end

    exchange = channel.exchange("my_exchange", "direct", auto_delete: true)
    queue = channel.queue("my_queue", auto_delete: true)
    queue.bind(exchange, queue.name)

    COUNT.times do
      msg = AMQP::Message.new("test message")
      exchange.publish(msg, "my_queue")
      sleep 0.1
    end
  end

  spawn do
    channel = conn.channel
    channel.on_close do |code, msg|
      puts "GETTER CHANNEL CLOSED: #{code} - #{msg}"
    end

    exchange = channel.exchange("my_exchange", "direct", auto_delete: true)
    queue = channel.queue("my_queue", auto_delete: true)
    queue.bind(exchange, queue.name)

    counter = 0
    loop do
      msg = queue.get
      next unless msg
      counter += 1
      puts "Received msg: #{msg.body}. Count: #{msg.message_count}"
      msg.ack
      break if counter == COUNT
      sleep 0.5
    end
  end

end
puts "Finished"
