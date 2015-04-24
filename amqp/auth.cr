module AMQP
  class Auth
    getter mechanism

    def initialize(@mechanism)
    end

    abstract def response(username, password): String
  end

  class PlainAuth < Auth
    def initialize
      super("PLAIN")
    end

    def response(username, password)
      "\u{0}#{username}\u{0}#{password}"
    end
  end

  Authenticators = {"PLAIN" => PlainAuth.new}
end
