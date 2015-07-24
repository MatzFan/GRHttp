module GRHttp

	# this class handles HTTP response.
	#
	# The response can be sent in stages but should complete within the scope of the connecton's message. Please notice that headers and status cannot be changed once the response started sending data.
	class HTTPResponse

		#the response's status code
		attr_accessor :status
		#the response's headers
		attr_reader :headers
		#the flash cookie-jar (single-use cookies, that survive only one request).
		attr_reader :flash
		#the response's body buffer container (an array). This object is removed once the headers are sent and all write operations hang after that point.
		attr_reader :body
		#bytes sent to the asynchronous que so far - excluding headers (only the body object).
		attr_reader :bytes_sent
		#the io through which the response will be sent.
		attr_reader :io
		#the request.
		attr_accessor :request

		# the response object responds to a specific request on a specific io.
		# hence, to initialize a response object, a request must be set.
		#
		# use, at the very least `HTTPResponse.new request`
		def initialize request, status = 200, headers = {}, content = nil
			@request = request
			@status = status
			@headers = headers
			@body = content || []
			@io = request[:io]
			@request.cookies.set_response self
			@http_version = 'HTTP/1.1' # request.version
			@bytes_sent = 0
			@finished = @streaming = false
			@cookies = {}
			@quite = false
			@chunked = false
			# propegate flash object
			@flash = Hash.new do |hs,k|
				hs["magic_flash_#{k.to_s}".to_sym] if hs.has_key? "magic_flash_#{k.to_s}".to_sym
			end
			request.cookies.each do |k,v|
				@flash[k] = v if k.to_s.start_with? 'magic_flash_'
			end
		end

		# returns true if headers were already sent
		def headers_sent?
			@headers.frozen?
		end

		# returns true if the response is already finished (the client isn't expecting any more data).
		def finished?
			@finished
		end

		# Forces the `finished` response's flag to true - use this to avoide sending a response or before manualy
		# responding using the IO object.
		def cancel!
			@finished = true
		end

		# Creates a streaming block. Once all streaming blocks are done, the response will automatically finish.
		#
		# This avoids manualy handling {#start_streaming}, {#finish_streaming} and asynchronously tasking.
		#
		# Every time data is sent the timout is reset. Responses longer than timeout will not be sent (but they will be processed). 
		#
		# Accepts a required block. i.e.
		#
		#     response.stream_async {sleep 1; response << "Hello Streaming"}
		#     # OR, you can chain the streaming calls
		#     response.stream_async do
		#       sleep 1
		#       response << "Hello Streaming"
		#       response.stream_async do
		#           sleep 1
		#           response << "Goodbye Streaming"
		#       end
		#     end
		#
		# @returns [true, exception] The method returns immidiatly with a value of true unless it is impossible to stream the response (an exception will be raised) or a block wasn't supplied.
		def stream_async &block
			raise "Block required." unless block
			start_streaming unless @finished
			@io[:http_sblocks_count] += 1
			@stream_proc ||= Proc.new { |block| raise "IO closed. Streaming failed." if io.io.closed?; block.call; io[:http_sblocks_count] -= 1; finish_streaming }
			GReactor.queue [block], @stream_proc
		end

		# Returns a writable combined hash of the request's cookies and the response cookie values.
		#
		# Any cookies writen to this hash (`response.cookies[:name] = value` will be set using default values).
		#
		# It's also possible to use this combined hash to delete cookies, using: response.cookies[:name] = nil
		def cookies
			@request.cookies
		end

		# supresses logging on success.
		def quite!
			@quite = true
		end

		# pushes data to the buffer of the response. this is the preferred way to add data to the response.
		#
		# If the headers were already sent, this will also send the data and hang until the data was sent.
		def << str
			@body ? @body.push(str) : (request.head? ? false :  send_body(str))
			self
			# send if streaming?
		end

		# returns a response header, if set.
		def [] header
			headers[header] # || @cookies[header]
		end

		# sets a response header. response headers should be a down-case String or Symbol.
		#
		# this is the prefered to set a header.
		#
		# returns the value set for the header.
		#
		# see HTTP response headers for valid headers and values: http://en.wikipedia.org/wiki/List_of_HTTP_header_fields
		def []= header, value
			raise 'Cannot set headers after the headers had been sent.' if headers_sent?
			header.is_a?(String) ? header.downcase! : (header.is_a?(Symbol) ? (header = header.to_s.downcase.to_sym) : (return false))
			headers[header]	= value
		end

		# Sets/deletes cookies when headers are sent.
		#
		# Accepts:
		# name:: the cookie's name
		# value:: the cookie's value
		# parameters:: a parameters Hash for cookie creation.
		#
		# Parameters accept any of the following Hash keys and values:
		#
		# expires:: a Time object with the expiration date. defaults to 10 years in the future.
		# max_age:: a Max-Age HTTP cookie string.
		# path:: the path from which the cookie is acessible. defaults to '/'.
		# domain:: the domain for the cookie (best used to manage subdomains). defaults to the active domain (sub-domain limitations might apply).
		# secure:: if set to `true`, the cookie will only be available over secure connections. defaults to false.
		# http_only:: if true, the HttpOnly flag will be set (not accessible to javascript). defaults to false.
		#
		# Setting the request's coockies (`request.cookies[:name] = value`) will automatically call this method with default parameters.
		#
		def set_cookie name, value, params = {}
			raise 'Cannot set cookies after the headers had been sent.' if headers_sent?
			params[:expires] = (Time.now - 315360000) unless value
			value ||= 'deleted'
			params[:expires] ||= (Time.now + 315360000) unless params[:max_age]
			params[:path] ||= '/'
			value = HTTP.encode(value.to_s)
			if params[:max_age]
				value << ('; Max-Age=%s' % params[:max_age])
			else
				value << ('; Expires=%s' % params[:expires].httpdate)
			end
			value << "; Path=#{params[:path]}"
			value << "; Domain=#{params[:domain]}" if params[:domain]
			value << '; Secure' if params[:secure]
			value << '; HttpOnly' if params[:http_only]
			@cookies[HTTP.encode(name.to_s).to_sym] = value
		end

		# deletes a cookie (actually calls `set_cookie name, nil`)
		def delete_cookie name
			set_cookie name, nil
		end

		# clears the response object, unless headers were already sent.
		#
		# returns false if the response was already sent.
		def clear
			return false if headers.frozen? || @finished
			@status, @body, @headers, @cookies = 200, [], {}, {}
			self
		end

		# sends the response object. headers will be frozen (they can only be sent at the head of the response).
		#
		# the response will remain open for more data to be sent through (using `response << data` and `response.send`).
		def send(str = nil)
			raise 'HTTPResponse IO MISSING: cannot send http response without an io.' unless @io
			@body << str if @body && str
			return if send_headers
			return if request.head?
			send_body(str)
			self
		end

		# Sends the response and flags the response as complete. Future data should not be sent. Your code might attempt sending data (which would probbaly be ignored by the client or raise an exception).
		def finish
			raise "Response already sent" if @finished
			@headers['content-length'] ||= (@body = @body.join).bytesize if !headers_sent? && @body.is_a?(Array)
			self.send
			@io.send "0\r\n\r\n" if @chunked
			@finished = true
			# io.close unless io[:keep_alive]
			finished_log
		end

		# Danger Zone (internally used method, use with care): attempts to finish the response - if it was not flaged as streaming or completed.
		def try_finish
			finish unless @finished
		end
		
		# response status codes, as defined.
		STATUS_CODES = {100=>"Continue",
			101=>"Switching Protocols",
			102=>"Processing",
			200=>"OK",
			201=>"Created",
			202=>"Accepted",
			203=>"Non-Authoritative Information",
			204=>"No Content",
			205=>"Reset Content",
			206=>"Partial Content",
			207=>"Multi-Status",
			208=>"Already Reported",
			226=>"IM Used",
			300=>"Multiple Choices",
			301=>"Moved Permanently",
			302=>"Found",
			303=>"See Other",
			304=>"Not Modified",
			305=>"Use Proxy",
			306=>"(Unused)",
			307=>"Temporary Redirect",
			308=>"Permanent Redirect",
			400=>"Bad Request",
			401=>"Unauthorized",
			402=>"Payment Required",
			403=>"Forbidden",
			404=>"Not Found",
			405=>"Method Not Allowed",
			406=>"Not Acceptable",
			407=>"Proxy Authentication Required",
			408=>"Request Timeout",
			409=>"Conflict",
			410=>"Gone",
			411=>"Length Required",
			412=>"Precondition Failed",
			413=>"Payload Too Large",
			414=>"URI Too Long",
			415=>"Unsupported Media Type",
			416=>"Range Not Satisfiable",
			417=>"Expectation Failed",
			422=>"Unprocessable Entity",
			423=>"Locked",
			424=>"Failed Dependency",
			426=>"Upgrade Required",
			428=>"Precondition Required",
			429=>"Too Many Requests",
			431=>"Request Header Fields Too Large",
			500=>"Internal Server Error",
			501=>"Not Implemented",
			502=>"Bad Gateway",
			503=>"Service Unavailable",
			504=>"Gateway Timeout",
			505=>"HTTP Version Not Supported",
			506=>"Variant Also Negotiates",
			507=>"Insufficient Storage",
			508=>"Loop Detected",
			510=>"Not Extended",
			511=>"Network Authentication Required"
		}

		protected

		def finished_log
			GReactor.log_raw("#{@request[:client_ip]} [#{Time.now.utc}] \"#{@request[:method]} #{@request[:original_path]} #{@request[:requested_protocol]}\/#{@request[:version]}\" #{@status} #{bytes_sent.to_s} #{"%i" % ((Time.now - @request[:time_recieved])*1000)}ms\n").clear unless @quite# %0.3f
		end

		# Danger Zone (internally used method, use with care): fix response's headers before sending them (date, connection and transfer-coding).
		def fix_cookie_headers
			# remove old flash cookies
			request.cookies.keys.each do |k|
				if k.to_s.start_with? 'magic_flash_'
					set_cookie k, nil
					flash.delete k
				end
			end
			#set new flash cookies
			@flash.each do |k,v|
				set_cookie "magic_flash_#{k.to_s}", v
			end
			@flash.freeze
		end
		# Danger Zone (internally used method, use with care): fix response's headers before sending them (date, connection and transfer-coding).
		def send_headers
			return false if @headers.frozen?
			fix_cookie_headers
			headers['cache-control'] ||= 'no-cache'
			out = ''

			out << "#{@http_version} #{@status} #{STATUS_CODES[@status] || 'unknown'}\r\nDate: #{Time.now.httpdate}\r\n"

			unless headers['connection']
				io[:keep_alive] = true
				out << "Connection: Keep-Alive\r\nKeep-Alive: timeout=5\r\n"
			end

			if headers['content-length']
				@chunked = false
			else
				@chunked = true
				out << "Transfer-Encoding: chunked\r\n"
			end
			headers.each {|k,v| out << "#{k.to_s}: #{v}\r\n"}
			@cookies.each {|k,v| out << "Set-Cookie: #{k.to_s}=#{v.to_s}\r\n"}
			out << "\r\n"

			io.send out
			out.clear
			@headers.freeze
			if @body && @body.is_a?(Array)
				@body = @body.join 
				send_body @body unless @body.empty? || request.head?
				@body.clear if @body
			else
				send_body @body if @body && !request.head?
			end
			@body = nil
		end

		# sends the body or part thereof
		def send_body data
			return nil unless data
			if @chunked
				@io.send "#{data.bytesize.to_s(16)}\r\n#{data}\r\n"
				@bytes_sent += data.bytesize
			else
				io.send data
				@bytes_sent += data.bytesize
			end

		end

		# Sets the http streaming flag and sends the responses headers, so that the response could be handled asynchronously.
		#
		# if this flag is not set, the response will try to automatically finish its job
		# (send its data and maybe close the connection).
		#
		# NOTICE! :: If HTTP streaming is set, you will need to manually call `response.finish_streaming`
		# or the connection will not close properly.
		def start_streaming
			raise "Cannot start streaming after headers were sent!" if headers_sent?
			@finished = @chunked = true
			headers['connection'] = 'Close'
			@io[:http_sblocks_count] ||= 0
			send nil
		end

		# Sends the complete response signal for a streaming response.
		#
		# Careful - sending the completed response signal more than once might case disruption to the HTTP connection.
		def finish_streaming
			return unless @io[:http_sblocks_count] == 0
			@finished = false
			finish
			@io.close
		end
	end

end

######
## example requests

# GET /stream HTTP/1.1
# Host: localhost:3000
# Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8
# Cookie: user_token=2INa32_vDgx8Aa1qe43oILELpSdIe9xwmT8GTWjkS-w
# User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10) AppleWebKit/600.1.25 (KHTML, like Gecko) Version/8.0 Safari/600.1.25
# Accept-Language: en-us
# Accept-Encoding: gzip, deflate
# Connection: keep-alive