# GRHttp - A native Ruby Generic HTTP and WebSocket server.
[![Gem Version](https://badge.fury.io/rb/grhttp.svg)](http://badge.fury.io/rb/grhttp)
[![Inline docs](http://inch-ci.org/github/boazsegev/GRHttp.svg?branch=master)](http://www.rubydoc.info/github/boazsegev/GRHttp/master)

This is a native Ruby HTTP and WebSocket multi-threaded server that uses the [GReactor](https://github.com/boazsegev/GReactor) library.

This means it's all ruby, no C or Java code. The code is thread-safe and also supports GReactor's forking... although it might effect your code (especially with regards to websocket broadcasting).

GRHttp is Rack compatible... although [GRHttp is meant to be a step forward](docs/HTTP.md), taking what we learned from our experience using Rack and designing the next generation of servers, as suggested by [José Valim](http://blog.plataformatec.com.br/2012/06/why-your-web-framework-should-not-adopt-rack-api/).

## How do I get it?

Add this line to your application's Gemfile:

```ruby
gem 'grhttp'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ [sudo] gem install grhttp


## To Rack or Not to Rack?

### We _can_...

It's true that we _can_ comfortably use GRHttp as a Rack server - just enter the folder for your favorit Rack compatible application (such as Rails or Sinatra) and write (remember to edit your `Gemfile` first):

    $ rackup -s grhttp -p 3000

For most frameworks (Rails/Sinatra), you can also add the `grhttp` gem to your gemfile and it will replace WEBrick as the default fallback server.

### We _should?_

So, we know we _can_, but _should_ we?

There is no simple answer. Using GRHttp through Rack is a bit slower by nature and uses an older (and heavier) server workflow design. on the other hand, if you have an existing application, what is the sense of re-writing all your code?

### We don't have to decide?!

The wonderful thing is, we really don't have to decide - we can mix and match GRHttp handlers with the Rack app (native handlers have priority).

Here is a quick example - place this `config.ru` file in a new folder and see for yourself:

```ruby
# config.ru
ENV['RACK_ENV'] = 'production'

require 'grhttp'

GRHttp.listen do |request, response|
  if request[:path] == '/grhttp'
    response << "Hello from GRHttp!"
    true
  else
    false
  end
end

rack_app = Proc.new do |env|
  [200, {"Content-Type" => "text/html", "Content-Length" => '16' }, ['Hello from Rack!'] ]
end

run rack_app
```

Run this code using `$ rackup -s grhttp -p 3000` (remember to be in the folder with the `config.ru` file)... Now test:

* GRHttp native server on: [http:localhost:3000/grhttp](http:localhost:3000/grhttp)
* GRHttp-Rack server on: [http:localhost:3000/rack](http:localhost:3000/rack)

This is How the [Plezi framework](https://github.com/boazsegev/plezi), which uses GRHttp's native server allows you to both run the Plezi framework's app and your Rails/Sinatra app at the same time - letting you use websockets and advanced features while still maintaining your existing codebase.

### How does it stack up against other servers?

The greatest sin is believing 'Hello World' apps are a good benchmark - they are NOT. For instance, replacing my Thin server on a production app with GRHttp had no meaningful and added Websockets to the mix... In the end of the day, the server is usually NOT the bottleneck.

But since "Hello World" apps the common way to isolate the server component, I tried doing some benchmarking and was fairly happy with the results.

But... Since every update might change the numbers, I removed the benchmarks from this README file. You can run the benchmarks on your own using the following code and see for yourself:

This was the Rackapp tested:

```ruby
# config.ru
ENV['RACK_ENV'] = 'production'
app = Proc.new do |env|
  [200, {"Content-Type" => "text/html", "Content-Length" => '16' }, ['Hello from Rack!'] ]
end
run app
```

The native GRHttp app tested was a terminal command:

      $ ruby -rgrhttp -e "GRHttp.start { GRHttp.listen {'Hello from GRHttp :-)'} }"

The hibrid-app tested was the code in the previous section.

Benchmarks were executed using `wrk` since not all servers answered `ab` (the issue is probably due to `close` vs. `keep-alive` connections over HTTP/1 while `wrk` uses HTTP/1.1):

     $ wrk -c400 -d10 -t12 http://localhost:3000/

\*In contrast to other Rack servers, GRHttp parses all of the HTTP request, offering you a read/write cookie-jar and parsing both POST data and query string data. The smart `request` and `response` is available to native apps.

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


## Websocket Client

GRHttp can also act as a client for either a semi-synchronous or asynchronous websocket connections.

GRHttp's websocket client was designed for simplicity, as it started it's life as a testing tool.

Here is a very simple implementation that leverages the fact that `GRHttp.ws_connect` will hang until a connection is established - making the code very simple to write:

```ruby
require 'grhttp'

client = GRHttp.ws_connect 'ws://echo.websocket.org' do |ws|
    puts "Received >> #{ws.data}"
    ws.close if ws.data =~ /^(bye|quit|exit|close)/i
end

client << "Echo this!"

client << "Bye" # => true

client.closed?

client << 'test' # => false

```

The block passed acted as our `on_message` callback. But what about an `on_close` callback, or an `on_connect` one... and what about some cookies?

Also, what if we don't want our code to block? Or maybe we want to connect to an SSL connection?

Okay, Okay... So many questions. No worries, here's a more complete example:


```ruby
require 'grhttp'

# Start GRHttp, if it isn't running in the background already.
# We're about to use asynchronous code.
number_of_threads = 30
GRHttp.start number_of_threads

# the following options will be used to setup the connection
options = {}

# The on_close callback
options[:on_close] = Proc.new {|ws| puts 'Connection closed.' }

# The on_open callback
options[:on_open] = Proc.new do |ws|
    # notify that the connection is open
    puts 'Connection opened.'
    # use the ws.ssl? method to make sure it's SSL
    puts 'This is an SSL connection' if ws.ssl?
    # write some stuff
    ws << 'Hello World!'
    10.times {|i|  ws << "Countdown: #{10-i}\n"}
    # say goodbye
    ws << 'Bye Bye'
end

# The on_message callback (instead of using a block like before)
options[:on_message] = Proc.new do |ws|
    # print out any incoming data
    puts "Received >> #{ws.data}"
    # close if we received a goodbye keyword
    ws.close if ws.data =~ /^(bye|quit|exit|close|goodbye)/i
end

# Cookies anyone?
options[:cookies] = {my_cookie_name: 'my cookie value'}

# Run the connection asynchronously
GRHttp.run_async { GRHttp.ws_connect 'wss://echo.websocket.org', options }

# Block, so we can see our code execute.
puts "Press ^C to stop the server"
GRHttp.join
```

Easy.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake false` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/boazsegev/grhttp.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

