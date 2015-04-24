module AMQP::Protocol
  class SoftError < Exception
  end

  class HardError < Exception
  end

  abstract class Method
    abstract def encode(io)
  end

  struct Decimal
    scale :: UInt8
    value :: Int32

    getter scale, value

    def initialize(@scale, @value)
    end
  end

  alias Field = Nil |
                Bool |
                UInt8 |
                UInt16 |
                UInt32 |
                UInt64 |
                Int32 |
                Int64 |
                Float32 |
                Float64 |
                Decimal |
                String |
                Array(Field) |
                Array(UInt8) |
                Time |
                Hash(String, Field)

  alias Table = Hash(String, Field)

  abstract class Frame
    METHOD    = 1_u8
    HEADERS   = 2_u8
    BODY      = 3_u8
    HEARTBEAT = 8_u8
    FINAL_OCTET = 0xCE_u8

    getter :type
    getter :channel

    def encode(io)
      io.write_octet(@type)
      io.write_short(@channel)
      payload = get_payload()
      io.write_long(payload.length.to_u32)
      io.write(payload)
      io.write_octet(FINAL_OCTET)
    end

    def self.decode(io)
      ty = io.read_octet
      raise ::IO::EOFError.new unless ty
      channel = io.read_short
      raise ::IO::EOFError.new unless channel
      size = io.read_long
      raise ::IO::EOFError.new unless size
      frame = case ty
              when METHOD
                MethodFrame.parse(channel, size, io)
              when HEADERS
                HeadersFrame.parse(channel, size, io)
              when BODY
                BodyFrame.parse(channel, size, io)
              when HEARTBEAT
                HeartbeatFrame.parse(channel, size, io)
              else
                raise FrameError.new "Invalid frame type: #{ty}"
              end
      final = io.read_octet
      unless final == FINAL_OCTET
        raise FrameError.new "Final octet doesn't match"
      end
      frame
    end

    abstract def get_payload: Slice(UInt8)
  end

  class MethodFrame < Frame
    getter method

    def initialize(@channel, @method)
      @type = METHOD
    end

    def self.parse(channel, size, io)
      cls_id = io.read_short
      meth_id = io.read_short
      method = Method.parse_method(cls_id, meth_id, io)
      MethodFrame.new(channel, method)
    end

    def get_payload
      buf = StringIO.new
      buf_io = IO.new(buf)
      @method.id.each {|v| buf_io.write_short(v)}
      @method.encode(buf_io)
      buf.to_s.to_slice
    end
  end

  class HeadersFrame < Frame
    def initialize(@channel)
      @type = HEADERS
    end

    def self.parse(channel, size, io)
      raise "not implemented"
    end

    def get_payload
      raise "not implemented"
    end
  end

  class BodyFrame < Frame
    def initialize(@channel)
      @type = BODY
    end

    def self.parse(channel, size, io)
      raise "not implemented"
    end

    def get_payload
      raise "not implemented"
    end
  end

  class HeartbeatFrame < Frame
    def initialize()
      @channel = 0_u16
      @type = HEARTBEAT
    end

    def self.parse(channel, size, io)
      unless channel == 0
        raise FrameError.new("Heartbeat frame must have a channel number of zero")
      end
      unless size == 0
        raise FrameError.new("Heartbeat frame must have an empty payload")
      end
      HeartbeatFrame.new
    end

    def get_payload
      Slice(UInt8).new(0)
    end
  end

  class IO
    @@bigendian = \
      begin
        tmp = 1_u16
        ptr = pointerof(tmp)
        ptr[0] == 0_u8 && ptr[1] == 1_u8
      end

    getter eof

    def initialize(@io)
      @eof = false
    end

    macro read_typed(type)
      buf :: {{type}}
      slice = Slice.new(pointerof(buf) as Pointer(UInt8), sizeof(typeof(buf)))
      unless read(slice)
        return nil
      end
      unless @@bigendian
        reverse(slice)
      end
      buf
    end

    macro def_read(type)
      def read_{{type.id.downcase}}
        read_typed({{type}})
      end
    end

    macro def_write(type)
      def write_{{type.id.downcase}}(v: {{type.id}})
        write(v)
      end
    end

    def_read(UInt8)
    def_read(UInt16)
    def_read(UInt32)
    def_read(UInt64)
    def_read(Int16)
    def_read(Int32)
    def_read(Int64)
    def_read(Float32)
    def_read(Float64)

    def read(slice: Slice(UInt8))
      raise ::IO::EOFError.new if @eof
      count = slice.length
      while count > 0
        read_bytes = @io.read(slice, count)
        if read_bytes == 0
          @eof = true
          return false
        end
        count -= read_bytes
        slice += read_bytes
      end
      true
    end

    def read_octet
      read_uint8
    end

    def read_short
      read_uint16
    end

    def read_long
      read_uint32
    end

    def read_longlong
      read_uint64
    end

    def read_shortstr
      len = read_uint8
      return nil unless len
      slice = Slice(UInt8).new(len.to_i32)
      unless read(slice)
        return nil
      end
      String.new(slice)
    end

    def read_longstr
      len = read_uint32
      return nil unless len
      slice = Slice(UInt8).new(len.to_i32)
      unless read(slice)
        return nil
      end
      String.new(slice)
    end

    def read_table
      table = {} of String => Field
      str = read_longstr
      return nil unless str
      return table if str.empty?
      io = IO.new(StringIO.new(str))
      loop do
        key = io.read_shortstr
        break unless key
        break if io.eof
        field = io.read_field
        break if io.eof
        table[key] = field
      end
      table
    end

    protected def read_field
      ty = read_octet
      return nil unless ty

      case ty.chr
      when 't'
        v = read_octet
        v != 0
      when 'b'
        read_octet
      when 's'
        read_uint16
      when 'I'
        read_int32
      when 'l'
        read_int64
      when 'f'
        read_float32
      when 'd'
        read_float64
      when 'D'
        read_decimal
      when 'S'
        read_longstr
      when 'A'
        read_array
      when 'T'
        read_timestamp
      when 'F'
        read_table
      when 'x'
        read_byte_array
      when 'V'
        nil
      else
        raise SyntaxError.new
      end
    end

    def write(slice: Slice(UInt8))
      @io.write(slice)
    end

    def write(v)
      slice = Slice.new(pointerof(v) as Pointer(UInt8), sizeof(typeof(v)))
      if slice.length > 1 && !@@bigendian
        reverse(slice)
      end
      write(slice)
    end

     def_write(UInt8)
     def_write(UInt16)
     def_write(UInt32)
     def_write(UInt64)
     def_write(Int16)
     def_write(Int32)
     def_write(Int64)
     def_write(Float32)
     def_write(Float64)

     def write_octet(v: UInt8)
       write(v)
     end

     def write_octet(v: Char)
       write(v.ord.to_u8)
     end

     def write_short(v: UInt16)
       write(v)
     end

     def write_long(v: UInt32)
       write(v)
     end

     def write_longlong(v: UInt64)
       write(v)
     end

     def write_shortstr(v: String)
       len = v.bytesize.to_u8
       if len < v.bytesize
         raise ContentTooLarge.new
       end
       write(len)
       @io.print(v)
     end

     def write_longstr(v: String)
       len = v.bytesize.to_u32
       write(len)
       @io.print(v)
     end

     def write_table(table: Table)
       buf = StringIO.new
       io = IO.new(buf)
       table.each do |key, value|
         io.write_shortstr(key)
         io.write_field(value)
       end
       write_longstr(buf.to_s)
     end

     protected def write_field(field)
       case field
       when Bool
         write_octet('t')
         write_octet(field ? 1_u8 : 0_u8)
       when UInt8
         write_octet('b')
         write(field)
       when UInt16
         write_octet('s')
         write(field)
       when UInt32
         write_octet('I')
         write(field)
       when UInt64
         write_octet('l')
         write(field)
       when Float32
         write_octet('f')
         write(field)
       when Float64
         write_octet('d')
       when String
         write_octet('S')
         write_longstr(field)
       when Array(UInt8)
         write_octet('x')
         write(field.length.to_i32)
         @io.write(Slice.new(field.buffer, field.length))
       when Array
         write_octet('A')
         write(field.length.to_i32)
         field.each {|v| write_field(v)}
       when Time
         write_octet('T')
         write(field.to_i.to_i64)
       when Hash
         write_octet('F')
         write_table(field)
       else
         raise FrameError.new("invalid type #{typeof(field)}")
       end
    end

    protected def read_array
      len = read_uint32
      return nil unless len
      slice = Slice(UInt8).new(len.to_i32)
      unless read(slice)
        return nil
      end
      io = IO.new(StringIO.new(String.new(slice)))
      array = [] of Field
      loop do
        field = io.read_field
        break if io.eof
        array << field
      end
      array
    end

    protected def read_decimal
      scale = read_octet
      return nil unless scale
      value = read_int32
      return nil unless value
      Decimal.new(scale, value)
    end

    protected def read_timestamp
      tv_sec = read_int64
      return nil unless tv_sec
      spec = LibC::TimeSpec.new
      spec.tv_sec = tv_sec
      Time.new(spec)
    end

    protected def read_byte_array
      len = read_int32
      return nil unless len
      array = Array(UInt8).new(len) { 0_u8 }
      unless read(Slice.new(array.buffer, len))
        return nil
      end
      array
    end

    private def reverse(slice)
      i = 0
      j = slice.length - 1
      while i < j
        slice.to_unsafe.swap i, j
        i += 1
        j -= 1
      end
    end
  end
end
