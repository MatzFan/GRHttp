require 'grhttp'

::Rack::Handler.register( 'grhttp', 'GRHttp::Base::Rack') if defined?(::Rack)
