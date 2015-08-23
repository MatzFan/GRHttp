module GRHttp
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
			# if m = request[:query].match /(([a-z0-9A-Z]+):\/\/)?(([^\/\:]+))?(:([0-9]+))?([^\?\#]*)(\?([^\#]*))?/
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
			return request if request[:scheme]
			request[:client_ip] = request['x-forwarded-for'.freeze].to_s.split(/,[\s]?/)[0] || (request[:io].io.remote_address.ip_address) rescue 'unknown IP'.freeze
			request[:version] = (request[:version] || '1.1'.freeze).to_s.match(/[\d\.]+/)[0]

			request[:scheme] = request['x-forwarded-proto'.freeze] ? request['x-forwarded-proto'.freeze].downcase : ( request[:io].ssl? ? 'https'.freeze : 'http'.freeze)
			tmp = request['host'.freeze] ? request['host'.freeze].split(':') : []
			request[:host_name] = tmp[0]
			request[:port] = tmp[1] || nil

			tmp = request[:query].split('?', 2)
			request[:path] = tmp[0].chomp('/')
			request[:original_path] = tmp[0].freeze
			request[:quary_params] = tmp[1]
			extract_params tmp[1].split(PARAM_SPLIT_REGX), (request[:params] ||= {}) if tmp[1]

			if request['cookie']
				if request['cookie'].is_a?(Array)
					tmp = []
					request['cookie'].each {|s| s.split(/[;,][\s]?/.freeze).each { |c| tmp << c } }
					request['cookie'] = tmp
					extract_header tmp, request.cookies
				else
					extract_header request['cookie'].split(/[;,][\s]?/.freeze, request.cookies
				end
			elsif request['set-cookie']
				request['set-cookie'] = [ request['set-cookie'] ] unless request['set-cookie'].is_a?(Array)
				tmp = []
				request['set-cookie'].each {|s| tmp << s.split(/[;][\s]?/.freeze)[0] }
				request['set-cookie'] = tmp
				extract_header tmp, request.cookies
			end

			read_body request if request[:body]

			request
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

		# read the body's data and parse any incoming data.
		def self.read_body request
			# save body for Rack, if applicable
			request[:rack_input] = StringIO.new(request[:body].dup.force_encoding(::Encoding::ASCII_8BIT)) if request[:io].params[:http_handler] == ::GRHttp::Base::Rack
			# parse content
			case request['content-type'.freeze].to_s
			when /x-www-form-urlencoded/
				extract_params request.delete(:body).split(/[&;]/), request[:params] #, :form # :uri
			when /multipart\/form-data/
				read_multipart request, request, request.delete(:body)
			when /text\/xml/
				# to-do support xml?
				make_utf8! request[:body]
				nil
			when /application\/json/
				JSON.parse(make_utf8! request[:body]).each {|k, v| add_param_to_hash k, v, request[:params]} rescue true
			end
		end


	end
end
