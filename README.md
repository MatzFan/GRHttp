# GRHttp - A native Ruby generic HTTP and WebSocket server.

Wait for it... - For now I just have the HTTP part finished... almost (the API design might change).

This is a native Ruby HTTP and WebSocket multi-threaded server that uses the [GReactor](https://github.com/boazsegev/GReactor) library.

This means it's all ruby, no C or Java code.

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

You can use GRHttp for both HTTP and Websocket services.

### HTTP Server

Allow me to welcome the world famous 'Hello World'!

```ruby
require 'grhttp'
GRHttp.start {   GRHttp.listen {|request, response| 'Hello World!' }      }
exit # exit between examples, to clear the listening services.
```

* [Test it at http://localhost:3000](http://localhost:3000).

There's no reason to be hanging around while the server works...

```ruby
require 'grhttp'
GRHttp.start
GRHttp.listen(timeout: 3, port: 3000) {|request, response| 'Hello!' }
GRHttp.on_shutdown { GRHttp.clear_listeners;  GRHttp.info 'Clear :-)'}
puts 'We can keep working...'
puts 'We can even restart the server:'
GRHttp.restart # restart doesn't invoke the shutdown callbacks.
puts 'Press ^C to stop the service.'
GRHttp.join

```

Ammm... This example was too quick to explain anything or show off all the bells and whistles, so, let's try again, this time - Bigger:

```ruby
require 'grhttp'

  # GRHttp doesn't have a .start method, so it deffers to the GReactor library.
  # This means we are actually calling GReactor.start which can accept a block and hang until it's done.
GRHttp.start do
     # GRHttp.listen creates a webservice and accepts an optional block that acts as the HTTP handler.
   GRHttp.listen(timeout: 3, port: 3000) do |request, response|
        # if we return a string, the server automatically
        # appends the string to the end of the response
      'Hello World!'
   end

     # We can also add an SSL version of the Hello World...

     # This time we'll create a hendler - an object that responds to #call(request, response)
   http_handler = Proc.new do |request, response|
      response.cookies[:ssl_visited] = "Yap."
      response << 'Hello SSL World!'
   end

   GRHttp.listen port: 3030, ssl: true, http_handler: http_handler

     # Clear the GReactor's listener stack between examples
   GRHttp.on_shutdown { GRHttp.clear_listeners;  GRHttp.info 'Clear :-)'}

end

```

* [Test it at http://localhost:3000](http://localhost:3000).
* [Test The SSL version at http://localhost:3030](http://localhost:3030).

We can also make this object oriented:

```ruby
require 'grhttp'

module MyHandler
   def self.call request, response
      if request.protocol == 'https'
         response.cookies[:ssl_visited] = true
           # there's even a temporary cookie stash (single use cookies)\*
         response.flash[:on_and_off] = true unless response.flash[:on_and_off]
         response << 'Hello SSL world!'
      else
         response << 'Hello Clear Text world!'
      end
      return false if request.path == '/refuse'
      true
   end
end

GRHttp.start do

   GRHttp.listen port: 3000, http_handler: MyHandler
   GRHttp.listen port: 3030, http_handler: MyHandler, ssl: true

     # Clear the GReactor's listener stack between examples
   GRHttp.on_shutdown { GRHttp.clear_listeners;  GRHttp.info 'Clear :-)'}

end

# \* Google's Chrome might mess your flash cookie jar
#    by requesting the `favicon.ico` while sending and setting cookies...
#    It works as expected, but Chrome's refresh might be over-extensive.

```

* [Test the `/refuse` path at http://localhost:3000/refuse](http://localhost:3000/refuse).


### Websocket services

Wait for it...

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake false` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/boazsegev/grhttp.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

