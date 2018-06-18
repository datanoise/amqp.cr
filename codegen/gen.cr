require "xml"

macro iputs(val)
  io.puts "#{" " * indent * 2}#{{{val}}}"
end

macro do_indent(&block)
  indent += 1
  {{block.body}}
  indent -= 1
end

class String
  def classify
    self.gsub(/(^|-)(\w)/){|s, m| m[2].upcase as String}
  end

  def constantify
    self.upcase.tr("-", "_")
  end
end

module CodeGen
  class Domain
    getter :name
    getter :type

    @name : String
    @type : String

    def initialize(@node : XML::Node)
      @name = @node["name"].not_nil!
      @type = @node["type"].not_nil!
    end

    @@types = {} of String => Domain
    def self.[](name)
      @@types[name]
    end

    def self.add_domain(node)
      domain = Domain.new(node)
      @@types[domain.name] = domain
    end
  end

  class Constant

    @name : String
    @value : String?
    @class : String?

    def initialize(@node : XML::Node)
      @name = @node["name"].not_nil!
      @value = @node["value"]
      @class = @node["class"]?
    end

    def generate_constant(io, indent = 0)
      iputs "#{@name.constantify} = #{@value}"
    end

    def generate_exception(io, indent = 0)
      iputs "class #{@name.classify} < #{@class.not_nil!.classify}"
      do_indent do
        iputs "VALUE = #{@value}"
      end
      iputs "end"
      io.puts
    end

    def generate(io, indent = 0)
      if @class
        generate_exception(io, indent)
      else
        generate_constant(io, indent)
      end
    end
  end

  class Class
    getter name
    getter index
    getter methods

    @name : String
    @index : UInt32
    @methods :  Array(CodeGen::Method)

    def initialize(@node : XML::Node)
      @name = @node["name"].not_nil!.classify
      @index = @node["index"].not_nil!.to_u32
      mnodes = @node.xpath("method") as XML::NodeSet
      @methods = mnodes.map do |mnode|
        Method.new(self, mnode)
      end
    end

    def generate(io, indent = 0)
      iputs "module #{@name}"
      do_indent do
        iputs "INDEX = #{@index}_u16"
        io.puts
        @methods.each do |m|
          m.generate(io, indent)
          io.puts
        end
      end
      iputs "end"
    end
  end

  class Method
    getter index
    getter name

    @name : String
    @index : UInt32
    @has_content : Bool
    @sync : Bool
    @fields : Array(CodeGen::Field)

    def initialize(@cls : CodeGen::Class, @node : XML::Node)
      @name = @node["name"].not_nil!.classify
      @index = @node["index"].not_nil!.to_u32
      @has_content = @node["content"]? == "1"
      @sync = @node["synchronous"]? == "1"
      fnodes = @node.xpath("field") as XML::NodeSet
      @fields = fnodes.map do |fnode|
        Field.new(fnode)
      end
      if @has_content
        @fields.push ExtraField.new("properties", "table", "Table.new")
        @fields.push ExtraField.new("payload", "longstr", "\"\"")
      end
    end

    def generate(io, indent)
      iputs "class #{@name} < Method"
      do_indent do
        iputs "INDEX = #{@index}_u16"
        unless @fields.empty?
          io.puts
          iputs "getter #{@fields.map(&.name).join(", ")}"
        end

        io.puts
        iputs "def initialize(#{@fields.map{|f| "@" + f.name}.join(", ")})"
        iputs "end"
        io.puts

        # id method
        iputs "def id"
        do_indent do
          iputs "[#{@cls.index}_u16, #{@index}_u16]"
        end
        iputs "end"
        io.puts

        # wait? method
        iputs "def sync?"
        do_indent do
          iputs @sync ? "true" : "false"
        end
        iputs "end"
        io.puts

        iputs "def has_content?"
        do_indent do
          iputs @has_content ? "true" : "false"
        end
        iputs "end"
        io.puts

        if @has_content
          iputs "def content"
          do_indent do
            iputs "{@properties, @payload}"
          end
          iputs "end"
          io.puts
        end

        # decode method
        iputs "def self.decode(io)"
        do_indent do
          bit = -1
          @fields.each do |f|
            if bit == -1 && f.bit?
              iputs "bits = io.read_octet"
              iputs "raise ::IO::EOFError.new unless bits"
              bit = 0
            elsif bit > -1 && f.bit?
              bit += 1
            end
            f.generate_decode(io, indent, bit)
            if bit > -1 && !f.bit?
              bit = -1
            end
          end
          iputs "#{@name}.new(#{@fields.map{|f| f.name}.join(", ")})"
        end
        iputs "end"
        io.puts

        # encode method
        iputs "def encode(io)"
        do_indent do
          bit = -1
          @fields.each do |f|
            if bit > -1 && !f.bit?
              bit = -1
              iputs "io.write_octet(bits)"
            elsif bit > -1 && f.bit?
              bit += 1
            elsif bit == -1 && f.bit?
              bit = 0
              iputs "bits = 0_u8"
            end
            f.generate_encode(io, indent, bit)
          end
          if bit > -1
            iputs "io.write_octet(bits)"
          end
        end
        iputs "end"

        # to_s method
        io.puts
        iputs "def to_s(io)"
        do_indent do
          iputs "io << \"#{@cls.name}.#{@name}(\""
          @fields.each_with_index do |f, idx|
            iputs "io << \"#{f.name}: \""
            iputs "#{f.name}.inspect(io)"
            iputs "io << \", \"" if idx < @fields.length - 1
          end
          iputs "io << \")\""
        end
        iputs "end"
      end
      iputs "end"
    end

    def has_bits
      @fields.any?{|f| f.bit?}
    end
  end

  class Field
    getter :name

    @name : String
    @domain : CodeGen::Domain

    def initialize(node)
      @name = node["name"].not_nil!.tr("-", "_")
      @domain = Domain[node["domain"]? || node["type"]?]
    end

    def generate_decode(io, indent, bit)
      if bit?
        iputs "#{@name} = bits & (1 << #{bit}) == 1"
      else
        iputs "#{@name} = io.read_#{@domain.type}"
        iputs "raise ::IO::EOFError.new unless #{name}"
      end
    end

    def generate_encode(io, indent, bit)
      if bit?
        iputs "bits = bits | (1 << #{bit}) if @#{@name}"
      else
        iputs "io.write_#{@domain.type}(@#{@name})"
      end
    end

    def bit?
      @domain.type == "bit"
    end
  end

  class ExtraField < Field
    def initialize(@name : String, domain, @init : String)
      @domain = Domain[domain]
    end

    def generate_decode(io, indent, bit)
      iputs "#{@name} = #{@init}"
    end

    def generate_encode(io, indent, bit)
    end
  end

  def self.generate(doc, io)
    nodes = doc.xpath("//domain") as XML::NodeSet
    nodes.each do |dnode|
      Domain.add_domain(dnode)
    end

    nodes = doc.xpath("//class") as XML::NodeSet
    classes = nodes.map do |cls|
      CodeGen::Class.new(cls)
    end

    nodes = doc.xpath("//constant") as XML::NodeSet
    constants = nodes.map do |node|
      CodeGen::Constant.new(node)
    end

    indent = 0
    iputs "module AMQP::Protocol"
    do_indent do
      constants.each {|c| c.generate(io, indent); io.puts }
      classes.each {|c| c.generate(io, indent); io.puts }
      iputs "class Method"
      do_indent do
        iputs "def self.parse_method(cls_id, meth_id, io)"
        do_indent do
          iputs "case cls_id"
          classes.each do |c|
            iputs "when #{c.index}"
            do_indent do
              iputs "case meth_id"
              c.methods.each do |m|
                iputs "when #{m.index}"
                do_indent do
                  iputs "#{c.name}::#{m.name}.decode(io)"
                end
              end
              iputs "else"
              do_indent do
                iputs "raise FrameError.new(\"Invalid method index \#{cls_id}-\#{meth_id}\")"
              end
              iputs "end"
            end
          end
          iputs "else"
          do_indent do
            iputs "raise FrameError.new(\"Invalid class index \#{cls_id}\")"
          end
          iputs "end"
        end
        iputs "end"
      end
      iputs "end"
    end
    iputs "end"
  end
end

doc = XML.parse File.read("amqp0-9-1.extended.xml")
CodeGen.generate(doc, STDOUT)
