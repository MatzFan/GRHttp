module GRHttp

	# These are some HTTP helper methods supplied for your convinience and the Generic HTTP server's use.
	#
	module HTTP

		public

		# re-encodes a string into UTF-8
		def self.make_utf8!(string, encoding= ::Encoding::UTF_8)
			return false unless string
			string.force_encoding(::Encoding::ASCII_8BIT).encode!(encoding, ::Encoding::ASCII_8BIT, invalid: :replace, undef: :replace, replace: '') unless string.force_encoding(encoding).valid_encoding?
			string
		end

		# re-encodes a string into UTF-8
		def self.try_utf8!(string, encoding= ::Encoding::UTF_8)
			return false unless string
			string.force_encoding(::Encoding::ASCII_8BIT) unless string.force_encoding(encoding).valid_encoding?
			string
		end

		# Escapes html. based on the WEBRick source code, escapes &, ", > and < in a String object
		def self.escape(string)
			# string.gsub('&', '&amp;')
			# .gsub('"', '&quot;')
			# .gsub('>', '&gt;')
			# .gsub('<', '&lt;')
			CGI.escapeHTML(string.to_s)
		end
		
		# Decodes data from :form, :html and :url (default) escaped strings.
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
		# Encodes data for :html, :url and :form (default) escaped strings.
		def self.encode object, decode_method = :form
			if object.is_a?(Hash)
				object.values.each {|v| encode v, decode_method}
			elsif object.is_a?(Array)
				object.each {|v| encode v, decode_method}
			elsif object.is_a?(String)
				case decode_method
				when :uri, :url, :form
					object.force_encoding ::Encoding::ASCII_8BIT
					object.gsub!(/[^a-zA-Z0-9\*\.\_\-]/) {|m| '%%%02x' % m.ord }
				when :html
					object.gsub!('&', '&amp;')
					object.gsub!('"', '&quot;')
					object.gsub!('>', '&gt;')
					object.gsub!('<', '&lt;')
					object.gsub!(/[^\sa-zA-Z\d\&\;]/) {|m| '&#%04d;' % m.unpack('U')[0] }
					# object.gsub!(/[^\s]/) {|m| "&#%04d;" % m.unpack('U')[0] }
					object.force_encoding ::Encoding::ASCII_8BIT
				when :utf8
					object.gsub!(/[^\sa-zA-Z\d]/) {|m| '&#%04d;' % m.unpack('U')[0] }
					object.force_encoding ::Encoding::ASCII_8BIT
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

		def self.encode_url str
			str.to_s.dup.force_encoding(::Encoding::ASCII_8BIT).gsub(/[^a-z0-9\*\.\_\-]/i) {|m| '%%%02x' % m.ord }
			# str.to_s.b.gsub(/[^a-z0-9\*\.\_\-]/i) {|m| '%%%02x' % m.ord }
		end

		# Adds paramaters to a Hash object, according to the GRHttp's server conventions.
		def self.add_param_to_hash name, value, target
			begin
				c = target
				val = rubyfy! value
				a = name.chomp('[]').split('[')

				a[0...-1].inject(target) do |h, n|
					n.chomp!(']');
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
			# begin
			# 	h = target
			# 	val = rubyfy! value
			# 	a = name.chomp('[]').split('[')
			# 	len = a.count - 1
			# 	p = nil
			# 	a.each.with_index do |n, i|
			# 		n.chomp!(']');
			# 		n.strip!;
			# 		n = n.empty? ? nil : (n.to_i.to_s == n) ?  n.to_i : n.to_sym
			# 		if i == len
			# 			if n
			# 				if h[n]
			# 					h[n].is_a?(Array) ? (h[n] << val) : (h[n] = [h[n], val])
			# 				else
			# 					h[n] = val
			# 				end
			# 			else
			# 				h = (h[n] ||= [])
			# 				h << val
			# 			end
			# 		else
			# 			h = ( h[n] ||= {} )
			# 		end
			# 	end
			# 	val
			# rescue => e
			# 	GReactor.error e
			# 	GReactor.error "(Silent): parameters parse error for #{name} ... maybe conflicts with a different set?"
			# 	target[name] = val
			# end
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

		# extracts parameters from the query
		def self.extract_params data, target_hash
			data.each do |set|
				list = set.split('=', 2)
				list.each {|s|  next unless s; s.gsub!('+', '%20'); s.gsub!(/\%[0-9a-f]{2}/i) {|m| m[1..2].to_i(16).chr}; s.gsub!(/&#[0-9]{4};/i) {|m| [m[2..5].to_i].pack 'U' }}
				add_param_to_hash list.shift, list.shift, target_hash
			end
		end
		# extracts parameters from the query
		def self.extract_header data, target_hash
			data.each do |set|
				list = set.split('=', 2)
				list.each {|s| next unless s; s.gsub!(/\%[0-9a-f]{2}/i) {|m| m[1..2].to_i(16).chr}; s.gsub!(/&#[0-9]{4};/i) {|m| [m[2..5].to_i].pack 'U' }}
				add_param_to_hash list.shift, list.shift, target_hash
			end
		end
		# Changes String to a Ruby Object, if it's a special string...
		def self.rubyfy!(string)
			return string unless string.is_a?(String)
			try_utf8! string
			if string == 'true'
				string = true
			elsif string == 'false'
				string = false
			elsif string.to_i.to_s == string
				string = string.to_i
			end
			string
		end

		def self._parse_http io, data
			request = io[:request] ||= HTTPRequest.new(io)
			unless request[:method]
				request[:time_recieved] = Time.now
				request[:method], request[:query], request[:version] = data.gets.split /[\s]+/
				return (data.pos = data.length) && io.close && false unless request[:method].match(HTTP_METHODS_REGEXP) && request[:query] && request[:version]				
			end
			until request[:headers_complete] || data.eof?
				header = data.gets
				next unless header
				if header.match EOHEADERS
					request[:headers_complete] = true
				else
					m = header.strip.split /\:[\s]*/ , 2
					m[0].downcase! if m[0]
					if m[0] == 'cookie'
						# save cookies for Rack, if applicable
						request[ m[0] ] ? (request[ m[0] ] << "; #{m[1].strip}") : (request[ m[0] ] = m[1].strip ) if request[:io].params[:http_handler] == ::GRHttp::Base::Rack
						# extract data
						HTTP.extract_header m[1].split(HEADER_SPLIT_REGX), request.cookies
					elsif m[0] == 'set-cookie'
						m[1] = m[1].split(';')[0]
						HTTP.extract_header m[1].split(HEADER_SPLIT_REGX), request.cookies
					elsif m[1]
						HTTP.make_utf8!(m[0])
						HTTP.make_utf8!(m[1])
						request[ m[0] ] ? (request[ m[0] ] << ", #{m[1]}") : (request[ m[0] ] = m[1])
					end
				end
			end
			while request[:headers_complete] && !request[:body_complete]
				if request['transfer-coding'] == 'chunked'
					# ad mid chunk logic here
					if io[:length].to_i == 0
						chunk = data.gets
						return false unless chunk
						io[:length] = chunk.match.to_i(16)
						io.close && raise("Unknown error parsing chunked data") unless io[:length]
						request[:body_complete] = true && break if io[:length] == 0
						io[:act_length] = 0
						request[:body] ||= ''
					end
					chunk = data.read(io[:length] - io[:act_length])
					return false unless chunk
					request[:body] << chunk
					io[:act_length] += chunk.bytesize
					(io[:act_length] = io[:length] = 0) && (data.gets) if io[:act_length] >= io[:length]
				elsif request['content-length'] && request['content-length'].to_i != 0
					request[:body] ||= ''
					packet = data.read(request['content-length'].to_i - request[:body].bytesize)
					return false unless packet
					request[:body] << packet
					request[:body_complete] = true if request['content-length'].to_i - request[:body].bytesize <= 0
				elsif request['content-type']
					GR.warn 'Body type protocol error.' unless request[:body]
					line = data.gets
					return false unless line
					(request[:body] ||= '') << line
					request[:body_complete] = true if line.match EOHEADERS
				else
					request[:body_complete] = true
				end
			end
			_finialize_request request if request[:body_complete]
		end

		# read the body's data and parse any incoming data.
		def self._finialize_request request			
			request[:client_ip] = request['x-forwarded-for'].to_s.split(/,[\s]?/)[0] || (request[:io].io.remote_address.ip_address) rescue 'unknown IP'
			request[:version] = (request[:version] || '1.1').to_s.match(/[\d\.]+/)[0]

			request[:requested_protocol] = request['x-forwarded-proto'] ? request['x-forwarded-proto'].downcase : ( request[:io].ssl? ? 'https' : 'http')
			tmp = request['host'] ? request['host'].split(':') : []
			request[:host_name] = tmp[0]
			request[:port] = tmp[1] || nil

			tmp = request[:query].split('?', 2)
			request[:path] = tmp[0].chomp('/')
			request[:original_path] = tmp[0].freeze
			request[:quary_params] = tmp[1]
			HTTP.extract_params tmp[1].split(PARAM_SPLIT_REGX), (request[:params] ||= {}) if tmp[1]
			HTTP._read_body request if request[:body]


			#check for server-responses
			case request.request_method
			when 'TRACE'
				request[:io][:request] = nil
				request[:io].close
				return false
			when 'OPTIONS'
				response = HTTPResponse.new request
				request[:io][:request] = nil
				response[:Allow] = 'GET,HEAD,POST,PUT,DELETE,OPTIONS'
				response['access-control-allow-origin'] = '*'
				response['content-length'] = 0
				response.finish
				return false
			end

			true

			# if m = request[:query].match FULL_QUARY_REGEX
				# request[:requested_protocol] = m[1] || request['x-forwarded-proto'] || ( request[:io].ssl? ? 'https' : 'http')
				# request[:host_name] = m[4] || (request['host'] ? request['host'].match(/^[^:]*/).to_s : nil)
				# request[:port] = m[6] || (request['host'] ? request['host'].match(/:([0-9]*)/).to_a[1] : nil)
				# request[:original_path] = HTTP.decode(m[7], :uri) || '/'
				# request['host'] ||= "#{request[:host_name]}:#{request[:port]}"

				# parse query for params - m[9] is the data part of the query
				# if m[9]
				# 	HTTP.extract_params m[9].split(PARAM_SPLIT_REGX), request[:params]
				# end
			# end
		end

		# read the body's data and parse any incoming data.
		def self._read_body request
			# save body for Rack, if applicable
			request[:rack_input] = StringIO.new(request[:body].dup.force_encoding(::Encoding::ASCII_8BIT)) if request[:io].params[:http_handler] == ::GRHttp::Base::Rack
			# parse content
			case request['content-type'].to_s
			when /x-www-form-urlencoded/
				HTTP.extract_params request.delete(:body).split(/[&;]/), request[:params] #, :form # :uri
			when /multipart\/form-data/
				_read_multipart request, request, request.delete(:body)
			when /text\/xml/
				# to-do support xml?
				HTTP.make_utf8! request[:body]
				nil
			when /application\/json/
				JSON.parse(HTTP.make_utf8! request[:body]).each {|k, v| HTTP.add_param_to_hash k, v, request[:params]} rescue true
			end
		end

		# parse a mime/multipart body or part.
		def self._read_multipart request, headers, part, name_prefix = ''
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
						_read_multipart request, h, p, name_prefix
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

			HTTP.extract_header headers['content-disposition'].match(/[^;];([^\r\n]*)/)[1].split(/[;,][\s]?/), cd

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