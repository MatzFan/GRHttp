require 'stringio'
module GRHttp

	# This is a basic HTTP handler class for the [GReactor](https://github.com/boazsegev/GReactor).
	#
	# Use this class to create a basic HTTP server. 
	#
	# To use the HTTP class, inherit the class and override any of the following methods:
	# #on_connect:: called AFTER a connection is accepted but BEFORE ant requests are handled.
	# #on_request(request, response):: called whenever data is recieved from the IO.
	# #on_disconnect:: called AFTER the IO is closed.
	# #on_upgrade(request):: called BEFORE a WebSocket connection is established. Should return the WebSocket handler (replaces this HTTP Protocol object for the specific connection) or false (refuses the connection).
	#
	# Do NOT override the `#on_message data` method, as this class uses the #on_message method to parse incoming requests.
	#
	module Base
		module HTTPHandler
			extend HTTP

			module_function

			# This method is called by the reactor.
			# By default, this method reads the data from the IO and calls the `#on_message data` method.
			#
			# This method is called within a lock on the connection (Mutex) - craeful from double locking.
			def call io
				data = StringIO.new io.read.to_s
				until data.eof?
					if HTTP._parse_http io, data
							request = io[:request]; io[:request] = nil
							response = HTTPResponse.new request
							ret = ((request.upgrade? ? io.params[:ws_handler] : io.params[:http_handler]) || NO_HANDLER).call(request, response)
							if ret.is_a?(String)
								response << ret 
							elsif ret == false
								response.clear && (response.status = 404) && (response << HTTPResponse::STATUS_CODES[404])
							elsif ret && request.upgrade?
								# perform upgrade
								# create handler(?) and call on_connect
							end
							response.try_finish
					end
				end
			end

			protected
			NO_HANDLER = Proc.new { |i,o| false }

		end
	end
end


# GET /ctrl?test=true&r[family]=smith&r[name]=joe&a=1&a=2 HTTP/1.1
# Host: localhost:3000
# Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8
# Cookie: user_token=2INa32_vDgx8Aa1qe43oILELpSdIe9xwmT8GTWjkS-w
# User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10) AppleWebKit/600.1.25 (KHTML, like Gecko) Version/8.0 Safari/600.1.25
# Accept-Language: en-us
# Accept-Encoding: gzip, deflate
# Connection: keep-alive
# Content-Length: 13

# Hello World

# "GET /ctrl?test=true&r[family]=smith&r[name]=joe&a=1&a=2 HTTP/1.1\r\nHost: localhost:3000\r\nAccept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r\nCookie: user_token=2INa32_vDgx8Aa1qe43oILELpSdIe9xwmT8GTWjkS-w\r\nUser-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10) AppleWebKit/600.1.25 (KHTML, like Gecko) Version/8.0 Safari/600.1.25\r\nAccept-Language: en-us\r\nAccept-Encoding: gzip, deflate\r\nConnection: keep-alive\r\nContent-Length: 13\r\n\r\nHello World\r\n\r\n"
# puts Benchmark.measure {100_000.times { i = -1 ; copy = source.dup; h = {}; copy.lines.each {|l| h[i += 1] = l }  } }

# puts Benchmark.measure {100_000.times { i = -1 ; copy = source.dup; h = {}; h[i += 1] = copy.slice!( /[^\r\n]*[\r]?\n/ ) until copy.empty?   } }
