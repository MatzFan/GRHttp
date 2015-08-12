# GRHttp - A native Ruby Generic HTTP and WebSocket server.

GRHttp's Websocket capabilities are designed for ease of use and utilization, as well as a low learning curve.

Since websockets required you to learn about the Javascript's websockets API, GRHttp followed on with the same spirit, utilizing known callback such as: #on_open, #on_message and #on_close, as well as new callbacks such as #on_broadcast.

GRHttp can act both as a websocket **server** and as a websocket **client**.

## Websocket Server

Here's a "Hello World!" variation with a WebSocket Echo Server that both Boradcasts and Unicasts data to different websockets (semi-chatroom).

This should give a reasonable basic overview of GRHttp's Websocket Server API.

We'll create a module named 'MyHTTPServer' to handle regular HTTP requests and create another module called 'MyWSServer' for WebSocket related requests, including the upgrade request.

Remember that Handlers need to answer `call(request, response)` and that a `false` return value tells GRHttp thet the request was refused.

```ruby
require 'grhttp'

module MyHTTPServer
    module_function

    # handles HTTP
    def call request, response
      return false if request.path == '/refuse'
      response << "Hello #{'SSL ' if request.ssl?}World!\r\n\r\n"
      response << "To check the websocket server use: http://www.websocket.org/echo.html\r\n
      \r\Fill in the form on their webpage with the following address as your websocket server:\r\nhttp://localhost:3000/\r\n\r\n"
      response << "The Request:\r\n#{request.to_s}"
    end
end

module MyWSServer
    module_function

    # handles the HTTP upgrade request
    def call request, response
        return false if request.path == '/refuse'
        return self
    end

    # WebSocket callbacks

    def on_open ws
      puts 'WebSocket Open!'
      ws << 'System: Welcome!'
      ws.autopong # sets auto-pinging, to keep alive

      @first ||= ws.uuid # save the first connection's uuid.
      if ws.uuid == @first
        ws << "System: You're the first one here, so you get special notifications :-)"
      else
        ws.unicast @first, "JOINED: Someone just joined the chat."
      end
    end
    def on_message ws
      ws << "You: #{ws.data}"
      ws.broadcast "Someone: #{ws.data}"
    end

    def on_broadcast ws
      ws << ws.data
      true
    end

    def on_close ws
      ws.unicast @first, "LEFT: Someone just left the chat."
      puts 'WebSocket Closed!'
    end
end

# Now we will start the server.
#
# supplying the `start` method with a block means that
# the block will be executed and the `join` method will
# automaticly be called, so the thread will hang.
#
# Calling `start` without a block will start the server asynchronously
GRHttp.start do
    # listen to unencrypted traffic
    GRHttp.listen upgrade_handler: MyWSServer, http_handler: MyHTTPServer
    # listen to SSL trafic
    GRHttp.listen port: 3030, ssl: true, upgrade_handler: MyWSServer, http_handler: MyHTTPServer

    # add shutdown callbacks.
    GRHttp.on_shutdown { GRHttp.clear_listeners;  GRHttp.info 'Clear :-)'}
    GRHttp.on_shutdown { puts 'Shutdown and cleanup complete.'}

    puts "Press ^C to exit the server."
end
```

* [Test the `/refuse` path at http://localhost:3000/refuse](http://localhost:3000/refuse).
* [Test the wesocket echo server using http://websocket.org/echo.html](http://websocket.org/echo.html).

## Websocket Client

To Do: Write a Websocket demo and short explanation

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake false` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/boazsegev/grhttp.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

