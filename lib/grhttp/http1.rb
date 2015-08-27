module GRHttp

	module Base

		# Legacy HTTP 1 protocol, and protocol upgrade layer (HTTP/2 / Websockets).
		class HTTP < ::GReactor::Protocol
			def on_open
				return switch_protocol(::GRHttp::HTTP2.new @io) if @io.ssl? && @io.ssl_socket.npn_protocol == 'h2'
				@refuse_requests = false
				@io[:bytes_sent] = 0
			end

			def on_message data
				return if @refuse_requests
				data = ::StringIO.new data
				until data.eof?
					request = (@request ||= ::GRHttp::Request.new(@io))
					unless request[:method]
						l = data.gets.strip
						next if l.empty?
						request[:method], request[:query], request[:version] = l.split(/[\s]+/, 3)
						return (GReactor.warn('Protocol Error, closing connection.') && close) unless request[:method] =~ HTTP_METHODS_REGEXP
						request[:time_recieved] = Time.now
					end
					until request[:headers_complete] || (l = data.gets).nil?
						if l.include? ':'
							l = l.strip.split(/:[\s]?/, 2)
							l[0].strip! ; l[0].downcase!;
							request[l[0]] ? (request[l[0]].is_a?(Array) ? (request[l[0]] << l[1]) : request[l[0]] = [request[l[0]], l[1] ]) : (request[l[0]] = l[1])
						elsif l =~ /^[\r]?\n/
							request[:headers_complete] = true
						else
							#protocol error
							GReactor.warn 'Protocol Error, closing connection.'
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
								return (GReactor.warn('Protocol Error, closing connection.') && close) unless io[:length]
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
							Base.parse_request request
						end
					end
					(@request = ::GRHttp::Request.new(@io)) && ( ::GRHttp::HTTP2.handshake(request, @io, data) || dispatch(request, data) ) if request[:body_complete]
				end
				data.string.clear
			end

			def dispatch request, data
				return data.string.clear if @io.io.closed? || @refuse_requests

				#check for server-responses
				case request[:method]
				when 'TRACE'.freeze
					close
					data.string.clear
					return false
				when 'OPTIONS'.freeze
					response = ::GRHttp::Response.new request
					response[:Allow] = 'GET,HEAD,POST,PUT,DELETE,OPTIONS'.freeze
					response['access-control-allow-origin'.freeze] = '*'
					response['content-length'.freeze] = 0
					send_response response
					return false
				end
				response = ::GRHttp::Response.new request
				begin
					if request.websocket?
						@refuse_requests = true
						WSHandler.http_handshake request, response, (@params[:upgrade_handler] || NO_HANDLER).call(request, response)
					else
						ret = (@params[:http_handler] || NO_HANDLER).call(request, response)
						if ret.is_a?(String)
							response << ret
						elsif ret == false
							response.clear && (response.status = 404) && (response <<  ::GRHttp::Response::STATUS_CODES[404])
						end
					end
					send_response response
				rescue => e
					GReactor.error e
					send_response ::GRHttp::Response.new(request, 500, {},  ::GRHttp::Response::STATUS_CODES[500])
				end
			end

			def send_response response
				return false if response.headers.frozen?

				request = response.request
				headers = response.headers
				body = extract_body response.body

				headers['content-length'.freeze] ||= body.to_s.bytesize

				keep_alive = io[:keep_alive]
				if (request[:version].to_f > 1 && request['connection'.freeze].nil?) || request['connection'.freeze].to_s =~ /ke/i || (headers['connection'.freeze] && headers['connection'.freeze] =~ /^ke/i)
					keep_alive = true
					headers['connection'.freeze] ||= 'Keep-Alive'.freeze
					headers['keep-alive'.freeze] ||= "timeout=#{(@io.timeout ||= 3).to_s}"
				else
					headers['connection'.freeze] ||= 'close'.freeze
				end

				send_headers response
				return if request.head?
				response.bytes_written += (@io.write(body) || 0) if body
				close unless keep_alive
				log_finished response
			end
			def stream_response response, finish = false
				unless response.headers.frozen?
					response['transfer-encoding'] = 'chunked'
					response.headers['connection'.freeze] = 'close'.freeze
					send_headers response
					@refuse_requests = true
				end
				return if response.request.head?
				body = extract_body response.body
				response.body = nil
				response.bytes_written += stream_data(body) if body || finish
				if finish
					response.bytes_written += stream_data('') unless body.nil?
					log_finished response
				end
				true
			end

			protected
			NO_HANDLER = Proc.new { |i,o| false }
			HTTP_METHODS = %w{GET HEAD POST PUT DELETE TRACE OPTIONS CONNECT PATCH}
			HTTP_METHODS_REGEXP = /\A#{HTTP_METHODS.join('|')}/i

			def send_headers response
				return false if response.headers.frozen?
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
				response.raw_cookies.freeze
				# response.cookies.set_response nil
				response.flash.freeze

				request = response.request
				headers = response.headers

				# response['date'.freeze] ||= request[:time_recieved].httpdate

				out = "HTTP/#{request[:version]} #{response.status} #{::GRHttp::Response::STATUS_CODES[response.status] || 'unknown'}\r\n"

				out << request[:time_recieved].utc.strftime("Date: %a, %d %b %Y %H:%M:%S GMT\r\n".freeze) unless headers['date'.freeze]

				# unless @headers['connection'] || (@request[:version].to_f <= 1 && (@request['connection'].nil? || !@request['connection'].match(/^k/i))) || (@request['connection'] && @request['connection'].match(/^c/i))
				headers.each {|k,v| out << "#{k.to_s}: #{v}\r\n"}
				out << "Cache-Control: max-age=0, no-cache\r\n".freeze unless headers['cache-control'.freeze]
				response.raw_cookies.each {|k,v| out << "Set-Cookie: #{k.to_s}=#{v.to_s}\r\n"}
				out << "\r\n"

				response.bytes_written += (@io.write(out) || 0)
				out.clear
				headers.freeze
				response.raw_cookies.freeze
			end
			def stream_data data = nil
				 @io.write("#{data.to_s.bytesize.to_s(16)}\r\n#{data.to_s}\r\n") || 0
			end
			def extract_body body
				if body.is_a?(Array)
					return nil if body.empty?
					extract_body body.join
				elsif body.is_a?(String)
					return nil if body.empty? 
					body
				elsif body.nil?
					nil
				elsif body.respond_to? :each
					tmp = ''
					body.each {|s| tmp << s}
					body.close if body.respond_to? :close
					return nil if tmp.empty? 
					tmp
				end
			end

			def log_finished response
				@io[:bytes_sent] = 0
				request = response.request
				return if GReactor.logger.nil? || request[:no_log]
				t_n = Time.now
				GReactor.log_raw("#{request[:client_ip]} [#{t_n.utc}] \"#{request[:method]} #{request[:original_path]} #{request[:scheme]}\/#{request[:version]}\" #{response.status} #{response.bytes_written.to_s} #{((t_n - request[:time_recieved])*1000).round(2)}ms\n").clear
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

