module GRHttp

	module Base

		# Legacy HTTP 1 protocol, and protocol upgrade layer (HTTP/2 / Websockets).
		class HTTP < ::GReactor::Protocol
			def on_open
				return switch_protocol(::GRHttp::HTTP2.new @io)if @io.ssl? && @io.ssl_socket.npn_protocol == 'h2'
				@refuse_requests = false
			end

			def on_message data
				return if @refuse_requests
				data = ::StringIO.new data
				l = nil
				while (l = data.gets)
					request = (@request ||= ::GRHttp::Request.new(@io))
					unless request[:method]
						request[:method], request[:query], request[:version] = l.strip.split(/[\s]+/, 3)
						return (GReactor.info('Protocol Error, closing connection.') && close) unless request[:method] =~ HTTP_METHODS_REGEXP
						request[:request_start] = Time.now
					end
					until request[:headers_complete] || (l = data.gets).nil?
						if l.include? ':'
							l = l.strip.split(':', 2)
							l[0].strip! ; l[0].downcase!
							request[l[0]] ? (request[l[0]].is_a?(Array) ? (request[l[0]] << l[1]) : request[l[0]] = [request[l[0]], l[1] ]) : (request[l[0]] = l[1])
						elsif l =~ /^[\r]?\n/
							request[:headers_complete] = true
						else
							#protocol error
							return close
						end
					end
					until request[:body_complete] && request[:headers_complete]
						if request['transfer-coding'.freeze] == 'chunked'.freeze
							# ad mid chunk logic here
							if io[:length].to_i == 0
								chunk = data.gets
								return false unless chunk
								io[:length] = chunk.to_i(16)
								(GReactor.info('Protocol Error, closing connection.') && close) unless io[:length]
								request[:body_complete] = true && break if io[:length] == 0
								io[:act_length] = 0
								request[:body] ||= ''
							end
							chunk = data.read(io[:length] - io[:act_length])
							return false unless chunk
							request[:body] << chunk
							io[:act_length] += chunk.bytesize
							(io[:act_length] = io[:length] = 0) && (data.gets) if io[:act_length] >= io[:length]
						elsif request['content-length'.freeze] && request['content-length'.freeze].to_i != 0
							request[:body] ||= ''
							packet = data.read(request['content-length'.freeze].to_i - request[:body].bytesize)
							return false unless packet
							request[:body] << packet
							request[:body_complete] = true if request['content-length'.freeze].to_i - request[:body].bytesize <= 0
						elsif request['content-type'.freeze]
							GReactor.warn 'Body type protocol error.' unless request[:body]
							line = data.gets
							return false unless line
							(request[:body] ||= '') << line
							request[:body_complete] = true if line =~ EOHEADERS
						else
							request[:body_complete] = true
						end
					end
					::GRHttp::HTTP2.handshake(request, @io, data) || dispatch(request, data) if request[:body_complete]
				end
				data.string.clear
			end

			def dispatch request, data
				return data.string.clear if @io.io.closed?
				io.write "HTTP/1.1 504 Version not Supported\r\nContent-Length: 41\r\n\r\nThis server only supports HTTP/2 for now."
				@request = ::GRHttp::Request.new(@io)
				return

				#check for server-responses
				case request.request[:method]
				when 'TRACE'.freeze
					request[:io].close
					return false
				when 'OPTIONS'.freeze
					response = ::GRHttp::Response.new request
					response[:Allow] = 'GET,HEAD,POST,PUT,DELETE,OPTIONS'.freeze
					response['access-control-allow-origin'.freeze] = '*'
					response['content-length'.freeze] = 0
					response.finish
					return false
				end

				response = ::GRHttp::Response.new request
				begin
					if request.websocket?
						WSHandler.http_handshake request, response, (io.params[:upgrade_handler] || NO_HANDLER).call(request, response) if WSHandler.is_valid_request?(request, response)
					else
						ret = (io.params[:http_handler] || NO_HANDLER).call(request, response)
						if ret.is_a?(String) && !response.finished?
							response << ret 
						elsif ret == false
							response.clear && (response.status = 404) && (response <<  ::GRHttp::Response::STATUS_CODES[404])
						end
						response.try_finish
					end							
				rescue => e
					GReactor.error e
					response = ::GRHttp::Response.new request, 500, {},  ::GRHttp::Response::STATUS_CODES[500]
					response.try_finish
				end
			end
			protected
			NO_HANDLER = Proc.new { |i,o| false }
			HTTP_METHODS = %w{GET HEAD POST PUT DELETE TRACE OPTIONS CONNECT PATCH}
			HTTP_METHODS_REGEXP = /\A#{HTTP_METHODS.join('|')}/i
		end

		def send_response response
			return false if response.heasers.frozen?

			headers = response.headers
			body = extract_body response

			headers['content-length'.freeze] ||= body.bytesize

			keep_alive = false
			if (request[:version].to_f > 1 && request['connection'.freeze].nil?) || request['connection'.freeze].to_s =~ /^k/i || (headers['connection'.freeze] && headers['connection'.freeze] =~ /^k/i)
				keep_alive = true
				out << "Connection: Keep-Alive\r\nKeep-Alive: timeout=#{(@io.timeout ||= 3).to_s}\r\n".freeze
			else
				headers['connection'.freeze] ||= 'close'.freeze
			end


			send_headers response
			send_data body
			close unless keep_alive
			log_finished response.request
		end
		def stream_response response, finish = false
			unless response.heasers.frozen?
				response['transfer-encoding'] = 'chunked'
				headers['connection'.freeze] ||= 'close'.freeze
				send_headers response
				@refuse_requests = true
			end
			body = extract_body response
			stream_data body if body || finish
			if finish
				stream_data '' unless body.nil?
			end
			true
		end

		protected

		def send_headers response
			return false if response.heasers.frozen?
			# remove old flash cookies
			response.cookies.keys.each do |k|
				if k.to_s.start_with? 'magic_flash_'.freeze
					response.set_cookie k, nil
					flash.delete k
				end
			end
			#set new flash cookies
			response.flash.each do |k,v|
				response.set_cookie "magic_flash_#{k.to_s}", v
			end
			response.cookies.freeze
			response.flash.freeze
			response['date'] ||= Time.now.httpdate

			request = response.request
			headers = response.headers


			out = "HTTP/#{request[:version]} #{response.status} #{STATUS_CODES[response.status] || 'unknown'}\r\n"

			# unless @headers['connection'] || (@request[:version].to_f <= 1 && (@request['connection'].nil? || !@request['connection'].match(/^k/i))) || (@request['connection'] && @request['connection'].match(/^c/i))
			headers.each {|k,v| out << "#{k.to_s}: #{v}\r\n"}
			out << "Cache-Control: max-age=0, no-cache\r\n".freeze unless @headers['cache-control'.freeze]
			response.raw_cookies.each {|k,v| out << "Set-Cookie: #{k.to_s}=#{v.to_s}\r\n"}
			out << "\r\n"

			@io[:bytes_sent] += @io.write(out)
			out.clear
			headers.freeze
			response.raw_cookies.feeze
		end
		def send_data data
			return if data.nil?
			@io[:bytes_sent] += @io.write(data)
		end
		def stream_data data = nil
			@io[:bytes_sent] += @io.write("#{data.bytesize.to_s(16)}\r\n#{data}\r\n")
		end
		def extract_body response
			if response.body.is_a?(String)
				return nil if response.body.empty? 
				response.body
			elsif body.is_a?(Array)
				return nil if response.body.empty? 
				response.body.join
			elsif response.body.nil?
				nil
			elsif response.body.respond_to? :each
				tmp = ''
				response.body.each {|s| tmp << s}
				response.body.close if response.body.respond_to? :close
				return nil if tmp.empty? 
				tmp
			end
		end

		def log_finished response
			t_n = Time.now
			request = response.request
			GReactor.log_raw("#{request[:client_ip]} [#{t_n.utc}] \"#{request[:method]} #{request[:original_path]} #{request[:scheme]}\/#{request[:version]}\" #{response.status} #{@io[:bytes_sent].to_s} #{((t_n - request[:time_recieved])*1000).round(2)}ms\n").clear # %0.3f
			@io[:bytes_sent] = 0
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

