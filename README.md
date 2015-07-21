# GRHttp - A native Ruby Generic HTTP and WebSocket server.
[![Inline docs](http://inch-ci.org/github/boazsegev/GRHttp.svg?branch=master)](http://www.rubydoc.info/gems/grhttp)

This is a native Ruby HTTP and WebSocket multi-threaded server that uses the [GReactor](https://github.com/boazsegev/GReactor) library.

This means it's all ruby, no C or Java code. The code is thread-safe and also supports GReactor's forking... although it might effect your code (especially with regards to websocket broadcasting).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'grhttp'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install grhttp

## Usage

GRHttp allows you to write a quick web service based of the [GReactor](https://github.com/boazsegev/GReactor) library - So you get Asynchronous events, timed event and a Server (or servers) - all in a native Ruby package.

You can use GRHttp for both HTTP and Websocket services and even write a full blown framework, such as the [Plezi HTTP and Websocket WebApp Framework](https://github.com/boazsegev/plezi) that uses GRHttp as it's server of choice.

### HTTP Server

Allow me to welcome the world famous 'Hello World'!

```ruby
require 'grhttp'
GRHttp.start {   GRHttp.listen { 'Hello World!' }      }
exit # exit between examples, to clear the listening services.
```

* [Test it at http://localhost:3000](http://localhost:3000).

As you may have noticed, by returning a string, the server automatically appended the string to the end of the response. This might be limited, so there's a better way to do this.

Also, we don't have to be hanging around while the server works... we can keep running tasks with the server in the background:

```ruby
require 'grhttp'

GRHttp.start

GRHttp.listen(timeout: 3, port: 3000) do |request, response|
   response.cookies[:name] = 'setting cookies is easy'
   response.flash[Time.now.to_s] = 'this cookie will selfdestruct on your next visit.'
   response << 'Hello!'
end

GRHttp.on_shutdown { GRHttp.clear_listeners; }

puts "We can keep working... try opening a page, go on... I'll wait..."
sleep 5

puts 'We can even restart the server:'
GRHttp.restart # restart doesn't invoke the shutdown callbacks.

puts 'Now we'll hang, press ^C to stop the service.'
GRHttp.join

```

* [Test it at http://localhost:3000](http://localhost:3000).
* [Test The SSL version at http://localhost:3030](http://localhost:3030).

Ammm... This example was too quick to explain much or show off all the bells and whistles, so, let's try again, this time - Bigger, better, and... websockets, anyone?

### Websocket services

WebSockets are also supported. Here's a "Hello World!" variation with a WebSocket Echo Server that both Boradcasts and Unicasts data to different websockets (semi-chatroom).

We'll be using the same handler to handle regular HTTP requests, upgrade requests and WebSocket requests, all at once. This might better simulate an HTTP Router situation, which routes all types of requests to their corrects controller (or controller class):

```ruby
module MyServer
    module_function

    # handles HTTP

    def call request, response
      if request.upgrade? # upgrade to websockets?
        return false if request.path == '/refuse'
        return self
      end
      return false if request.path == '/refuse'
      response << "Hello #{'SSL ' if request.ssl?}World!\r\n\r\n"
      response << "To check the websocket server use: http://www.websocket.org/echo.html\r\n\r\n"
      response << "The Request:\r\n#{request.to_s}"
    end

    # handles WebSockets

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

GRHttp.start do
    GRHttp.listen upgrade_handler: MyServer, http_handler: MyServer
    GRHttp.listen port: 3030, ssl: true, upgrade_handler: MyServer, http_handler: MyServer
    GRHttp.on_shutdown { GRHttp.clear_listeners;  GRHttp.info 'Clear :-)'}
    GRHttp.on_shutdown { puts 'Shutdown and cleanup complete.'}
end
```

* [Test the `/refuse` path at http://localhost:3000/refuse](http://localhost:3000/refuse).
* [Test the wesocket echo server using http://websocket.org/echo.html](http://websocket.org/echo.html).

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake false` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/boazsegev/grhttp.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

