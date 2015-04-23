require "socket"
require "./protocol"
require "./spec091"

module AMQP
  class Connection
    ProtocolHeader = ['A'.ord, 'M'.ord, 'Q'.ord, 'P'.ord, 0, 0, 9, 1].map(&.to_u8)

    def initialize(@host = "127.0.0.1", @port = 5672)
      @socket = TCPSocket.new(@host, @port)
      @io = Protocol::IO.new(@socket)
    end

    def open
      write_protocol_header
      frame = Protocol::Frame.decode(@io)
      if frame.is_a?(Protocol::MethodFrame)
        method = frame.method
        if method.is_a?(Protocol::Connection::Start)
          puts "Version: #{method.version_major}.#{method.version_minor}"
          puts "Properties:"
          puts method.server_properties
          puts "Mechanisms:"
          puts method.mechanisms
        end
      end
    end

    private def write_protocol_header
      @io.write(Slice.new(ProtocolHeader.buffer, ProtocolHeader.length))
    end
  end
end

conn = AMQP::Connection.new
conn.open

