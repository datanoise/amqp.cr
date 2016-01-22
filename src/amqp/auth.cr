module AMQP
  abstract class Auth
    getter mechanism

    def initialize(@mechanism)
    end

    abstract def response(username, password): String

    def self.get_authenticator(mechanisms)
      unless mechanisms
        raise Protocol::FrameError.new("List of auth mechanisms is empty")
      end
      mechanisms = mechanisms.split(' ')
      auth = nil
      mechanisms.each do |mech|
        auth = Authenticators[mech]?
        break if auth
      end
      unless auth
        raise Protocol::NotImplemented.new("Unable to use any of these auth methods #{mechanisms}")
      end
      auth
    end
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
