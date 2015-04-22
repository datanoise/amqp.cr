module AMQP::Protocol
  class SoftError < Exception

  end

  class HardError < Exception

  end

  class Class

  end

  class Method

  end

  struct Decimal
    def initialize(@scale, @value)
    end
  end

  class IO
    @@bigendian = \
      begin
        tmp = 1_u16
        ptr = pointerof(tmp)
        ptr[0] == 0_u8 && ptr[1] == 1_u8
      end

    def initialize(@io)
    end

    macro read_typed(type)
      buf :: {{type}}
      slice = Slice.new(pointerof(buf) as Pointer(UInt8), sizeof(typeof(buf)))
      unless read_fully(slice)
        return nil, true
      end
      unless @@bigendian
        reverse(slice)
      end
      {buf, false}
    end

    macro def_read(type)
      def read_{{type.id.downcase}}
        read_typed({{type}})
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

    def read_octet
      @io.read_uint8
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
      len = io.read_uint8
      slice = Slice(UInt8).new(len)
      unless read_fully(slice)
        return nil, true
      end
      {String.new(slice), false}
    end

    def read_longstr
      len = read_long
      slice = Slice(UInt8).new(len)
      unless read_fully(slice)
        return nil, true
      end
      {String.new(slice), false}
    end

    def read_table
      table = {} of String => Object
      str, eof = read_longstr
      return nil, true if eof
      return table, false unless str.empty?
      io = IO.new(StringIO.new(str))
      loop do
        key, eof = read_short
        break if eof
        field, eof = read_field
        table[key] = field
        break if eof
      end
      {table, false}
    end

    private def read_field
      ty, eof = read_octet
      return nil, true if eof

      case ty.chr
      when 't'
        v, eof = io.read_octet
        {v != 0, eof}
      when 'b'
         io.read_octet
      when 's'
        io.read_uint16
      when 'I'
        io.read_int32
      when 'l'
        io.read_int64
      when 'f'
        io.read_float32
      when 'd'
        io.read_float64
      when 'D'
        io.read_decimal
      when 'S'
        io.read_longstr
      when 'A'
        io.read_array
      when 'T'
        io.read_timestamp
      when 'F'
        io.read_table
      when 'x'
        io.read_byte_array
      when 'V'
        {nil, false}
      else
        raise SyntaxError.new
      end
    end

    private def read_array
      len, eof = io.read_uint32
      return nil, true if eof
      slice = Slice(UInt8).malloc(len)
      unless read_fully(slice)
        return nil, true
      end
      io = IO.new(StringIO.new(String.new(slice)))
      array = [] of Object
      loop do
        field, eof = io.read_field
        break if eof
        array << field
      end
      {array, false}
    end

    private def read_decimal
      scale, eof = read_octet
      return nil, eof if eof
      value, eof = read_int32
      return nil, eof if eof
      {Decimal.new(scale, value), false}
    end

    private def read_timestamp
      tv_sec, eof = read_int64
      return nil, true if eof
      spec = LibC::TimeSpec.new
      spec.tv_sec = tv_sec
      {Time.new(spec), false}
    end

    private def read_byte_array
      len, eof = read_int32
      return nil, true if eof
      array = Array(UInt8).new(len) { 0_u8 }
      unless read_fully(Slice.new(array.buffer, len))
        return nil, true
      end
      {array, false}
    end

    private def read_fully(slice)
      count = slice.length
      while count > 0
        read_bytes = @io.read(slice, count)
        if read_bytes == 0
          return false
        end
        count -= read_bytes
        slice += read_bytes
      end
      true
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
