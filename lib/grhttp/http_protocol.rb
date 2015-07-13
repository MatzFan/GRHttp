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
	class HTTP < GReactor::Protocol

		def initialize io
			@request = HTTPRequest.new io
			super
		end

		def on_request request, response
			response << request.to_s
			# length = request.to_s.bytesize
			# send "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: #{length}\r\nConnection: keep-alive\r\nKeep-Alive: 5\r\n\r\n#{request.to_s}"
			# t_now = Time.now
			# GR.log_raw "#{request[:client_ip]} [#{t_now.utc}] \"#{request[:method]} #{request[:original_path]} #{request[:requested_protocol]}\/#{request[:version].to_s}\" #{status} #{"%i" % ((t_now - request[:time_recieved])*1000)}ms\n" # %0.3f
			# puts "#{request[:client_ip]} [#{Time.now.utc}] \"#{request[:method]} #{request[:original_path]} #{request[:requested_protocol]}\/#{request[:version]}\" #{status} #{bytes_sent.to_s} #{"%i" % ((Time.now - request[:time_recieved])*1000)}ms\n" # %0.3f
			# request[:io].send "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\nConnection: keep-alive\r\nKeep-Alive: 5\r\n\r\nHello World\r\n"
		end

		def on_connect
		end
		def on_message data
			data = StringIO.new data
			until data.eof?
				request = @request
				unless request[:method]
					request[:time_recieved] = Time.now
					request[:method], request[:query], request[:version] = data.gets.split /[\s]+/
					return io.close unless request[:method].match(HTTP_METHODS_REGEXP) && request[:query] && request[:version]				
				end
				until request[:headers_complete] || data.eof?
					header = data.gets
					if header.match EOHEADERS
						request[:headers_complete] = true
					else
						m = header.split /\:[\s]*/ , 2
						if m[0].downcase == 'cookie'
							HTTP.extract_data m[1].split(HEADER_SPLIT_REGX), @request.cookies, :uri
						elsif m[1]
							HTTP.make_utf8!(m[0]).downcase!
							HTTP.make_utf8! m[1]
							request[ m[0] ] ? (request[ m[0] ] << ", #{m[1]}") : (request[ m[0] ] = m[1])
						end
					end
				end
				until request[:body_complete]
					if request['transfer-coding'] == 'chunked'
						puts 'chunk'
						# ad mid chunk logic here
						if io[:length].to_i == 0
							chunk = data.gets
							return unless chunk
							io[:length] = chunk.match.to_i(16)
							io.close && raise("Unknown error parsing chunked data") unless io[:length]
							request[:body_complete] = true && break if io[:length] == 0
							io[:act_length] = 0
							request[:body] ||= ''
						end
						chunk = data.read(io[:length] - io[:act_length])
						return unless chunk
						request[:body] << chunk
						io[:act_length] += chunk.bytesize
						(io[:act_length] = io[:length] = 0) && (data.gets) if io[:act_length] >= io[:length]
					elsif request['content-length'] && request['content-length'].to_i != 0
						puts 'len'
						request[:body] ||= ''
						packet = data.read(request['content-length'].to_i - request[:body].bytesize)
						return unless packet
						request[:body] << packet
						request[:body_complete] = true if request['content-length'].to_i - request[:body].bytesize <= 0
					elsif request['content-type']
						GR.warn 'Body type protocol error.' unless request[:body]
						line = data.gets
						return unless line
						(request[:body] ||= '') << line
						request[:body_complete] = true if line.match EOHEADERS
					else
						request[:body_complete] = true
					end
				end
				complete_request if request[:body_complete]
			end
		end

		protected
		HTTP_METHODS = %w{GET HEAD POST PUT DELETE TRACE OPTIONS CONNECT PATCH}
		HTTP_METHODS_REGEXP = /\A#{HTTP_METHODS.join('|')}/i
		EOHEADERS = /^[\r]?\n/
		HEADER_REGX = /^([^:]*):[\s]*([^\r\n]*)/
		FULL_QUARY_REGEX = /(([a-z0-9A-Z]+):\/\/)?(([^\/\:]+))?(:([0-9]+))?([^\?\#]*)(\?([^\#]*))?/
		REG_QUARY_REGEX = /([^\?\#]*)(\?([^\#]*))?/
		PARAM_SPLIT_REGX = /[&;]/
		HEADER_SPLIT_REGX = /[;,][\s]?/

		def complete_request
			request = @request
			@request = HTTPRequest.new io
			request[:client_ip] = @request['x-forwarded-for'].to_s.split(/,[\s]?/)[0] || (io.io.remote_address.ip_address) rescue 'unknown IP'
			request[:version] = request[:version].match(/[\d\.]+/)[0]

			request[:requested_protocol] = request['x-forwarded-proto'] || ( io.ssl? ? 'https' : 'http')
			tmp = request['host'] ? request['host'].split(':') : []
			request[:host_name] = tmp[0]
			request[:port] = tmp[1] || nil

			tmp = request[:query].split '?', 2
			request[:original_path] = tmp[0]
			request[:quary_params] = tmp[1]
			HTTP.extract_data tmp[1].split(PARAM_SPLIT_REGX), (request[:params] ||= {}) if tmp[1]
			# if m = request[:query].match FULL_QUARY_REGEX
				# request[:requested_protocol] = m[1] || request['x-forwarded-proto'] || ( io.ssl? ? 'https' : 'http')
				# request[:host_name] = m[4] || (request['host'] ? request['host'].match(/^[^:]*/).to_s : nil)
				# request[:port] = m[6] || (request['host'] ? request['host'].match(/:([0-9]*)/).to_a[1] : nil)
				# request[:original_path] = HTTP.decode(m[7], :uri) || '/'
				# request['host'] ||= "#{request[:host_name]}:#{request[:port]}"

			 	# parse query for params - m[9] is the data part of the query
			 	# if m[9]
			 	# 	HTTP.extract_data m[9].split(PARAM_SPLIT_REGX), request[:params]
			 	# end
			# end

			# self.class.read_body request if request[:body]

			# return ws_upgrade if request.upgrade?
			response = HTTPResponse.new request
			on_request request, response
			response.try_finish
		end

		public
		

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

		protected
		# read the body's data and parse any incoming data.
		def self.read_body request
			# parse content
			case request['content-type'].to_s
			when /x-www-form-urlencoded/
				HTTP.extract_data request.delete(:body).split(/[&;]/), request[:params], :form # :uri
			when /multipart\/form-data/
				read_multipart request, request, request.delete(:body)
			when /text\/xml/
				# to-do support xml?
				HTTP.make_utf8! request[:body]
				nil
			when /application\/json/
				JSON.parse(HTTP.make_utf8! request[:body]).each {|k, v| HTTP.add_param_to_hash k, v, request[:params]}
			end
		end

		# parse a mime/multipart body or part.
		def self.read_multipart request, headers, part, name_prefix = ''
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
						read_multipart request, h, p, name_prefix
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
