require "../amqp"
require "signal"

COUNT = 20
EXCHANGE_NAME = "basic_get"
QUEUE_NAME = "basic_get"

AMQP::Connection.start do |conn|
  conn.on_close do |code, msg|
    puts "CONNECTION CLOSED: #{code} - #{msg}"
  end

  spawn do
    channel = conn.channel
    channel.on_close do |code, msg|
      puts "PUBLISH CHANNEL CLOSED: #{code} - #{msg}"
    end

    exchange = channel.exchange(EXCHANGE_NAME, "direct", auto_delete: true)
    queue = channel.queue(QUEUE_NAME)
    queue.bind(exchange, queue.name)

    COUNT.times do
      msg = AMQP::Message.new("test message")
      exchange.publish(msg, QUEUE_NAME)
      sleep 0.1
    end
    queue.unbind(exchange, queue.name)
  end

  spawn do
    channel = conn.channel
    channel.on_close do |code, msg|
      puts "GETTER CHANNEL CLOSED: #{code} - #{msg}"
    end

    exchange = channel.exchange(EXCHANGE_NAME, "direct", auto_delete: true)
    queue = channel.queue(QUEUE_NAME)
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
    queue.unbind(exchange, queue.name)
    queue.delete
    conn.loop_break
  end

  Signal.trap(Signal::INT) do
    puts "Exiting..."
    conn.loop_break
  end
  conn.run_loop
end
