require 'stringio'
module GRHttp

	# This is a basic HTTP handler class for the reactor.
	#
	# To use the HTTP class, inherit the class and override any of the following methods:
	# #on_connect:: called AFTER a connection is accepted but BEFORE ant requests are handled.
	# #on_request request:: called whenever data is recieved from the IO.
	# #on_disconnect:: called AFTER the IO is closed.
	# #on_upgrade:: called BEFORE a WebSocket connection is established. Should return the WebSocket handler (replaces this HTTP Protocol object for the specific connection) or false (refuses the connection).
	#
	# Do NOT override the `#on_message data` method, as this class uses the #on_message method to parse incoming requests.
	#
	module HTTP

		module_function

		# This method is called by the reactor. Don't override this method.
		def call io
			data = io.read
			return unless data
			data = StringIO.new data
			io[:step] ||= 0
			until data.eof?
				request = io[:request] || HTTPRequest.new(io)
				parse_quary data, request, io
				parse_head data, request, io
				parse_body data, request, io
			end
		end

		# Override this method to answer HTTP requests.
		#
		# This method is called every time an HTTP request is accepted through the connection.
		#
		# The method is called from withing an io.lock, to avoide two or more requests
		# made by the same client being answered at the same time.
		#
		# Due to HTTP's specs, it is important the the request's response is finished within scope of the lock
		# (by the time this method complete's it's execution).
		#
		# The default implementation simply sends back the parsed request's object.
		#
		# To send data or close the connection use the request's IO wrapper object at: request[:io].
		def on_request request
			response = HTTPResponse.new request
			response << request.to_s
			response.finish
			# length = request.to_s.bytesize
			# request[:io].send "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: #{length}\r\nConnection: keep-alive\r\nKeep-Alive: 5\r\n\r\n#{request.to_s}"
			# request[:io].send "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\nConnection: keep-alive\r\nKeep-Alive: 5\r\n\r\nHello World\r\n"
		end

		# Override this method to handle Websocket connections.
		#
		# This method will be called BEFORE the protocol changes from HTTP to Websockets and allows you to
		# either set the Websocket connection handler* or refuse the connection.
		#
		# This method should return false in order to refuse a Websocket connection (default behavior).
		#
		# Otherwise, this method should return the new handler for the connection (the object that will handle the Websocket communication).
		#
		# The new handler (Usually a {GRHttp::WSProtocol} subclass) should handle the Websocket handshake.
		#
		# The default is to return false (refuse the Websocket connection).
		#
		#
		# \* Since the Websocket Protocol requires parsing of the messages recieved,
		# it is recommended to use a sub-class of WSProtocol for message handling.
		def on_upgrade request
			false
		end

		protected

		HTTP_METHODS = %w{GET HEAD POST PUT DELETE TRACE OPTIONS CONNECT PATCH}
		HTTP_METHODS_REGEXP = /\A#{HTTP_METHODS.join('|')}/i

		QUARY_SPLIT_REGX = /[\s]+/
		HTTP_VER_REGX = /[0-9\.]+/

		def self.parse_quary data, request, io
			quary = true
			while io[:step] == 0
				quary = data.gets
				return unless quary
				next unless quary.match(HTTP_METHODS_REGEXP)
				request[:time_recieved] = Time.now
				request[:method], request[:query], request[:version] = quary.split(QUARY_SPLIT_REGX)
				request[:version] = (request[:version] || '1.1').match(HTTP_VER_REGX).to_s.to_f
				io[:step] = 1
				return
			end
		end

		EOHEADERS = /[\r]?\n/
		HEADER_REGX = /^([^:]*):[\s]*([^\r\n]*)/
		HEADER_SPLIT_REGX = /[;,][\s]?/
		def self.parse_head data, request, io
			return unless io[:step] == 1
			loop do
				header = data.gets
				return unless header
				if header.match EOHEADERS
					if request['transfer-coding'] || (request['content-length'] && request['content-length'].to_i != 0) || request['content-type']
						request[:body] = ''
						io[:step] = 2
						return
					else
						return complete_request request, io
					end
				end
				m = header.match(HEADER_REGX)
				case m[1].downcase
				when 'cookie'
					HTTP.extract_data m[2].split(HEADER_SPLIT_REGX), request.cookies, :uri
				else
					name = HTTP.make_utf8!(m[1]).downcase
					request[ name ] ? (request[ name ] << ", #{HTTP.make_utf8! m[2]}"): (request[ name ] =  HTTP.make_utf8! m[2])
				end if m
			end
		end
		CHUNK_REGX = /\A[a-z0-9A-Z]+/
		EOCHUNK_REGX = /^0[\r]?\n/
		def self.parse_body data, request, io
			while io[:step] == 2

				# check for body is needed, if exists and if complete
				if request['transfer-coding'] == 'chunked'
					# ad mid chunk logic here
					if io[:length].to_i == 0
						chunk = data.gets
						return unless chunk
						return complete_request request, io if chunk.match(EOCHUNK_REGX)
						io[:length] = chunk.match(CHUNK_REGX).to_i(16)
						return (io[:step] =0), raise("HTTP protocol error: unable to parse chunked enocoded message.") if io[:length] == 0					
						io[:act_length] = 0
					end
					chunk = data.read(io[:length] - io[:act_length])
					return if chunk.empty?
					request[:body] << chunk
					io[:act_length] += chunk.bytesize
					(io[:act_length] = io[:length] = 0) && (data.gets) if io[:act_length] >= io[:length]
				elsif request['content-length']
					unless io[:length]
						request['content-length'] = io[:length] = request['content-length'].to_i
						io[:act_length] = 0
					end
					request[:body] << data.read(io[:length] - io[:act_length])
					io[:act_length] = request[:body].bytesize
					return complete_request request, io if io[:act_length] >= io[:length]
					return if data.eof?
				else 
					GReactor.warn 'bad body request - trying to read'
					loop do
						line = data.gets
						break if line.match EOHEADERS
						request[:body] << line
					end
					return complete_request request, io
				end
			end 
		end

		QUARY_REGEX = /(([a-z0-9A-Z]+):\/\/)?(([^\/\:]+))?(:([0-9]+))?([^\?\#]*)(\?([^\#]*))?/
		PARAM_SPLIT_REGX = /[&;]/

		def self.complete_request request, io
			io[:step] = 0
			io[:length] = nil
			io[:request] = nil

			m = request[:query].match QUARY_REGEX
			request[:requested_protocol] = m[1] || request['x-forwarded-proto'] || ( io.ssl? ? 'https' : 'http')
			request[:host_name] = m[4] || (request['host'] ? request['host'].match(/^[^:]*/).to_s : nil)
			request[:port] = m[6] || (request['host'] ? request['host'].match(/:([0-9]*)/).to_a[1] : nil)
			request[:original_path] = HTTP.decode(m[7], :uri) || '/'
			request['host'] ||= "#{request[:host_name]}:#{request[:port]}"

			# parse query for params - m[9] is the data part of the query
			request[:params] ||= {}
			if m[9]
				HTTP.extract_data m[9].split(PARAM_SPLIT_REGX), request[:params]
			end

			HTTP.make_utf8! request[:original_path]
			request[:path] = request[:original_path].dup
			request[:original_path].freeze

			HTTP.make_utf8! request[:host_name] if request[:host_name]
			HTTP.make_utf8! request[:query]

			request[:client_ip] = request['x-forwarded-for'].to_s.split(/,[\s]?/)[0] || (io.io.remote_address.ip_address) rescue 'unknown IP'

			read_body request if request[:body]

			#check for server-responses
			case request[:method]
			when 'TRACE'
				return true
			when 'OPTIONS'
				response = HTTPResponse.new request
				response[:Allow] = 'GET,HEAD,POST,PUT,DELETE,OPTIONS'
				response['access-control-allow-origin'] = '*'
				response['content-length'] = 0
				response.finish
				return true
			end

			return ws_upgrade if request.upgrade?

			on_request request

			# GR.queue [self, request], CALL_REQUEST
		end
		# CALL_REQUEST = Proc.new {|p, r| p.on_request r}
		# review a Websocket Upgrade
		def self.ws_upgrade request, io
			new_handler = on_upgrade request
			return io.params[:handler] = new_handler if new_handler

			response = HTTPResponse.new request, 400
			response.finish
		end


		# read the body's data and parse any incoming data.
		def self.read_body request
			# parse content
			case request['content-type'].to_s
			when /x-www-form-urlencoded/
				HTTP.extract_data request.delete(:body).split(/[&;]/), request[:params], :form # :uri
			when /multipart\/form-data/
				read_multipart request, request.delete(:body)
			when /text\/xml/
				# to-do support xml?
				HTTP.make_utf8! request[:body]
				nil
			when /application\/json/
				JSON.parse(HTTP.make_utf8! request[:body]).each {|k, v| HTTP.add_param_to_hash k, v, request[:params]}
			end
		end

		# parse a mime/multipart body or part.
		def self.read_multipart headers, part, name_prefix = ''
			if headers['content-type'].to_s.match /multipart/
				boundry = headers['content-type'].match(/boundary=([^\s]+)/)[1]
				if headers['content-disposition'].to_s.match /name=/
					if name_prefix.empty?
						name_prefix << HTTP.decode(headers['content-disposition'].to_s.match(/name="([^"]*)"/)[1])
					else
						name_prefix << "[#{HTTP.decode(headers['content-disposition'].to_s.match(/name="([^"]*)"/)[1])}]"
					end
				end
				part.split(/([\r]?\n)?--#{boundry}(--)?[\r]?\n/).each do |p|
					unless p.strip.empty? || p=='--'
						# read headers
						h = {}
						m = p.slice! /\A[^\r\n]*[\r]?\n/
						while m
							break if m.match /\A[\r]?\n/
							m = m.match(/^([^:]+):[\s]?([^\r\n]+)/)
							h[m[1].downcase] = m[2] if m
							m = p.slice! /\A[^\r\n]*[\r]?\n/
						end
						# send headers and body to be read
						read_multipart h, p, name_prefix
					end
				end
				return
			end

			# require a part body to exist (data exists) for parsing
			return true if part.to_s.empty?

			# convert part to `charset` if charset is defined?

			if !headers['content-disposition']
				GReactor.error "Wrong multipart format with headers: #{headers} and body: #{part}"
				return
			end

			cd = {}

			HTTP.extract_data headers['content-disposition'].match(/[^;];([^\r\n]*)/)[1].split(/[;,][\s]?/), cd, :uri

			name = name_prefix.dup

			if name_prefix.empty?
				name << HTTP.decode(cd[:name][1..-2])
			else
				name << "[#{HTTP.decode(cd[:name][1..-2])}]"
			end
			if headers['content-type']
				HTTP.add_param_to_hash "#{name}[data]", part, request[:params]
				HTTP.add_param_to_hash "#{name}[type]", HTTP.make_utf8!(headers['content-type']), request[:params]
				cd.each {|k,v|  HTTP.add_param_to_hash "#{name}[#{k.to_s}]", HTTP.make_utf8!(v[1..-2]), request[:params] unless k == :name}
			else
				HTTP.add_param_to_hash name, HTTP.decode(part, :utf8), request[:params]
			end
			true
		end

		# re-encodes a string into UTF-8
		def self.make_utf8!(string, encoding= 'utf-8')
			return false unless string
			string.force_encoding('binary').encode!(encoding, 'binary', invalid: :replace, undef: :replace, replace: '') unless string.force_encoding(encoding).valid_encoding?
			string
		end

		def self.add_param_to_hash param_name, param_value, target_hash
			begin
				a = target_hash
				p = param_name.gsub(']',' ').split(/\[/)
				val = rubyfy! param_value
				p.each_index { |i| p[i].strip! ; n = p[i].match(/^[0-9]+$/) ? p[i].to_i : p[i].to_sym ; p[i+1] ? [ ( a[n] ||= ( p[i+1] == ' ' ? [] : {} ) ), ( a = a[n]) ] : ( a.is_a?(Hash) ? (a[n] ? (a[n].is_a?(Array) ? (a << val) : a[n] = [a[n], val] ) : (a[n] = val) ) : (a << val) ) }
			rescue Exception => e
				GReactor.error e
				GReactor.error "(Silent): parameters parse error for #{param_name} ... maybe conflicts with a different set?"
				target_hash[param_name] = rubyfy! param_value
			end
		end

		# extracts parameters from the query
		def self.extract_data data, target_hash, decode = :form
			data.each do |set|
				list = set.split('=')
				list.each {|s| HTTP.decode s, decode if s}
				add_param_to_hash list.shift, list.join('='), target_hash
			end
		end

		# Changes String to a Ruby Object, if it's a special string
		def self.rubyfy!(string)
			return false unless string
			# make_utf8! string
			if string == 'true'
				string = true
			elsif string == 'false'
				string = false
			elsif string.match(/[0-9]/) && !string.match(/[^0-9]/)
				string = string.to_i
			end
			string
		end

		public

		# Escapes html. based on the WEBRick source code, escapes &, ", > and < in a String object
		def self.escape(string)
			string.gsub(/&/n, '&amp;')
			.gsub(/\"/n, '&quot;')
			.gsub(/>/n, '&gt;')
			.gsub(/</n, '&lt;')
		end
		
		def self.decode object, decode_method = :form
			if object.is_a?(Hash)
				object.values.each {|v| decode v, decode_method}
			elsif object.is_a?(Array)
				object.each {|v| decode v, decode_method}
			elsif object.is_a?(String)
				case decode_method
				when :form
					object.gsub!('+', '%20')
					object.gsub!(/\%[0-9a-fA-F][0-9a-fA-F]/) {|m| m[1..2].to_i(16).chr}					
				when :uri, :url
					object.gsub!(/\%[0-9a-fA-F][0-9a-fA-F]/) {|m| m[1..2].to_i(16).chr}
				when :html
					object.gsub!(/&amp;/i, '&')
					object.gsub!(/&quot;/i, '"')
					object.gsub!(/&gt;/i, '>')
					object.gsub!(/&lt;/i, '<')
				when :utf8

				else

				end
				object.gsub!(/&#([0-9a-fA-F]{2});/) {|m| m.match(/[0-9a-fA-F]{2}/)[0].hex.chr}
				object.gsub!(/&#([0-9]{4});/) {|m| [m.match(/[0-9]+/)[0].to_i].pack 'U'}
				make_utf8! object
				return object
			elsif object.is_a?(Symbol)
				str = object.to_str
				decode str, decode_method
				return str.to_sym
			else
				raise "GReactor Raising Hell (don't misuse us)!"
			end
		end
		def self.encode object, decode_method = :form
			if object.is_a?(Hash)
				object.values.each {|v| encode v, decode_method}
			elsif object.is_a?(Array)
				object.each {|v| encode v, decode_method}
			elsif object.is_a?(String)
				case decode_method
				when :uri, :url, :form
					object.force_encoding 'binary'
					object.gsub!(/[^a-zA-Z0-9\*\.\_\-]/) {|m| m.ord <= 16 ? "%0#{m.ord.to_s(16)}" : "%#{m.ord.to_s(16)}"}
				when :html
					object.gsub!('&', '&amp;')
					object.gsub!('"', '&quot;')
					object.gsub!('>', '&gt;')
					object.gsub!('<', '&lt;')
					object.gsub!(/[^\sa-zA-Z\d\&\;]/) {|m| '&#%04d;' % m.unpack('U')[0] }
					# object.gsub!(/[^\s]/) {|m| "&#%04d;" % m.unpack('U')[0] }
					object.force_encoding 'binary'
				when :utf8
					object.gsub!(/[^\sa-zA-Z\d]/) {|m| '&#%04d;' % m.unpack('U')[0] }
					object.force_encoding 'binary'
				else

				end
				return object
			elsif object.is_a?(Symbol)
				str = object.to_str
				encode str, decode_method
				return str.to_sym
			else
				raise "GReactor Raising Hell (don't misuse us)!"
			end
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
