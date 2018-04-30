module AMQP::Protocol

  # 0      1         3             7                  size+7 size+8
  # +------+---------+-------------+  +------------+  +-----------+
  # | type | channel |     size    |  |  payload   |  | frame-end |
  # +------+---------+-------------+  +------------+  +-----------+
  #  octet   short         long         size octets       octet
  FRAME_HEADER_SIZE = 1 + 2 + 4 + 1

  class SoftError < Exception
  end

  class HardError < Exception
  end

  abstract class Method
    abstract def encode(io)
  end

  struct Decimal
    getter scale, value

    def initialize(@scale : UInt8, @value : Int32)
    end
  end

  alias Field = Nil |
                Bool |
                UInt8 |
                UInt16 |
                UInt32 |
                Int8 |
                Int16 |
                Int32 |
                Int64 |
                Float32 |
                Float64 |
                Decimal |
                String |
                Array(Field) |
                Array(UInt8) |
                Slice(UInt8) |
                Time |
                Hash(String, Field)

  alias Table = Hash(String, Field)

  struct Properties
    FLAG_CONTENT_TYPE     = 0x8000_u16
    FLAG_CONTENT_ENCODING = 0x4000_u16
    FLAG_HEADERS          = 0x2000_u16
    FLAG_DELIVERY_MODE    = 0x1000_u16
    FLAG_PRIORITY         = 0x0800_u16
    FLAG_CORRELATION_ID   = 0x0400_u16
    FLAG_REPLY_TO         = 0x0200_u16
    FLAG_EXPIRATION       = 0x0100_u16
    FLAG_MESSAGE_ID       = 0x0080_u16
    FLAG_TIMESTAMP        = 0x0040_u16
    FLAG_TYPE             = 0x0020_u16
    FLAG_USER_ID          = 0x0010_u16
    FLAG_APP_ID           = 0x0008_u16
    FLAG_RESERVED1        = 0x0004_u16

    property content_type
    property content_encoding
    property headers
    property delivery_mode
    property priority
    property correlation_id
    property reply_to
    property expiration
    property message_id
    property timestamp
    property type
    property user_id
    property app_id
    property reserved1

    def initialize(@content_type = "",
                   @content_encoding = "",
                   @headers = Protocol::Table.new,
                   @delivery_mode = 0_u8,
                   @priority = 0_u8,
                   @correlation_id = "",
                   @reply_to = "",
                   @expiration = "",
                   @message_id = "",
                   @timestamp = Time.epoch(0),
                   @type = "",
                   @user_id = "",
                   @app_id = "",
                   @reserved1 = "")
    end

    def decode(flags, io)
      if flags & FLAG_CONTENT_TYPE > 0
        content_type = io.read_shortstr
        raise ::IO::EOFError.new unless content_type
        @content_type = content_type
      end
      if flags & FLAG_CONTENT_ENCODING > 0
        content_encoding = io.read_shortstr
        raise ::IO::EOFError.new unless content_encoding
        @content_encoding = content_encoding
      end
      if flags & FLAG_HEADERS > 0
        headers = io.read_table
        raise ::IO::EOFError.new unless headers
        @headers = headers
      end
      if flags & FLAG_DELIVERY_MODE > 0
        delivery_mode = io.read_octet
        raise ::IO::EOFError.new unless delivery_mode
        @delivery_mode = delivery_mode
      end
      if flags & FLAG_PRIORITY > 0
        priority = io.read_octet
        raise ::IO::EOFError.new unless priority
        @priority = priority
      end
      if flags & FLAG_CORRELATION_ID > 0
        correlation_id = io.read_shortstr
        raise ::IO::EOFError.new unless correlation_id
        @correlation_id = correlation_id
      end
      if flags & FLAG_REPLY_TO > 0
        reply_to = io.read_shortstr
        raise ::IO::EOFError.new unless reply_to
        @reply_to = reply_to
      end
      if flags & FLAG_EXPIRATION > 0
        expiration = io.read_shortstr
        raise ::IO::EOFError.new unless expiration
        @expiration = expiration
      end
      if flags & FLAG_MESSAGE_ID > 0
        message_id = io.read_shortstr
        raise ::IO::EOFError.new unless message_id
        @message_id = message_id
      end
      if flags & FLAG_TIMESTAMP > 0
        timestamp = io.read_timestamp
        raise ::IO::EOFError.new unless timestamp
        @timestamp = timestamp
      end
      if flags & FLAG_TYPE > 0
        type = io.read_shortstr
        raise ::IO::EOFError.new unless type
        @type = type
      end
      if flags & FLAG_USER_ID > 0
        user_id = io.read_shortstr
        raise ::IO::EOFError.new unless user_id
        @user_id = user_id
      end
      if flags & FLAG_APP_ID > 0
        app_id = io.read_shortstr
        raise ::IO::EOFError.new unless app_id
        @app_id = app_id
      end
      if flags & FLAG_RESERVED1 > 0
        reserved1 = io.read_shortstr
        raise ::IO::EOFError.new unless reserved1
        @reserved1 = reserved1
      end
    end

    def encode(io)
      flags = 0_u16
      flags = flags | FLAG_CONTENT_TYPE     unless @content_type.empty?
      flags = flags | FLAG_CONTENT_ENCODING unless @content_encoding.empty?
      flags = flags | FLAG_HEADERS          unless @headers.empty?
      flags = flags | FLAG_DELIVERY_MODE    unless @delivery_mode == 0
      flags = flags | FLAG_PRIORITY         unless @priority == 0
      flags = flags | FLAG_CORRELATION_ID   unless @correlation_id.empty?
      flags = flags | FLAG_REPLY_TO         unless @reply_to.empty?
      flags = flags | FLAG_EXPIRATION       unless @expiration.empty?
      flags = flags | FLAG_MESSAGE_ID       unless @message_id.empty?
      flags = flags | FLAG_TIMESTAMP        unless @timestamp.epoch == 0
      flags = flags | FLAG_TYPE             unless @type.empty?
      flags = flags | FLAG_USER_ID          unless @user_id.empty?
      flags = flags | FLAG_APP_ID           unless @app_id.empty?
      flags = flags | FLAG_RESERVED1        unless @reserved1.empty?

      io.write_short(flags)

      io.write_shortstr(@content_type)     unless @content_type.empty?
      io.write_shortstr(@content_encoding) unless @content_encoding.empty?
      io.write_table(@headers)             unless @headers.empty?
      io.write_octet(@delivery_mode.to_u8) unless @delivery_mode == 0
      io.write_octet(@priority.to_u8)      unless @priority == 0
      io.write_shortstr(@correlation_id)   unless @correlation_id.empty?
      io.write_shortstr(@reply_to)         unless @reply_to.empty?
      io.write_shortstr(@expiration)       unless @expiration.empty?
      io.write_shortstr(@message_id)       unless @message_id.empty?
      io.write_timestamp(@timestamp)       unless @timestamp.epoch == 0
      io.write_shortstr(@type)             unless @type.empty?
      io.write_shortstr(@user_id)          unless @user_id.empty?
      io.write_shortstr(@app_id)           unless @app_id.empty?
      io.write_shortstr(@reserved1)        unless @reserved1.empty?
    end
  end

  abstract class Frame
    METHOD    = 1_u8
    HEADERS   = 2_u8
    BODY      = 3_u8
    HEARTBEAT = 8_u8
    FINAL_OCTET = 0xCE_u8

    @type : UInt8
    @channel : UInt16

    getter :type
    getter :channel

    def initialize
      @type = AMQP::Protocol::Method
      @channel = 0_u16
    end

    def encode(io)
      io.write_octet(@type)
      io.write_short(@channel)
      payload = get_payload()
      io.write_long(payload.size.to_u32)
      io.write(payload)
      io.write_octet(FINAL_OCTET)
      io.flush
    end

    def self.decode(io)
      ty = io.read_octet
      raise ::IO::EOFError.new unless ty
      channel = io.read_short
      raise ::IO::EOFError.new unless channel
      size = io.read_long
      raise ::IO::EOFError.new unless size
      body = Slice(UInt8).new(size.to_i32)
      io.read(body)
      raise ::IO::EOFError.new if io.eof
      final = io.read_octet
      unless final == FINAL_OCTET
        raise FrameError.new "Final octet doesn't match"
      end
      body_io = IO.new(::IO::Memory.new(String.new body))
      frame = case ty
              when METHOD
                MethodFrame.parse(channel, size, body_io)
              when HEADERS
                HeaderFrame.parse(channel, size, body_io)
              when BODY
                BodyFrame.parse(channel, size, body_io)
              when HEARTBEAT
                HeartbeatFrame.parse(channel, size, body_io)
              else
                raise FrameError.new "Invalid frame type: #{ty}"
              end
      frame
    end

    abstract def get_payload : Slice(UInt8)
  end

  class MethodFrame < Frame
    getter method

    def initialize(@channel : UInt16, @method : AMQP::Protocol::Method)
      @type = METHOD
    end

    def self.parse(channel, size, io)
      cls_id = io.read_short
      meth_id = io.read_short
      method = Method.parse_method(cls_id, meth_id, io)
      new(channel, method)
    end

    def get_payload
      buf = ::IO::Memory.new
      buf_io = IO.new(buf)
      @method.id.each {|v| buf_io.write_short(v)}
      @method.encode(buf_io)
      buf.to_s.to_slice
    end

    def to_s(io)
      io << "MethodFrame(#{@channel}): " << @method
    end
  end

  class HeaderFrame < Frame
    getter cls_id
    getter weight
    getter body_size
    getter properties

    def initialize(@channel : UInt16, @cls_id : UInt16, @weight : UInt16, @body_size : UInt64, @properties = Properties.new)
      @type = HEADERS
    end

    def self.parse(channel, size, io)
      cls_id = io.read_short
      raise ::IO::EOFError.new unless cls_id
      weight = io.read_short
      raise ::IO::EOFError.new unless weight
      body_size = io.read_longlong
      raise ::IO::EOFError.new unless body_size
      flags = io.read_short
      raise ::IO::EOFError.new unless flags
      new(channel, cls_id, weight, body_size).tap &.decode_properties(flags, io)
    end

    def get_payload
      buf = ::IO::Memory.new
      io = IO.new(buf)
      io.write_short(@cls_id)
      io.write_short(@weight)
      io.write_longlong(@body_size)
      @properties.encode(io)
      buf.to_s.to_slice
    end

    protected def decode_properties(flags, io)
      @properties.decode(flags, io)
    end

    def to_s(io)
      io << "HeaderFrame(#{@channel}): " << "cls_id: #{@cls_id}, weight: #{@weight}, body_size: #{@body_size}"
      io << ", properties: #{@properties}"
    end
  end

  class BodyFrame < Frame
    getter body

    def initialize(@channel : UInt16, @body : Slice(UInt8))
      @type = BODY
    end

    def self.parse(channel, size, io)
      body = Slice(UInt8).new(size.to_i32)
      unless io.read(body)
        raise ::IO::EOFError.new
      end
      new(channel, body)
    end

    def get_payload
      @body
    end

    def to_s(io)
      io << "BodyFrame(#{@channel}): " << @body
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
      new
    end

    def get_payload
      Slice(UInt8).new(0)
    end

    def to_s(io)
      io << "HeartbeatFrame(#{@channel})"
    end
  end

  class IO
    @@bigendian : Bool = \
      begin
        tmp = 1_u16
        ptr = pointerof(tmp)
        ptr[0] == 0_u8 && ptr[1] == 1_u8
      end

    getter eof

    def initialize(@io : ::IO::Memory)
      @eof = false
    end

    def initialize(@io : Socket)
      @eof = false
    end

    macro read_typed(type)
      buf = uninitialized {{type}}
      slice = Slice.new(pointerof(buf).as(Pointer(UInt8)), sizeof(typeof(buf)))
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
      def write_{{type.id.downcase}}(v : {{type.id}})
        write(v)
      end
    end

    def_read(UInt8)
    def_read(UInt16)
    def_read(UInt32)
    def_read(UInt64)
    def_read(Int8)
    def_read(Int16)
    def_read(Int32)
    def_read(Int64)
    def_read(Float32)
    def_read(Float64)

    def read(slice : Slice(UInt8))
      raise ::IO::EOFError.new if @eof
      count = slice.size
      while count > 0
        read_bytes = @io.read(slice)
        if read_bytes == 0
          @eof = true
          return false
        elsif read_bytes < 0
          raise Errno.new("IO ERROR")
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
      io = IO.new(::IO::Memory.new(str))
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
        read_octet != 0_u8
      when 'b'
        read_int8
      when 'B'
        read_uint8
      when 's'
        read_int16
      when 'u'
        read_uint16
      when 'I'
        read_int32
      when 'i'
        read_uint32
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
        raise FrameError.new("Unknown field type '#{ty.chr}'")
      end
    end

    def write(slice : Slice(UInt8))
      @io.write(slice)
    end

    def write(v)
      slice = Slice.new(pointerof(v).as(Pointer(UInt8)), sizeof(typeof(v)))
      if slice.size > 1 && !@@bigendian
        reverse(slice)
      end
      write(slice)
    end

     def_write(UInt8)
     def_write(UInt16)
     def_write(UInt32)
     def_write(UInt64)
     def_write(Int8)
     def_write(Int16)
     def_write(Int32)
     def_write(Int64)
     def_write(Float32)
     def_write(Float64)

     def write_octet(v : UInt8)
       write(v)
     end

     def write_octet(v : Char)
       write(v.ord.to_u8)
     end

     def write_short(v : UInt16)
       write(v)
     end

     def write_long(v : UInt32)
       write(v)
     end

     def write_longlong(v : UInt64)
       write(v)
     end

     def write_shortstr(v : String)
       len = v.bytesize.to_u8
       if len < v.bytesize
         raise ContentTooLarge.new
       end
       write(len)
       @io.print(v)
     end

     def write_longstr(v : String)
       len = v.bytesize.to_u32
       write(len)
       @io.print(v)
     end

     def write_table(table : Table)
       buf = ::IO::Memory.new
       io = IO.new(buf)
       table.each do |key, value|
         io.write_shortstr(key)
         io.write_field(value)
       end
       write_longstr(buf.to_s)
     end

     def write_timestamp(v : Time)
       write(v.epoch.to_i64)
     end

     protected def write_field(field)
       case field
       when Bool
         write_octet('t')
         write_octet(field ? 1_u8 : 0_u8)
       when Int8
         write_octet('b')
         write(field)
       when UInt8
         write_octet('B')
         write(field)
       when Int16
         write_octet('s')
         write(field)
       when UInt16
         write_octet('u')
         write(field)
       when Int32
         write_octet('I')
         write(field)
       when UInt32
         write_octet('i')
         write(field)
       when Int64
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
       when Slice(UInt8)
         write_octet('x')
         write(field.size.to_i32)
         @io.write(Slice.new(field.to_unsafe, field.size))
       when Array
         write_octet('A')
         mem = ::IO::Memory.new
         io = IO.new(mem)
         field.each { |v| io.write_field(v) }
         write(mem.bytesize.to_i32)
         write mem.to_slice
       when Time
         write_octet('T')
         write_timestamp(field)
       when Hash
         write_octet('F')
         write_table(field)
       when Nil
         write_octet('V')
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
      io = IO.new(::IO::Memory.new(String.new(slice)))
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

    def read_timestamp
      tv_sec = read_int64
      return nil unless tv_sec
      Time.epoch tv_sec
    end

    def flush
      @io.flush
    end

    protected def read_byte_array
      len = read_int32
      return nil unless len
      bytes = Bytes.new(len)
      read(bytes)
      bytes
    end

    private def reverse(slice)
      i = 0
      j = slice.size - 1
      while i < j
        slice.to_unsafe.swap i, j
        i += 1
        j -= 1
      end
    end
  end
end
