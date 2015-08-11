# GRHttp - A native Ruby Generic HTTP and WebSocket server.

GRHttp's HTTP capabilities are designed for ease of use and utilization, although some knowledge about HTTP is expected.

Here we will explore some of the core differences between GRHttp's workflow design and Rack based workflow design. This should demonstrate why it's time to learn from Rack's experience and say to Rack 'goodbye'.

## GRHttp Vs. Rack - HTTP workflow

In a very general sense, the HTTP protocol a request=>response based protocol, where the client (browser) makes requests and the server responds to those requests.

In the most common world of Rack servers, the server will send your code a request and the response will be parse according to the returned value.

But a lot of experience and time had accumilated since the Rack specifications were first designed and in today's world we want to be able to start sending the HTTP response even before our server had completed.

Until now, [many workarounds were tried](http://blog.plataformatec.com.br/2012/06/why-your-web-framework-should-not-adopt-rack-api/) in an attempt to transcend the limitations imposed by Rack's specifications.

This is where GRHttp's workflow comes in.

GRHttp sends you both the request and the response, so that you can start sending data while still processing your request.

### Old world workflow

Here is a regular 'Hello world' example with Rack:

```ruby
# file: "config.ru" ; test with Puma: $ puma -p 3000
run Proc.new {|env| return [200, {"Content-Type" => "text/html", "Content_Length: 12"}, ["Hello World!"]] }
```

GRHttp can emulate the same oldworld workflow. When the returned value is a String, GRHttp will append the String to the response before completing the response.

Here is the same simple example with GRHttp:

```ruby
# run from irb
require 'grhttp'
GRHttp.start { GRHttp.listen { "Hello World!"} }
exit
```
### New world workflow

Here is a simple blocking 'new world' exaple. Because GRHttp has a thread pool, it's OKAY (and sometimes safer) to block one thread for a slow response IF most responses are non-blocking.

```ruby
# run from irb
require 'grhttp'
GRHttp.start do
  GRHttp.listen do |request, response|
    "Hello World!".chars.each do |c|
      response.send c
      sleep 1
    end
  end
end
exit
```


Rack can perform blocking While Rack's new world workflow would require a lengthly example for each possible behavior (not to mention, Websockets which require different code for different Rack servers), GRHttp makes it simple.


Using `response.send data` forces the response to send the data immediately, unlike `response << data` which sends the data immediately only if data was already sent using `response.send`.

Our thread was blocking, but data was constantly streamed.

Next, we will use recursion for a 'non-blocking' streaming example:

```ruby
# run from irb
require 'grhttp'
GRHttp.start do
  GRHttp.listen do |request, response|
    data = "Hello World!".chars
    send_proc = Proc.new do
      response.send data.shift
      sleep 1
      response.stream_async &send_proc unless data.empty?
    end
    response.stream_async &send_proc
  end
end
exit
```

This time, our thread will break down the 12 seconds task into blocks of one second each. In this sense, our task will be "non-blocking" - we will not wait for completion before allowing our thread to execute intermediate tasks.

Review this using telnet to see the actual streaming (The browser will block for text streaming):

    $ telnet localhost 3000

    > GET / HTTP/1.1
    > Host: localhost:3000
    >       (empty line)

How can we implement non-blocking HTTP streaming in Rack? Well, the simple answer is - we can't...

...If we can, I simply have no idea how. As far as I know, Rach will call `#each` on the body it recieves. Once `#each` completes, the response will be done. Unless the IO is hijacked and we leave Rack behind, we cannot stream data asynchronously and we will experience a long blocking task.


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/boazsegev/grhttp.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

