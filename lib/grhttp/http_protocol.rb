require 'stringio'
module GRHttp

	# This is a basic HTTP Protocol Class for the [GReactor](https://github.com/boazsegev/GReactor).
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
	class HTTProtocol < GReactor::Protocol
		include HTTP

		# Override this method to deal with HTTP requests.
		def on_request request, response
			response << request.to_s
			# length = request.to_s.bytesize
			# send "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: #{length}\r\nConnection: keep-alive\r\nKeep-Alive: 5\r\n\r\n#{request.to_s}"
			# t_now = Time.now
			# GR.log_raw "#{request[:client_ip]} [#{t_now.utc}] \"#{request[:method]} #{request[:original_path]} #{request[:requested_protocol]}\/#{request[:version].to_s}\" #{status} #{"%i" % ((t_now - request[:time_recieved])*1000)}ms\n" # %0.3f
			# puts "#{request[:client_ip]} [#{Time.now.utc}] \"#{request[:method]} #{request[:original_path]} #{request[:requested_protocol]}\/#{request[:version]}\" #{status} #{bytes_sent.to_s} #{"%i" % ((Time.now - request[:time_recieved])*1000)}ms\n" # %0.3f
			# request[:io].send "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\nConnection: keep-alive\r\nKeep-Alive: 5\r\n\r\nHello World\r\n"
		end

		# This method is called by the GReactor::Protocol superclass - DON'T override this method. This method is in charge of parsing the HTTP request.
		def on_message data
			data = StringIO.new data
			until data.eof?
				_complete_request if HTTP._parse_http io, data
			end
		end

		# Override this method to deal with WebSocket requests.
		def on_upgrade request
			false			
		end

		protected

		def _complete_request
			request = io[:request]
			io[:request] = nil

			# return ws_upgrade if request.upgrade?
			response = HTTPResponse.new request
			on_request request, response
			response.try_finish
		end

		# review a Websocket Upgrade
		def _ws_upgrade request
			new_handler = on_upgrade request
			return io.params[:handler] = new_handler if new_handler

			response = HTTPResponse.new request, 400
			response.finish
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
