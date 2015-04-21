module AMPQ
  FRAME_METHOD = 1
  FRAME_HEADER = 2
  FRAME_BODY = 3
  FRAME_HEARTBEAT = 8
  FRAME_MIN_SIZE = 4096
  FRAME_END = 206
  REPLY_SUCCESS = 200
  class ContentTooLarge < SoftError
    VALUE = 311
  end

  class NoConsumers < SoftError
    VALUE = 313
  end

  class ConnectionForced < HardError
    VALUE = 320
  end

  class InvalidPath < HardError
    VALUE = 402
  end

  class AccessRefused < SoftError
    VALUE = 403
  end

  class NotFound < SoftError
    VALUE = 404
  end

  class ResourceLocked < SoftError
    VALUE = 405
  end

  class PreconditionFailed < SoftError
    VALUE = 406
  end

  class FrameError < HardError
    VALUE = 501
  end

  class SyntaxError < HardError
    VALUE = 502
  end

  class CommandInvalid < HardError
    VALUE = 503
  end

  class ChannelError < HardError
    VALUE = 504
  end

  class UnexpectedFrame < HardError
    VALUE = 505
  end

  class ResourceError < HardError
    VALUE = 506
  end

  class NotAllowed < HardError
    VALUE = 530
  end

  class NotImplemented < HardError
    VALUE = 540
  end

  class InternalError < HardError
    VALUE = 541
  end

  class Connection < Class
    INDEX = 10

    class Start < Method
      INDEX = 10

      def initialize(@version_major, @version_minor, @server_properties, @mechanisms, @locales)
      end

      def id
        [10, 10]
      end

      def wait?
        true
      end

      def self.decode(io)
        version_major = io.read_octet
        version_minor = io.read_octet
        server_properties = io.read_table
        mechanisms = io.read_longstr
        locales = io.read_longstr
        Start.new(version_major, version_minor, server_properties, mechanisms, locales)
      end

      def encode(io)
        io.write_octet(@version_major)
        io.write_octet(@version_minor)
        io.write_table(@server_properties)
        io.write_longstr(@mechanisms)
        io.write_longstr(@locales)
      end
    end

    class StartOk < Method
      INDEX = 11

      def initialize(@client_properties, @mechanism, @response, @locale)
      end

      def id
        [10, 11]
      end

      def wait?
        true
      end

      def self.decode(io)
        client_properties = io.read_table
        mechanism = io.read_shortstr
        response = io.read_longstr
        locale = io.read_shortstr
        StartOk.new(client_properties, mechanism, response, locale)
      end

      def encode(io)
        io.write_table(@client_properties)
        io.write_shortstr(@mechanism)
        io.write_longstr(@response)
        io.write_shortstr(@locale)
      end
    end

    class Secure < Method
      INDEX = 20

      def initialize(@challenge)
      end

      def id
        [10, 20]
      end

      def wait?
        true
      end

      def self.decode(io)
        challenge = io.read_longstr
        Secure.new(challenge)
      end

      def encode(io)
        io.write_longstr(@challenge)
      end
    end

    class SecureOk < Method
      INDEX = 21

      def initialize(@response)
      end

      def id
        [10, 21]
      end

      def wait?
        true
      end

      def self.decode(io)
        response = io.read_longstr
        SecureOk.new(response)
      end

      def encode(io)
        io.write_longstr(@response)
      end
    end

    class Tune < Method
      INDEX = 30

      def initialize(@channel_max, @frame_max, @heartbeat)
      end

      def id
        [10, 30]
      end

      def wait?
        true
      end

      def self.decode(io)
        channel_max = io.read_short
        frame_max = io.read_long
        heartbeat = io.read_short
        Tune.new(channel_max, frame_max, heartbeat)
      end

      def encode(io)
        io.write_short(@channel_max)
        io.write_long(@frame_max)
        io.write_short(@heartbeat)
      end
    end

    class TuneOk < Method
      INDEX = 31

      def initialize(@channel_max, @frame_max, @heartbeat)
      end

      def id
        [10, 31]
      end

      def wait?
        true
      end

      def self.decode(io)
        channel_max = io.read_short
        frame_max = io.read_long
        heartbeat = io.read_short
        TuneOk.new(channel_max, frame_max, heartbeat)
      end

      def encode(io)
        io.write_short(@channel_max)
        io.write_long(@frame_max)
        io.write_short(@heartbeat)
      end
    end

    class Open < Method
      INDEX = 40

      def initialize(@virtual_host, @reserved_1, @reserved_2)
      end

      def id
        [10, 40]
      end

      def wait?
        true
      end

      def self.decode(io)
        virtual_host = io.read_shortstr
        reserved_1 = io.read_shortstr
        bits = io.read_short
        @reserved_2 = bits & (1 << 0)
        Open.new(virtual_host, reserved_1, reserved_2)
      end

      def encode(io)
        io.write_shortstr(@virtual_host)
        io.write_shortstr(@reserved_1)
        bits = 0_u8
        bits = bits | (1 << 0) if @reserved_2
        io.write_short(bits)
      end
    end

    class OpenOk < Method
      INDEX = 41

      def initialize(@reserved_1)
      end

      def id
        [10, 41]
      end

      def wait?
        true
      end

      def self.decode(io)
        reserved_1 = io.read_shortstr
        OpenOk.new(reserved_1)
      end

      def encode(io)
        io.write_shortstr(@reserved_1)
      end
    end

    class Close < Method
      INDEX = 50

      def initialize(@reply_code, @reply_text, @class_id, @method_id)
      end

      def id
        [10, 50]
      end

      def wait?
        true
      end

      def self.decode(io)
        reply_code = io.read_short
        reply_text = io.read_shortstr
        class_id = io.read_short
        method_id = io.read_short
        Close.new(reply_code, reply_text, class_id, method_id)
      end

      def encode(io)
        io.write_short(@reply_code)
        io.write_shortstr(@reply_text)
        io.write_short(@class_id)
        io.write_short(@method_id)
      end
    end

    class CloseOk < Method
      INDEX = 51

      def initialize()
      end

      def id
        [10, 51]
      end

      def wait?
        true
      end

      def self.decode(io)
        CloseOk.new()
      end

      def encode(io)
      end
    end

    class Blocked < Method
      INDEX = 60

      def initialize(@reason)
      end

      def id
        [10, 60]
      end

      def wait?
        false
      end

      def self.decode(io)
        reason = io.read_shortstr
        Blocked.new(reason)
      end

      def encode(io)
        io.write_shortstr(@reason)
      end
    end

    class Unblocked < Method
      INDEX = 61

      def initialize()
      end

      def id
        [10, 61]
      end

      def wait?
        false
      end

      def self.decode(io)
        Unblocked.new()
      end

      def encode(io)
      end
    end

  end
  class Channel < Class
    INDEX = 20

    class Open < Method
      INDEX = 10

      def initialize(@reserved_1)
      end

      def id
        [20, 10]
      end

      def wait?
        true
      end

      def self.decode(io)
        reserved_1 = io.read_shortstr
        Open.new(reserved_1)
      end

      def encode(io)
        io.write_shortstr(@reserved_1)
      end
    end

    class OpenOk < Method
      INDEX = 11

      def initialize(@reserved_1)
      end

      def id
        [20, 11]
      end

      def wait?
        true
      end

      def self.decode(io)
        reserved_1 = io.read_longstr
        OpenOk.new(reserved_1)
      end

      def encode(io)
        io.write_longstr(@reserved_1)
      end
    end

    class Flow < Method
      INDEX = 20

      def initialize(@active)
      end

      def id
        [20, 20]
      end

      def wait?
        true
      end

      def self.decode(io)
        bits = io.read_short
        @active = bits & (1 << 0)
        Flow.new(active)
      end

      def encode(io)
        bits = 0_u8
        bits = bits | (1 << 0) if @active
        io.write_short(bits)
      end
    end

    class FlowOk < Method
      INDEX = 21

      def initialize(@active)
      end

      def id
        [20, 21]
      end

      def wait?
        false
      end

      def self.decode(io)
        bits = io.read_short
        @active = bits & (1 << 0)
        FlowOk.new(active)
      end

      def encode(io)
        bits = 0_u8
        bits = bits | (1 << 0) if @active
        io.write_short(bits)
      end
    end

    class Close < Method
      INDEX = 40

      def initialize(@reply_code, @reply_text, @class_id, @method_id)
      end

      def id
        [20, 40]
      end

      def wait?
        true
      end

      def self.decode(io)
        reply_code = io.read_short
        reply_text = io.read_shortstr
        class_id = io.read_short
        method_id = io.read_short
        Close.new(reply_code, reply_text, class_id, method_id)
      end

      def encode(io)
        io.write_short(@reply_code)
        io.write_shortstr(@reply_text)
        io.write_short(@class_id)
        io.write_short(@method_id)
      end
    end

    class CloseOk < Method
      INDEX = 41

      def initialize()
      end

      def id
        [20, 41]
      end

      def wait?
        true
      end

      def self.decode(io)
        CloseOk.new()
      end

      def encode(io)
      end
    end

  end
  class Exchange < Class
    INDEX = 40

    class Declare < Method
      INDEX = 10

      def initialize(@reserved_1, @exchange, @type, @passive, @durable, @auto_delete, @internal, @no_wait, @arguments)
      end

      def id
        [40, 10]
      end

      def wait?
        true
      end

      def self.decode(io)
        reserved_1 = io.read_short
        exchange = io.read_shortstr
        type = io.read_shortstr
        bits = io.read_short
        @passive = bits & (1 << 0)
        @durable = bits & (1 << 1)
        @auto_delete = bits & (1 << 2)
        @internal = bits & (1 << 3)
        @no_wait = bits & (1 << 4)
        arguments = io.read_table
        Declare.new(reserved_1, exchange, type, passive, durable, auto_delete, internal, no_wait, arguments)
      end

      def encode(io)
        io.write_short(@reserved_1)
        io.write_shortstr(@exchange)
        io.write_shortstr(@type)
        bits = 0_u8
        bits = bits | (1 << 0) if @passive
        bits = bits | (1 << 1) if @durable
        bits = bits | (1 << 2) if @auto_delete
        bits = bits | (1 << 3) if @internal
        bits = bits | (1 << 4) if @no_wait
        io.write_short(bits)
        io.write_table(@arguments)
      end
    end

    class DeclareOk < Method
      INDEX = 11

      def initialize()
      end

      def id
        [40, 11]
      end

      def wait?
        true
      end

      def self.decode(io)
        DeclareOk.new()
      end

      def encode(io)
      end
    end

    class Delete < Method
      INDEX = 20

      def initialize(@reserved_1, @exchange, @if_unused, @no_wait)
      end

      def id
        [40, 20]
      end

      def wait?
        true
      end

      def self.decode(io)
        reserved_1 = io.read_short
        exchange = io.read_shortstr
        bits = io.read_short
        @if_unused = bits & (1 << 0)
        @no_wait = bits & (1 << 1)
        Delete.new(reserved_1, exchange, if_unused, no_wait)
      end

      def encode(io)
        io.write_short(@reserved_1)
        io.write_shortstr(@exchange)
        bits = 0_u8
        bits = bits | (1 << 0) if @if_unused
        bits = bits | (1 << 1) if @no_wait
        io.write_short(bits)
      end
    end

    class DeleteOk < Method
      INDEX = 21

      def initialize()
      end

      def id
        [40, 21]
      end

      def wait?
        true
      end

      def self.decode(io)
        DeleteOk.new()
      end

      def encode(io)
      end
    end

    class Bind < Method
      INDEX = 30

      def initialize(@reserved_1, @destination, @source, @routing_key, @no_wait, @arguments)
      end

      def id
        [40, 30]
      end

      def wait?
        true
      end

      def self.decode(io)
        reserved_1 = io.read_short
        destination = io.read_shortstr
        source = io.read_shortstr
        routing_key = io.read_shortstr
        bits = io.read_short
        @no_wait = bits & (1 << 0)
        arguments = io.read_table
        Bind.new(reserved_1, destination, source, routing_key, no_wait, arguments)
      end

      def encode(io)
        io.write_short(@reserved_1)
        io.write_shortstr(@destination)
        io.write_shortstr(@source)
        io.write_shortstr(@routing_key)
        bits = 0_u8
        bits = bits | (1 << 0) if @no_wait
        io.write_short(bits)
        io.write_table(@arguments)
      end
    end

    class BindOk < Method
      INDEX = 31

      def initialize()
      end

      def id
        [40, 31]
      end

      def wait?
        true
      end

      def self.decode(io)
        BindOk.new()
      end

      def encode(io)
      end
    end

    class Unbind < Method
      INDEX = 40

      def initialize(@reserved_1, @destination, @source, @routing_key, @no_wait, @arguments)
      end

      def id
        [40, 40]
      end

      def wait?
        true
      end

      def self.decode(io)
        reserved_1 = io.read_short
        destination = io.read_shortstr
        source = io.read_shortstr
        routing_key = io.read_shortstr
        bits = io.read_short
        @no_wait = bits & (1 << 0)
        arguments = io.read_table
        Unbind.new(reserved_1, destination, source, routing_key, no_wait, arguments)
      end

      def encode(io)
        io.write_short(@reserved_1)
        io.write_shortstr(@destination)
        io.write_shortstr(@source)
        io.write_shortstr(@routing_key)
        bits = 0_u8
        bits = bits | (1 << 0) if @no_wait
        io.write_short(bits)
        io.write_table(@arguments)
      end
    end

    class UnbindOk < Method
      INDEX = 51

      def initialize()
      end

      def id
        [40, 51]
      end

      def wait?
        true
      end

      def self.decode(io)
        UnbindOk.new()
      end

      def encode(io)
      end
    end

  end
  class Queue < Class
    INDEX = 50

    class Declare < Method
      INDEX = 10

      def initialize(@reserved_1, @queue, @passive, @durable, @exclusive, @auto_delete, @no_wait, @arguments)
      end

      def id
        [50, 10]
      end

      def wait?
        true
      end

      def self.decode(io)
        reserved_1 = io.read_short
        queue = io.read_shortstr
        bits = io.read_short
        @passive = bits & (1 << 0)
        @durable = bits & (1 << 1)
        @exclusive = bits & (1 << 2)
        @auto_delete = bits & (1 << 3)
        @no_wait = bits & (1 << 4)
        arguments = io.read_table
        Declare.new(reserved_1, queue, passive, durable, exclusive, auto_delete, no_wait, arguments)
      end

      def encode(io)
        io.write_short(@reserved_1)
        io.write_shortstr(@queue)
        bits = 0_u8
        bits = bits | (1 << 0) if @passive
        bits = bits | (1 << 1) if @durable
        bits = bits | (1 << 2) if @exclusive
        bits = bits | (1 << 3) if @auto_delete
        bits = bits | (1 << 4) if @no_wait
        io.write_short(bits)
        io.write_table(@arguments)
      end
    end

    class DeclareOk < Method
      INDEX = 11

      def initialize(@queue, @message_count, @consumer_count)
      end

      def id
        [50, 11]
      end

      def wait?
        true
      end

      def self.decode(io)
        queue = io.read_shortstr
        message_count = io.read_long
        consumer_count = io.read_long
        DeclareOk.new(queue, message_count, consumer_count)
      end

      def encode(io)
        io.write_shortstr(@queue)
        io.write_long(@message_count)
        io.write_long(@consumer_count)
      end
    end

    class Bind < Method
      INDEX = 20

      def initialize(@reserved_1, @queue, @exchange, @routing_key, @no_wait, @arguments)
      end

      def id
        [50, 20]
      end

      def wait?
        true
      end

      def self.decode(io)
        reserved_1 = io.read_short
        queue = io.read_shortstr
        exchange = io.read_shortstr
        routing_key = io.read_shortstr
        bits = io.read_short
        @no_wait = bits & (1 << 0)
        arguments = io.read_table
        Bind.new(reserved_1, queue, exchange, routing_key, no_wait, arguments)
      end

      def encode(io)
        io.write_short(@reserved_1)
        io.write_shortstr(@queue)
        io.write_shortstr(@exchange)
        io.write_shortstr(@routing_key)
        bits = 0_u8
        bits = bits | (1 << 0) if @no_wait
        io.write_short(bits)
        io.write_table(@arguments)
      end
    end

    class BindOk < Method
      INDEX = 21

      def initialize()
      end

      def id
        [50, 21]
      end

      def wait?
        true
      end

      def self.decode(io)
        BindOk.new()
      end

      def encode(io)
      end
    end

    class Unbind < Method
      INDEX = 50

      def initialize(@reserved_1, @queue, @exchange, @routing_key, @arguments)
      end

      def id
        [50, 50]
      end

      def wait?
        true
      end

      def self.decode(io)
        reserved_1 = io.read_short
        queue = io.read_shortstr
        exchange = io.read_shortstr
        routing_key = io.read_shortstr
        arguments = io.read_table
        Unbind.new(reserved_1, queue, exchange, routing_key, arguments)
      end

      def encode(io)
        io.write_short(@reserved_1)
        io.write_shortstr(@queue)
        io.write_shortstr(@exchange)
        io.write_shortstr(@routing_key)
        io.write_table(@arguments)
      end
    end

    class UnbindOk < Method
      INDEX = 51

      def initialize()
      end

      def id
        [50, 51]
      end

      def wait?
        true
      end

      def self.decode(io)
        UnbindOk.new()
      end

      def encode(io)
      end
    end

    class Purge < Method
      INDEX = 30

      def initialize(@reserved_1, @queue, @no_wait)
      end

      def id
        [50, 30]
      end

      def wait?
        true
      end

      def self.decode(io)
        reserved_1 = io.read_short
        queue = io.read_shortstr
        bits = io.read_short
        @no_wait = bits & (1 << 0)
        Purge.new(reserved_1, queue, no_wait)
      end

      def encode(io)
        io.write_short(@reserved_1)
        io.write_shortstr(@queue)
        bits = 0_u8
        bits = bits | (1 << 0) if @no_wait
        io.write_short(bits)
      end
    end

    class PurgeOk < Method
      INDEX = 31

      def initialize(@message_count)
      end

      def id
        [50, 31]
      end

      def wait?
        true
      end

      def self.decode(io)
        message_count = io.read_long
        PurgeOk.new(message_count)
      end

      def encode(io)
        io.write_long(@message_count)
      end
    end

    class Delete < Method
      INDEX = 40

      def initialize(@reserved_1, @queue, @if_unused, @if_empty, @no_wait)
      end

      def id
        [50, 40]
      end

      def wait?
        true
      end

      def self.decode(io)
        reserved_1 = io.read_short
        queue = io.read_shortstr
        bits = io.read_short
        @if_unused = bits & (1 << 0)
        @if_empty = bits & (1 << 1)
        @no_wait = bits & (1 << 2)
        Delete.new(reserved_1, queue, if_unused, if_empty, no_wait)
      end

      def encode(io)
        io.write_short(@reserved_1)
        io.write_shortstr(@queue)
        bits = 0_u8
        bits = bits | (1 << 0) if @if_unused
        bits = bits | (1 << 1) if @if_empty
        bits = bits | (1 << 2) if @no_wait
        io.write_short(bits)
      end
    end

    class DeleteOk < Method
      INDEX = 41

      def initialize(@message_count)
      end

      def id
        [50, 41]
      end

      def wait?
        true
      end

      def self.decode(io)
        message_count = io.read_long
        DeleteOk.new(message_count)
      end

      def encode(io)
        io.write_long(@message_count)
      end
    end

  end
  class Basic < Class
    INDEX = 60

    class Qos < Method
      INDEX = 10

      def initialize(@prefetch_size, @prefetch_count, @global)
      end

      def id
        [60, 10]
      end

      def wait?
        true
      end

      def self.decode(io)
        prefetch_size = io.read_long
        prefetch_count = io.read_short
        bits = io.read_short
        @global = bits & (1 << 0)
        Qos.new(prefetch_size, prefetch_count, global)
      end

      def encode(io)
        io.write_long(@prefetch_size)
        io.write_short(@prefetch_count)
        bits = 0_u8
        bits = bits | (1 << 0) if @global
        io.write_short(bits)
      end
    end

    class QosOk < Method
      INDEX = 11

      def initialize()
      end

      def id
        [60, 11]
      end

      def wait?
        true
      end

      def self.decode(io)
        QosOk.new()
      end

      def encode(io)
      end
    end

    class Consume < Method
      INDEX = 20

      def initialize(@reserved_1, @queue, @consumer_tag, @no_local, @no_ack, @exclusive, @no_wait, @arguments)
      end

      def id
        [60, 20]
      end

      def wait?
        true
      end

      def self.decode(io)
        reserved_1 = io.read_short
        queue = io.read_shortstr
        consumer_tag = io.read_shortstr
        bits = io.read_short
        @no_local = bits & (1 << 0)
        @no_ack = bits & (1 << 1)
        @exclusive = bits & (1 << 2)
        @no_wait = bits & (1 << 3)
        arguments = io.read_table
        Consume.new(reserved_1, queue, consumer_tag, no_local, no_ack, exclusive, no_wait, arguments)
      end

      def encode(io)
        io.write_short(@reserved_1)
        io.write_shortstr(@queue)
        io.write_shortstr(@consumer_tag)
        bits = 0_u8
        bits = bits | (1 << 0) if @no_local
        bits = bits | (1 << 1) if @no_ack
        bits = bits | (1 << 2) if @exclusive
        bits = bits | (1 << 3) if @no_wait
        io.write_short(bits)
        io.write_table(@arguments)
      end
    end

    class ConsumeOk < Method
      INDEX = 21

      def initialize(@consumer_tag)
      end

      def id
        [60, 21]
      end

      def wait?
        true
      end

      def self.decode(io)
        consumer_tag = io.read_shortstr
        ConsumeOk.new(consumer_tag)
      end

      def encode(io)
        io.write_shortstr(@consumer_tag)
      end
    end

    class Cancel < Method
      INDEX = 30

      def initialize(@consumer_tag, @no_wait)
      end

      def id
        [60, 30]
      end

      def wait?
        true
      end

      def self.decode(io)
        consumer_tag = io.read_shortstr
        bits = io.read_short
        @no_wait = bits & (1 << 0)
        Cancel.new(consumer_tag, no_wait)
      end

      def encode(io)
        io.write_shortstr(@consumer_tag)
        bits = 0_u8
        bits = bits | (1 << 0) if @no_wait
        io.write_short(bits)
      end
    end

    class CancelOk < Method
      INDEX = 31

      def initialize(@consumer_tag)
      end

      def id
        [60, 31]
      end

      def wait?
        true
      end

      def self.decode(io)
        consumer_tag = io.read_shortstr
        CancelOk.new(consumer_tag)
      end

      def encode(io)
        io.write_shortstr(@consumer_tag)
      end
    end

    class Publish < Method
      INDEX = 40
      CONTENT = true

      def initialize(@reserved_1, @exchange, @routing_key, @mandatory, @immediate)
      end

      def id
        [60, 40]
      end

      def wait?
        false
      end

      def self.decode(io)
        reserved_1 = io.read_short
        exchange = io.read_shortstr
        routing_key = io.read_shortstr
        bits = io.read_short
        @mandatory = bits & (1 << 0)
        @immediate = bits & (1 << 1)
        Publish.new(reserved_1, exchange, routing_key, mandatory, immediate)
      end

      def encode(io)
        io.write_short(@reserved_1)
        io.write_shortstr(@exchange)
        io.write_shortstr(@routing_key)
        bits = 0_u8
        bits = bits | (1 << 0) if @mandatory
        bits = bits | (1 << 1) if @immediate
        io.write_short(bits)
      end
    end

    class Return < Method
      INDEX = 50
      CONTENT = true

      def initialize(@reply_code, @reply_text, @exchange, @routing_key)
      end

      def id
        [60, 50]
      end

      def wait?
        false
      end

      def self.decode(io)
        reply_code = io.read_short
        reply_text = io.read_shortstr
        exchange = io.read_shortstr
        routing_key = io.read_shortstr
        Return.new(reply_code, reply_text, exchange, routing_key)
      end

      def encode(io)
        io.write_short(@reply_code)
        io.write_shortstr(@reply_text)
        io.write_shortstr(@exchange)
        io.write_shortstr(@routing_key)
      end
    end

    class Deliver < Method
      INDEX = 60
      CONTENT = true

      def initialize(@consumer_tag, @delivery_tag, @redelivered, @exchange, @routing_key)
      end

      def id
        [60, 60]
      end

      def wait?
        false
      end

      def self.decode(io)
        consumer_tag = io.read_shortstr
        delivery_tag = io.read_longlong
        bits = io.read_short
        @redelivered = bits & (1 << 0)
        exchange = io.read_shortstr
        routing_key = io.read_shortstr
        Deliver.new(consumer_tag, delivery_tag, redelivered, exchange, routing_key)
      end

      def encode(io)
        io.write_shortstr(@consumer_tag)
        io.write_longlong(@delivery_tag)
        bits = 0_u8
        bits = bits | (1 << 0) if @redelivered
        io.write_short(bits)
        io.write_shortstr(@exchange)
        io.write_shortstr(@routing_key)
      end
    end

    class Get < Method
      INDEX = 70

      def initialize(@reserved_1, @queue, @no_ack)
      end

      def id
        [60, 70]
      end

      def wait?
        true
      end

      def self.decode(io)
        reserved_1 = io.read_short
        queue = io.read_shortstr
        bits = io.read_short
        @no_ack = bits & (1 << 0)
        Get.new(reserved_1, queue, no_ack)
      end

      def encode(io)
        io.write_short(@reserved_1)
        io.write_shortstr(@queue)
        bits = 0_u8
        bits = bits | (1 << 0) if @no_ack
        io.write_short(bits)
      end
    end

    class GetOk < Method
      INDEX = 71
      CONTENT = true

      def initialize(@delivery_tag, @redelivered, @exchange, @routing_key, @message_count)
      end

      def id
        [60, 71]
      end

      def wait?
        true
      end

      def self.decode(io)
        delivery_tag = io.read_longlong
        bits = io.read_short
        @redelivered = bits & (1 << 0)
        exchange = io.read_shortstr
        routing_key = io.read_shortstr
        message_count = io.read_long
        GetOk.new(delivery_tag, redelivered, exchange, routing_key, message_count)
      end

      def encode(io)
        io.write_longlong(@delivery_tag)
        bits = 0_u8
        bits = bits | (1 << 0) if @redelivered
        io.write_short(bits)
        io.write_shortstr(@exchange)
        io.write_shortstr(@routing_key)
        io.write_long(@message_count)
      end
    end

    class GetEmpty < Method
      INDEX = 72

      def initialize(@reserved_1)
      end

      def id
        [60, 72]
      end

      def wait?
        true
      end

      def self.decode(io)
        reserved_1 = io.read_shortstr
        GetEmpty.new(reserved_1)
      end

      def encode(io)
        io.write_shortstr(@reserved_1)
      end
    end

    class Ack < Method
      INDEX = 80

      def initialize(@delivery_tag, @multiple)
      end

      def id
        [60, 80]
      end

      def wait?
        false
      end

      def self.decode(io)
        delivery_tag = io.read_longlong
        bits = io.read_short
        @multiple = bits & (1 << 0)
        Ack.new(delivery_tag, multiple)
      end

      def encode(io)
        io.write_longlong(@delivery_tag)
        bits = 0_u8
        bits = bits | (1 << 0) if @multiple
        io.write_short(bits)
      end
    end

    class Reject < Method
      INDEX = 90

      def initialize(@delivery_tag, @requeue)
      end

      def id
        [60, 90]
      end

      def wait?
        false
      end

      def self.decode(io)
        delivery_tag = io.read_longlong
        bits = io.read_short
        @requeue = bits & (1 << 0)
        Reject.new(delivery_tag, requeue)
      end

      def encode(io)
        io.write_longlong(@delivery_tag)
        bits = 0_u8
        bits = bits | (1 << 0) if @requeue
        io.write_short(bits)
      end
    end

    class RecoverAsync < Method
      INDEX = 100

      def initialize(@requeue)
      end

      def id
        [60, 100]
      end

      def wait?
        false
      end

      def self.decode(io)
        bits = io.read_short
        @requeue = bits & (1 << 0)
        RecoverAsync.new(requeue)
      end

      def encode(io)
        bits = 0_u8
        bits = bits | (1 << 0) if @requeue
        io.write_short(bits)
      end
    end

    class Recover < Method
      INDEX = 110

      def initialize(@requeue)
      end

      def id
        [60, 110]
      end

      def wait?
        false
      end

      def self.decode(io)
        bits = io.read_short
        @requeue = bits & (1 << 0)
        Recover.new(requeue)
      end

      def encode(io)
        bits = 0_u8
        bits = bits | (1 << 0) if @requeue
        io.write_short(bits)
      end
    end

    class RecoverOk < Method
      INDEX = 111

      def initialize()
      end

      def id
        [60, 111]
      end

      def wait?
        true
      end

      def self.decode(io)
        RecoverOk.new()
      end

      def encode(io)
      end
    end

    class Nack < Method
      INDEX = 120

      def initialize(@delivery_tag, @multiple, @requeue)
      end

      def id
        [60, 120]
      end

      def wait?
        false
      end

      def self.decode(io)
        delivery_tag = io.read_longlong
        bits = io.read_short
        @multiple = bits & (1 << 0)
        @requeue = bits & (1 << 1)
        Nack.new(delivery_tag, multiple, requeue)
      end

      def encode(io)
        io.write_longlong(@delivery_tag)
        bits = 0_u8
        bits = bits | (1 << 0) if @multiple
        bits = bits | (1 << 1) if @requeue
        io.write_short(bits)
      end
    end

  end
  class Tx < Class
    INDEX = 90

    class Select < Method
      INDEX = 10

      def initialize()
      end

      def id
        [90, 10]
      end

      def wait?
        true
      end

      def self.decode(io)
        Select.new()
      end

      def encode(io)
      end
    end

    class SelectOk < Method
      INDEX = 11

      def initialize()
      end

      def id
        [90, 11]
      end

      def wait?
        true
      end

      def self.decode(io)
        SelectOk.new()
      end

      def encode(io)
      end
    end

    class Commit < Method
      INDEX = 20

      def initialize()
      end

      def id
        [90, 20]
      end

      def wait?
        true
      end

      def self.decode(io)
        Commit.new()
      end

      def encode(io)
      end
    end

    class CommitOk < Method
      INDEX = 21

      def initialize()
      end

      def id
        [90, 21]
      end

      def wait?
        true
      end

      def self.decode(io)
        CommitOk.new()
      end

      def encode(io)
      end
    end

    class Rollback < Method
      INDEX = 30

      def initialize()
      end

      def id
        [90, 30]
      end

      def wait?
        true
      end

      def self.decode(io)
        Rollback.new()
      end

      def encode(io)
      end
    end

    class RollbackOk < Method
      INDEX = 31

      def initialize()
      end

      def id
        [90, 31]
      end

      def wait?
        true
      end

      def self.decode(io)
        RollbackOk.new()
      end

      def encode(io)
      end
    end

  end
  class Confirm < Class
    INDEX = 85

    class Select < Method
      INDEX = 10

      def initialize(@nowait)
      end

      def id
        [85, 10]
      end

      def wait?
        true
      end

      def self.decode(io)
        bits = io.read_short
        @nowait = bits & (1 << 0)
        Select.new(nowait)
      end

      def encode(io)
        bits = 0_u8
        bits = bits | (1 << 0) if @nowait
        io.write_short(bits)
      end
    end

    class SelectOk < Method
      INDEX = 11

      def initialize()
      end

      def id
        [85, 11]
      end

      def wait?
        true
      end

      def self.decode(io)
        SelectOk.new()
      end

      def encode(io)
      end
    end

  end
end
