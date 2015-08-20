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
		# @return [true, Exception] The method returns immidiatly with a value of true unless it is impossible to stream the response (an exception will be raised) or a block wasn't supplied.
		def stream_async &block
			raise "Block required." unless block
			start_streaming unless @finished
			@io[:http_sblocks_count] += 1
			@stream_proc ||= Proc.new { |block| raise "IO closed. Streaming failed." if io.io.closed?; block.call; io[:http_sblocks_count] -= 1; finish_streaming }
			GReactor.queue @stream_proc, [block]
		end

		# Creates and returns the session storage object.
		#
		# By default and for security reasons, session id's created on a secure connection will NOT be available on a non secure connection (SSL/TLS).
		#
		# Since this method renews the session_id's cookie's validity (update's it's times-stump), it must be called for the first time BEFORE the headers are sent.
		#
		# After the session object was created using this method call, it should be safe to continue updating the session data even after the headers were sent and this method would act as an accessor for the already existing session object.
		#
		# @return [Hash like storage] creates and returns the session storage object with all the data from a previous connection.
		def session
			return @session if @session
			id = request.cookies[GRHttp.session_token.to_sym] || SecureRandom.uuid
			set_cookie GRHttp.session_token, id, expires: (Time.now+86_400), secure:  @request.ssl?
			@session = GRHttp::SessionManager.get id
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
			# write if streaming?
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
			return (@headers.delete(header) && nil) if header.nil?
			header.is_a?(String) ? (header.frozen? ? header : header.downcase!) : (header.is_a?(Symbol) ? (header = header.to_s.downcase.to_sym) : (return false))
			headers[header]	= value
		end


		COOKIE_NAME_REGEXP = /[\x00-\x20\(\)<>@,;:\\\"\/\[\]\?\=\{\}\s]/

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
			name = name.to_s
			raise 'Illegal cookie name' if name.match(COOKIE_NAME_REGEXP)
			params[:expires] = (Time.now - 315360000) unless value
			value ||= 'deleted'.freeze
			params[:expires] ||= (Time.now + 315360000) unless params[:max_age]
			params[:path] ||= '/'.freeze
			value = HTTP.encode_url(value)
			if params[:max_age]
				value << ('; Max-Age=%s' % params[:max_age])
			else
				value << ('; Expires=%s' % params[:expires].httpdate)
			end
			value << "; Path=#{params[:path]}"
			value << "; Domain=#{params[:domain]}" if params[:domain]
			value << '; Secure'.freeze if params[:secure]
			value << '; HttpOnly'.freeze if params[:http_only]
			@cookies[name.to_sym] = value
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
		# the response will remain open for more data to be sent through (using `response << data` and `response.write`).
		def write(str = nil)
			raise 'HTTPResponse IO MISSING: cannot send http response without an io.' unless @io
			@body << str if @body && str
			return if send_headers
			return if request.head?
			send_body(str)
			self
		end
		alias :send :write

		# Sends the response and flags the response as complete. Future data should not be sent. Your code might attempt sending data (which would probbaly be ignored by the client or raise an exception).
		def finish
			raise "Response already sent" if @finished
			@headers['content-length'.freeze] ||= (@body = @body.join).bytesize if !headers_sent? && @body.is_a?(Array)
			self.write
			@io.write "0\r\n\r\n" if @chunked
			@finished = true
			@io.close unless @io[:keep_alive]
			finished_log
		end

		# Danger Zone (internally used method, use with care): attempts to finish the response - if it was not flaged as streaming or completed.
		def try_finish
			finish unless @finished
		end
		
		# response status codes, as defined.
		STATUS_CODES = {100=>"Continue".freeze,
			101=>"Switching Protocols".freeze,
			102=>"Processing".freeze,
			200=>"OK".freeze,
			201=>"Created".freeze,
			202=>"Accepted".freeze,
			203=>"Non-Authoritative Information".freeze,
			204=>"No Content".freeze,
			205=>"Reset Content".freeze,
			206=>"Partial Content".freeze,
			207=>"Multi-Status".freeze,
			208=>"Already Reported".freeze,
			226=>"IM Used".freeze,
			300=>"Multiple Choices".freeze,
			301=>"Moved Permanently".freeze,
			302=>"Found".freeze,
			303=>"See Other".freeze,
			304=>"Not Modified".freeze,
			305=>"Use Proxy".freeze,
			306=>"(Unused)".freeze,
			307=>"Temporary Redirect".freeze,
			308=>"Permanent Redirect".freeze,
			400=>"Bad Request".freeze,
			401=>"Unauthorized".freeze,
			402=>"Payment Required".freeze,
			403=>"Forbidden".freeze,
			404=>"Not Found".freeze,
			405=>"Method Not Allowed".freeze,
			406=>"Not Acceptable".freeze,
			407=>"Proxy Authentication Required".freeze,
			408=>"Request Timeout".freeze,
			409=>"Conflict".freeze,
			410=>"Gone".freeze,
			411=>"Length Required".freeze,
			412=>"Precondition Failed".freeze,
			413=>"Payload Too Large".freeze,
			414=>"URI Too Long".freeze,
			415=>"Unsupported Media Type".freeze,
			416=>"Range Not Satisfiable".freeze,
			417=>"Expectation Failed".freeze,
			422=>"Unprocessable Entity".freeze,
			423=>"Locked".freeze,
			424=>"Failed Dependency".freeze,
			426=>"Upgrade Required".freeze,
			428=>"Precondition Required".freeze,
			429=>"Too Many Requests".freeze,
			431=>"Request Header Fields Too Large".freeze,
			500=>"Internal Server Error".freeze,
			501=>"Not Implemented".freeze,
			502=>"Bad Gateway".freeze,
			503=>"Service Unavailable".freeze,
			504=>"Gateway Timeout".freeze,
			505=>"HTTP Version Not Supported".freeze,
			506=>"Variant Also Negotiates".freeze,
			507=>"Insufficient Storage".freeze,
			508=>"Loop Detected".freeze,
			510=>"Not Extended".freeze,
			511=>"Network Authentication Required".freeze
		}

		protected

		def finished_log
			return if @quite
			t_n = Time.now
			GReactor.log_raw("#{@request[:client_ip]} [#{t_n.utc}] \"#{@request[:method]} #{@request[:original_path]} #{@request[:requested_protocol]}\/#{@request[:version]}\" #{@status} #{bytes_sent.to_s} #{((t_n - @request[:time_recieved])*1000).round(2)}ms\n").clear # %0.3f
		end

		# Danger Zone (internally used method, use with care): fix response's headers before sending them (date, connection and transfer-coding).
		def fix_cookie_headers
			# remove old flash cookies
			request.cookies.keys.each do |k|
				if k.to_s.start_with? 'magic_flash_'.freeze
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
			out = ''

			out << "#{@http_version} #{@status} #{STATUS_CODES[@status] || 'unknown'}\r\nDate: #{Time.now.httpdate}\r\n"

			# unless @headers['connection'] || (@request[:version].to_f <= 1 && (@request['connection'].nil? || !@request['connection'].match(/^k/i))) || (@request['connection'] && @request['connection'].match(/^c/i))
			if (@request[:version].to_f > 1 && @request['connection'.freeze].nil?) || @request['connection'.freeze].to_s =~ /^k/i || (@headers['connection'.freeze] && @headers['connection'.freeze] =~ /^k/i) # simpler
				@io[:keep_alive] = true
				out << "Connection: Keep-Alive\r\nKeep-Alive: timeout=5\r\n".freeze
			else
				@headers['connection'.freeze] ||= 'close'.freeze
			end

			if @headers['content-length'.freeze]
				@chunked = false
			else
				@chunked = true
				out << "Transfer-Encoding: chunked\r\n".freeze
			end
			@headers.each {|k,v| out << "#{k.to_s}: #{v}\r\n"}
			out << "Cache-Control: max-age=0, no-cache\r\n".freeze unless @headers['cache-control'.freeze]
			@cookies.each {|k,v| out << "Set-Cookie: #{k.to_s}=#{v.to_s}\r\n"}
			out << "\r\n"

			@io.write out
			out.clear
			@headers.freeze
			if @body && @body.is_a?(Array)
				@body = @body.join 
			end
			send_body(@body) && (@body.frozen? ? true : @body.clear) if @body && !@body.empty? && !request.head?
			@body = nil
			true
		end

		# sends the body or part thereof
		def send_body data
			return nil unless data
			if @chunked
				@io.write "#{data.bytesize.to_s(16)}\r\n#{data}\r\n"
				@bytes_sent += data.bytesize
			else
				@io.write data
				@bytes_sent += data.bytesize
			end

		end

		# Sets the http streaming flag and sends the responses headers, so that the response could be handled asynchronously.
		#
		# if this flag is not set, the response will try to automatically finish its job
		# (send its data and maybe close the connection).
		#
		# NOTICE! :: If HTTP streaming is set, you will need to manually call `response.finish_streaming`
		# or the connection will not close properly and the client will be left expecting more information.
		def start_streaming
			raise "Cannot start streaming after headers were sent!" if headers_sent?
			@finished = @chunked = true
			headers['connection'.freeze] = 'Close'.freeze
			@io[:http_sblocks_count] ||= 0
			write nil
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