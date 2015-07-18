require 'stringio'
module GRHttp

	# This module and it's members are used internally and AREN'T part of the public API.
	#
	module Base
		# The GReactor's[https://github.com/boazsegev/GReactor] HTTP handler used by the GRHttp.
		module HTTPHandler
			extend HTTP

			module_function

			# This method is called by the reactor.
			# By default, this method reads the data from the IO and calls the `#on_message data` method.
			#
			# This method is called within a lock on the connection (Mutex) - craeful from double locking.
			def call io
				data = StringIO.new io.read.to_s
				until data.eof?
					if HTTP._parse_http io, data
						request = io[:request]; io[:request] = nil
						response = HTTPResponse.new request
						break if io.io.closed?
						if request.upgrade?
							WSHandler.http_handshake request, response, (io.params[:upgrade_handler] || NO_HANDLER).call(request, response) if WSHandler.is_valid_request?(request, response)
						else
							ret = (io.params[:http_handler] || NO_HANDLER).call(request, response)
							if ret.is_a?(String) && !response.finished?
								response << ret 
							elsif ret == false
								response.clear && (response.status = 404) && (response << HTTPResponse::STATUS_CODES[404])
							end
							response.try_finish
						end
					end
				end
			end

			protected
			NO_HANDLER = Proc.new { |i,o| false }

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
