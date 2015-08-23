#!/usr/bin/env ruby

module HTTP
	# This module contains helper methods and classes that AREN'T part of the public API, but are used internally.
	module Base
		# Sets magic cookies - NOT part of the API.
		#
		# magic cookies keep track of both incoming and outgoing cookies, setting the response's cookies as well as the combined cookie respetory (held by the request object).
		#
		# use only the []= for magic cookies. merge and update might not set the response cookies.
		class Cookies < ::Hash
			# sets the Magic Cookie's controller object (which holds the response object and it's `set_cookie` method).
			def set_response response
				@response = response
			end
			# overrides the []= method to set the cookie for the response (by encoding it and preparing it to be sent), as well as to save the cookie in the combined cookie jar (unencoded and available).
			def []= key, val
				return super unless @response
				if key.is_a?(Symbol) && self.has_key?( key.to_s)
					key = key.to_s
				elsif self.has_key?( key.to_s.to_sym)
					key = key.to_s.to_sym
				end
				@response.set_cookie key, (val ? val.to_s.dup : nil)
				super
			end
		end

		# parses an HTTP request (quary, body data etc')
		def self.parse_request request
			
		end

		# re-encodes a string into UTF-8
		def self.make_utf8!(string, encoding= ::Encoding::UTF_8)
			return false unless string
			string.force_encoding(::Encoding::ASCII_8BIT).encode!(encoding, ::Encoding::ASCII_8BIT, invalid: :replace, undef: :replace, replace: ''.freeze) unless string.force_encoding(encoding).valid_encoding?
			string
		end

		# re-encodes a string into UTF-8
		def self.try_utf8!(string, encoding= ::Encoding::UTF_8)
			return false unless string
			string.force_encoding(::Encoding::ASCII_8BIT) unless string.force_encoding(encoding).valid_encoding?
			string
		end

		def self.encode_url str
			str.to_s.dup.force_encoding(::Encoding::ASCII_8BIT).gsub(/[^a-z0-9\*\.\_\-]/i) {|m| '%%%02x'.freeze % m.ord }
			# str.to_s.b.gsub(/[^a-z0-9\*\.\_\-]/i) {|m| '%%%02x' % m.ord }
		end

		# Adds paramaters to a Hash object, according to the GRHttp's server conventions.
		def self.add_param_to_hash name, value, target
			begin
				c = target
				val = rubyfy! value
				a = name.chomp('[]'.freeze).split('['.freeze)

				a[0...-1].inject(target) do |h, n|
					n.chomp!(']'.freeze);
					n.strip!;
					raise "malformed parameter name for #{name}" if n.empty?
					n = (n.to_i.to_s == n) ?  n.to_i : n.to_sym            
					c = (h[n] ||= {})
				end
				n = a.last
				n.chomp!(']'); n.strip!;
				n = n.empty? ? nil : ( (n.to_i.to_s == n) ?  n.to_i : n.to_sym )
				if n
					if c[n]
						c[n].is_a?(Array) ? (c[n] << val) : (c[n] = [c[n], val])
					else
						c[n] = val
					end
				else
					if c[n]
						c[n].is_a?(Array) ? (c[n] << val) : (c[n] = [c[n], val])
					else
						c[n] = [val]
					end
				end
				val
			rescue => e
				GReactor.error e
				GReactor.error "(Silent): parameters parse error for #{name} ... maybe conflicts with a different set?"
				target[name] = val
			end
		end

		# extracts parameters from the query
		def self.extract_params data, target_hash
			data.each do |set|
				list = set.split('='.freeze, 2)
				list.each {|s|  next unless s; s.gsub!('+'.freeze, '%20'.freeze); s.gsub!(/\%[0-9a-f]{2}/i) {|m| m[1..2].to_i(16).chr}; s.gsub!(/&#[0-9]{4};/i) {|m| [m[2..5].to_i].pack 'U'.freeze }}
				add_param_to_hash list.shift, list.shift, target_hash
			end
		end
		# extracts parameters from the query
		def self.extract_header data, target_hash
			data.each do |set|
				list = set.split('='.freeze, 2)
				list.each {|s| next unless s; s.gsub!(/\%[0-9a-f]{2}/i) {|m| m[1..2].to_i(16).chr}; s.gsub!(/&#[0-9]{4};/i) {|m| [m[2..5].to_i].pack 'U'.freeze }}
				add_param_to_hash list.shift, list.shift, target_hash
			end
		end
		# Changes String to a Ruby Object, if it's a special string...
		def self.rubyfy!(string)
			return string unless string.is_a?(String)
			try_utf8! string
			if string == 'true'.freeze
				string = true
			elsif string == 'false'.freeze
				string = false
			elsif string.to_i.to_s == string
				string = string.to_i
			end
			string
		end


	end

	# An HTTP Request
	class Request < Hash

		def initialize io = nil
			super()
			self[:io] = io if io
			self[:cookies] = Base::Cookies.new
			self[:params] = {}
		end

		public

		# the request's headers
		def headers
			self.select {|k,v| k.is_a? String }
		end
		# the request's method (GET, POST... etc').
		def request_method
			self[:method]
		end
		# set request's method (GET, POST... etc').
		def request_method= value
			self[:method] = value
		end
		# the parameters sent by the client.
		def params
			self[:params]
		end
		# the cookies sent by the client.
		def cookies
			self[:cookies]
		end

		# the query string
		def query
			self[:query]
		end

		# the original (frozen) path (resource requested).
		def original_path
			self[:original_path]
		end

		# the requested path (rewritable).
		def path
			self[:path]
		end
		def path=(new_path)
			self[:path] = new_path
		end

		# The HTTP version for this request
		def version
			self[:version]
		end

		# the base url ([http/https]://host[:port])
		def base_url switch_scheme = nil
			"#{switch_protocol || self[:requested_protocol]}://#{self[:host_name]}#{self[:port]? ":#{self[:port]}" : ''}"
		end

		# the request's url, without any GET parameters ([http/https]://host[:port]/path)
		def request_url switch_scheme = nil
			"#{base_url switch_protocol}#{self[:original_path]}"
		end

		# the protocol managing this request
		def scheme
			self[:scheme]
		end

		# @return [true, false] returns true if the requested was an SSL protocol (true also if the connection is clear-text behind an SSL Proxy, such as with some PaaS providers).
		def ssl?
			io.ssl? || self[:scheme] == 'https'.freeze || self[:scheme] == 'wss'.freeze
		end
		alias :secure? :ssl?

		# @return [BasicIO, SSLBasicIO] the io used for the request.
		def io
			self[:io]			
		end

		# method recognition

		HTTP_GET = 'GET'.freeze
		# returns true of the method == GET
		def get?
			self[:method] == HTTP_GET
		end

		HTTP_HEAD = 'HEAD'.freeze
		# returns true of the method == HEAD
		def head?
			self[:method] == HTTP_HEAD
		end
		HTTP_POST = 'POST'.freeze
		# returns true of the method == POST
		def post?
			self[:method] == HTTP_POST
		end
		HTTP_PUT = 'PUT'.freeze
		# returns true of the method == PUT
		def put?
			self[:method] == HTTP_PUT
		end
		HTTP_DELETE = 'DELETE'.freeze
		# returns true of the method == DELETE
		def delete?
			self[:method] == HTTP_DELETE
		end
		HTTP_TRACE = 'TRACE'.freeze
		# returns true of the method == TRACE
		def trace?
			self[:method] == HTTP_TRACE
		end
		HTTP_OPTIONS = 'OPTIONS'.freeze
		# returns true of the method == OPTIONS
		def options?
			self[:method] == HTTP_OPTIONS
		end
		HTTP_CONNECT = 'CONNECT'.freeze
		# returns true of the method == CONNECT
		def connect?
			self[:method] == HTTP_CONNECT
		end
		HTTP_PATCH = 'PATCH'.freeze
		# returns true of the method == PATCH
		def patch?
			self[:method] == HTTP_PATCH
		end
		HTTP_CTYPE = 'content-type'.freeze; HTTP_JSON = /application\/json/
		# returns true if the request is of type JSON.
		def json?
			self[HTTP_CTYPE] =~ HTTP_JSON
		end
		HTTP_XML = /text\/xml/
		# returns true if the request is of type XML.
		def xml?
			self[HTTP_CTYPE].match HTTP_XML
		end
		HTTP_UPGRADE = 'upgrade'.freeze ; HTTP_UPGRADE_REGEX = /upg/i ; HTTP_WEBSOCKET = 'websocket'.freeze; HTTP_CONNECTION = 'connection'.freeze
		# returns true if this is a websocket upgrade request
		def websocket?
			@is_upgrade ||= (self[HTTP_UPGRADE] && self[HTTP_UPGRADE].to_s.downcase == HTTP_WEBSOCKET &&  self[HTTP_CONNECTION].to_s =~ HTTP_UPGRADE_REGEX && true)
		end

	end

	class Response
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
			Base.parse_request request
			@status = status
			@headers = headers
			@body = content || []
			@io = request[:io]
			@request.cookies.set_response self
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
		# Since GRHttp is likely to be multi-threading (depending on your settings and architecture), it is important that
		# streaming blocks are nested rather than chained. Chained streaming blocks might be executed in parallel and 
		# suffer frome race conditions that might lead to the response being corrupted.
		#
		# Accepts a required block. i.e.
		#
		#     response.stream_async {sleep 1; response << "Hello Streaming"}
		#     # OR, you can nest (but not chain) the streaming calls
		#     response.stream_async do
		#       sleep 1
		#       response << "Hello Streaming"
		#       response.stream_async do
		#           sleep 1
		#           response << "\r\nGoodbye Streaming"
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

		# Creates nested streaming blocks for an enumerable object. Once all streaming blocks are done, the response will automatically finish.
		#
		# Since streaming blocks might run in parallel, nesting the streaming blocks is important...
		#
		# However, manually nesting hundreds of nesting blocks is time consuming and error prone.
		#
		# {.sream_enum} allows you to stream an enumerable knowing that Plezi will nest the streaming blocks dynamically.
		#
		# Accepts:
		# enum:: an Enumerable or an object that answers to the `to_a` method (the array will be used to stream the )
		#
		# If an Array is passed to the enumerable, it will be changed and emptied as the streaming progresses.
		# So, if preserving the array is important, please create a shallow copy of the array first using the `.dup` method.
		#
		# i.e.:
		#
		#      data = "Hello world!".chars
		#      response.stream_enum(data.each_with_index) {|c, i| response << c; sleep i/10.0 }
		#
		#
		# @return [true, Exception] The method returns immidiatly with a value of true unless it is impossible to stream the response (an exception will be raised) or a block wasn't supplied.
		def stream_enum enum, &block
			enum = enum.to_a
			return if enum.empty?
			stream_async do
				args = enum.shift
				block.call(*args)
				stream_enum enum, &block
			end
		end



		# # Creates and returns the session storage object.
		# #
		# # By default and for security reasons, session id's created on a secure connection will NOT be available on a non secure connection (SSL/TLS).
		# #
		# # Since this method renews the session_id's cookie's validity (update's it's times-stump), it must be called for the first time BEFORE the headers are sent.
		# #
		# # After the session object was created using this method call, it should be safe to continue updating the session data even after the headers were sent and this method would act as an accessor for the already existing session object.
		# #
		# # @return [Hash like storage] creates and returns the session storage object with all the data from a previous connection.
		# def session
		# 	return @session if @session
		# 	id = request.cookies[GRHttp.session_token.to_sym] || SecureRandom.uuid
		# 	set_cookie GRHttp.session_token, id, expires: (Time.now+86_400), secure:  @request.ssl?
		# 	@session = GRHttp::SessionManager.get id
		# end

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

		# sets a response header. response headers should be a downcase String or Symbol.
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


		COOKIE_NAME_REGEXP = /[\x00-\x20\(\)\<\>@,;:\\\"\/\[\]\?\=\{\}\s]/

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
			raise 'Illegal cookie name' if name =~ COOKIE_NAME_REGEXP
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
		# # Danger Zone (internally used method, use with care): fix response's headers before sending them (date, connection and transfer-coding).
		# def send_headers
		# 	return false if @headers.frozen?
		# 	fix_cookie_headers
		# 	out = ''

		# 	out << "#{@http_version} #{@status} #{STATUS_CODES[@status] || 'unknown'}\r\nDate: #{Time.now.httpdate}\r\n"

		# 	# unless @headers['connection'] || (@request[:version].to_f <= 1 && (@request['connection'].nil? || !@request['connection'].match(/^k/i))) || (@request['connection'] && @request['connection'].match(/^c/i))
		# 	if (@request[:version].to_f > 1 && @request['connection'.freeze].nil?) || @request['connection'.freeze].to_s =~ /^k/i || (@headers['connection'.freeze] && @headers['connection'.freeze] =~ /^k/i) # simpler
		# 		@io[:keep_alive] = true
		# 		out << "Connection: Keep-Alive\r\nKeep-Alive: timeout=5\r\n".freeze
		# 	else
		# 		@headers['connection'.freeze] ||= 'close'.freeze
		# 	end

		# 	if @headers['content-length'.freeze]
		# 		@chunked = false
		# 	else
		# 		@chunked = true
		# 		out << "Transfer-Encoding: chunked\r\n".freeze
		# 	end
		# 	@headers.each {|k,v| out << "#{k.to_s}: #{v}\r\n"}
		# 	out << "Cache-Control: max-age=0, no-cache\r\n".freeze unless @headers['cache-control'.freeze]
		# 	@cookies.each {|k,v| out << "Set-Cookie: #{k.to_s}=#{v.to_s}\r\n"}
		# 	out << "\r\n"

		# 	@io.write out
		# 	out.clear
		# 	@headers.freeze
		# 	if @body && @body.is_a?(Array)
		# 		@body = @body.join 
		# 	end
		# 	send_body(@body) && (@body.frozen? ? true : @body.clear) if @body && !@body.empty? && !request.head?
		# 	@body = nil
		# 	true
		# end

		# # sends the body or part thereof
		# def send_body data
		# 	return nil unless data
		# 	if @chunked
		# 		@io.write "#{data.bytesize.to_s(16)}\r\n#{data}\r\n"
		# 		@bytes_sent += data.bytesize
		# 	else
		# 		@io.write data
		# 		@bytes_sent += data.bytesize
		# 	end

		# end

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
			# write nil
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