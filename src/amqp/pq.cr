# A simple implementation of a priority queue.
#
module AMQP
  class PQ(T)
    def initialize
      @graph = [] of T
    end

    def empty?
      @graph.empty?
    end

    def length
      @graph.size
    end

    def <<(v)
      @graph.push v
      PQ.swim(@graph, @graph.size - 1)
    end

    def pop
      res =
        case @graph.size
        when 0
          yield
        when 1
          @graph.pop
        else
          @graph.swap(0, @graph.size - 1)
          @graph.pop
        end
      PQ.sink(@graph, 0, @graph.size)
      res
    end

    def pop
      pop { raise IndexOutOfBounds.new }
    end

    def pop?
      pop { nil }
    end

    protected def self.swim(graph, k)
      k += 1
      while k > 1 && graph[k/2-1] < graph[k-1]
        graph.swap(k/2-1, k-1)
        k = k/2
      end
    end

    protected def self.sink(graph, k, len)
      raise "invalid args" unless len <= graph.size
      k += 1
      while 2*k <= len
        j = 2*k
        if j < len && graph[j-1] < graph[j]
          j += 1
        end
        break if graph[k-1] > graph[j-1]
        graph.swap(k-1, j-1)
        k = j
      end
    end
  end
end
