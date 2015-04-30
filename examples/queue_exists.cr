require "../src/amqp"
require "signal"

queue_name = ARGV.first

AMQP::Connection.start do |conn|
  if conn.queue_exists?(queue_name)
    puts "Queue #{queue_name} exists"
  else
    puts "Queue #{queue_name} does not exist"
  end
end
