require "spec"
require "../src/amqp.cr"

describe AMQP::Connection do
  it "can communicate all table data types" do
    AMQP::Connection.start do |conn|
      ch = conn.channel
      headers = AMQP::Protocol::Table{
        "bool" => true,
        "int8" => Int8::MAX,
        "uint8" => UInt8::MAX,
        "int16" => Int16::MAX,
        "uint16" => UInt16::MAX,
        "int32" => Int32::MAX,
        "uint32" => UInt32::MAX,
        "int64" => Int64::MAX,
        "float32" => 0.0_f32,
        #"float64" => 0.0_f64,
        "string" => "a" * 257,
        "array" => [
          true,
          Int8::MAX,
          UInt8::MAX,
          Int16::MAX,
          UInt16::MAX,
          Int32::MAX,
          UInt32::MAX,
          Int64::MAX,
          0.0_f32,
          #0.0_f64,
          "a" * 257,
          "aaaa".to_slice,
          Time.epoch(Time.utc_now.epoch),
          AMQP::Protocol::Table{ "key" => "value" },
          nil,
        ] of AMQP::Protocol::Field,
        "byte_array" => "aaaa".to_slice,
        "time" => Time.epoch(Time.utc_now.epoch),
        "hash" => AMQP::Protocol::Table{ "key" => "value" },
        "nil" => nil,
      }
      msg = AMQP::Message.new("props", AMQP::Protocol::Properties.new(headers: headers))
      q = ch.queue("", auto_delete: false, durable: true, exclusive: false, passive: false)
      x = ch.exchange("", "direct", passive: true)
      x.publish msg, q.name
      msg = q.get
      msg.should_not be_nil
      msg.not_nil!.properties.headers.should eq(headers)
    end
  end
end
