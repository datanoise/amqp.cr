require "../src/amqp"

COUNT = 20
EXCHANGE_NAME = "sender_receiver"
QUEUE_NAME = "sender_receiver"
STDOUT.sync = true

AMQP::Connection.start do |conn|
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
    body = String.new(msg.body)
    puts "Received msg (1): #{body}"
    msg.ack
  end
  queue.subscribe do |msg|
    body = String.new(msg.body)
    puts "Received msg (2): #{body}"
    msg.ack
  end

  COUNT.times do |idx|
    msg = AMQP::Message.new("test message: #{idx+1}")
    exchange.publish(msg, QUEUE_NAME)
    sleep 0.1
  end

  queue.delete
  exchange.delete
  channel.close
end
