module GRHttp

	# Websocket client objects are members of this class.
	#
	# This is a VERY simple Websocket client. It doesn't support cookies, HTTP authentication or... well... anything, really.
	# It's just a simple client used for framework's testing. It's useful for simple WebSocket connections, but no more.
	class WSClient
		attr_accessor :response, :request

		def initialize request
			@response = nil
			@request = request
			params = request.io.params
			@on_message = params[:on_message]
			raise "Websocket client must have an #on_message Proc or handler." unless @on_message && @on_message.respond_to?(:call)
			@on_open = params[:on_open]
			@on_close = params[:on_close]
		end

		def on event_name, &block
			return false unless block
			case event_name
			when :message
				@on_message = block
			when :close
				@on_close = block
			when :open
				raise 'The on_open even is invalid at this point.'
			end
										
		end

		def on_message(ws = nil, &block)
			unless ws
				@on_message = block if block
				return @on_message
			end
			instance_exec( ws, &@on_message) 
		end

		def on_open(ws = nil, &block)
			unless ws
				raise 'The on_open even is invalid at this point.' if block
				# @on_open = block if block
				return @on_open
			end
			@response = ws
			instance_exec( ws, &@on_open) if @on_open
		end

		def on_close(ws = nil, &block)
			unless ws
				@on_close = block if block
				return @on_close
			end
			instance_exec( ws, &@on_close) if @on_close
		end

		# Sends data through the socket. a shortcut for ws_client.response <<
		#
		# @return [true, false] Returns the true if the data was actually sent or nil if no data was sent.
		def << data
			# raise 'Cannot send data when the connection is closed.' if closed?
			@response << data
		end
		alias :write :<<

		# closes the connection, if open
		def close
			@response.close if @response
		end

		# checks if the socket is open (if the websocket was terminated abnormally, this might returs true when it should be false).
		def closed?
			@response.io.io.closed?
		end

		# return the HTTP's handshake data, including any cookies sent by the server.
		def request
			@request
		end
		# return a Hash with the HTTP cookies recieved during the HTTP's handshake.
		def cookies
			@request.cookies
		end

		# Asynchronously connects to a websocket server.
		#
		# @return [true] this method always returns true or raises an exception if no block or :on_message handler were present (see the {WSClient.connect} method for more details).
		def self.async_connect url, options={}, &block
			GReactor.start unless GReactor.running?
			options[:on_message] ||= block
			raise "No #on_message handler defined! please pass a block or define an #on_message handler!" unless options[:on_message]
			GReactor.run_async { connect url, options }
			true
		end

		# Create a simple Websocket Client(!). This will implicitly start the IO reactor pattern.
		#
		# This method accepts two parameters:
		# url:: a String representing the URL of the websocket. i.e.: 'ws://foo.bar.com:80/ws/path'
		# options:: a Hash with options to be used. The options will be used to define the connection's details (i.e. ssl etc') and the Websocket callbacks (i.e. on_open(ws), on_close(ws), on_message(ws))
		# &block:: an optional block that accepts one parameter (data) and will be used as the `#on_message(data)`
		#
		# Acceptable options are:
		# on_open:: the on_open callback. Must be an objects that answers `call(ws)`, usually a Proc.
		# on_message:: the on_message callback. Must be an objects that answers `call(ws)`, usually a Proc.
		# on_close:: the on_close callback. Must be an objects that answers `call(ws)`, usually a Proc.
		# headers:: a Hash of custom HTTP headers to be sent with the request. Header data, including cookie headers, should be correctly encoded.
		# cookies:: a Hash of cookies to be sent with the request. cookie data will be encoded before being sent.
		# timeout:: the number of seconds to wait before the connection is established. Defaults to 5 seconds.
		#
		# The method will block until the connection is established or until 5 seconds have passed (the timeout). The method will either return a WebsocketClient instance object or raise an exception it the connection was unsuccessful.
		#
		# An on_message Proc must be defined, or the method will fail.
		#
		# The on_message Proc can be defined using the optional block:
		#
		#      WebsocketClient.connect_to("ws://localhost:3000/") {|data| response << data} #echo example
		#
		# OR, the on_message Proc can be defined using the options Hash: 
		#
		#      WebsocketClient.connect_to("ws://localhost:3000/", on_open: -> {}, on_message: -> {|data| response << data})
		#
		# The #on_message(data), #on_open and #on_close methods will be executed within the context of the WebsocketClient
		# object, and will have natice acess to the Websocket response object.
		#
		# After the WebsocketClient had been created, it's possible to update the #on_message and #on_close methods:
		#
		#      # updates #on_message
		#      wsclient.on_message do |data|
		#           response << "I'll disconnect on the next message!"
		#           # updates #on_message again.
		#           on_message {|data| disconnect }
		#      end
		#
		#
		# !!please be aware that the Websockt Client will not attempt to verify SSL certificates,
		# so that even SSL connections are subject to a possible man in the middle attack.
		#
		# @return [GRHttp::WSClient] this method returns the connected {GRHttp::WSClient} or raises an exception if something went wrong (such as a connection timeout).
		def self.connect url, options={}, &block
			GReactor.start unless GReactor.running?
			socket = nil
			options[:on_message] ||= block
			options[:reactor] = ::GReactor
			raise "No #on_message handler defined! please pass a block or define an #on_message handler!" unless options[:on_message]
			options[:handler] = GRHttp::Base::WSHandler
			url = URI.parse(url) unless url.is_a?(URI)

			connection_type = GReactor::BasicIO
			if url.scheme == "https" || url.scheme == "wss"
				connection_type = GReactor::SSLBasicIO
				options[:ssl_client] = true
				url.port ||= 443
			end
			url.port ||= 80
			url.path = '/' if url.path.to_s.empty?
			socket = TCPSocket.new(url.host, url.port)
			io = options[:io] = connection_type.new(socket, options)
			io.locker.synchronize do

				# prep custom headers
				custom_headers = ''
				custom_headers = options[:headers] if options[:headers].is_a?(String)
				options[:headers].each {|k, v| custom_headers << "#{k.to_s}: #{v.to_s}\r\n"} if options[:headers].is_a?(Hash)
				options[:cookies].each {|k, v| raise 'Illegal cookie name' if k.to_s.match(/[\x00-\x20\(\)<>@,;:\\\"\/\[\]\?\=\{\}\s]/); custom_headers << "Cookie: #{ k }=#{ HTTP.encode_url v }\r\n"} if options[:cookies].is_a?(Hash)

				# send protocol upgrade request
				websocket_key = [(Array.new(16) {rand 255} .pack 'c*' )].pack('m0*')
				io.write "GET #{url.path}#{url.query.to_s.empty? ? '' : ('?' + url.query)} HTTP/1.1\r\nHost: #{url.host}#{url.port ? (':'+url.port.to_s) : ''}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nOrigin: #{options[:ssl_client] ? 'https' : 'http'}://#{url.host}\r\nSec-WebSocket-Key: #{websocket_key}\r\nSec-WebSocket-Version: 13\r\n#{custom_headers}\r\n"
				# wait for answer - make sure we don't over-read
				# (a websocket message might be sent immidiately after connection is established)
				reply = ''
				reply.force_encoding(::Encoding::ASCII_8BIT)
				stop_time = Time.now + (options[:timeout] || 5)
				stop_reply = "\r\n\r\n"
				sleep 0.2
				until reply[-4..-1] == stop_reply
					add = io.read(1)
					add ? (reply << add) : (sleep 0.2)
					raise "connections was closed" if io.io.closed?
					raise "Websocket client handshake timed out (HTTP reply not recieved)\n\n Got Only: #{reply}" if Time.now >= stop_time
				end
				# review reply
				raise "Connection Refused. Reply was:\r\n #{reply}" unless reply.lines[0].match(/^HTTP\/[\d\.]+ 101/i)
				raise 'Websocket Key Authentication failed.' unless reply.match(/^Sec-WebSocket-Accept:[\s]*([^\s]*)/i) && reply.match(/^Sec-WebSocket-Accept:[\s]*([^\s]*)/i)[1] == Digest::SHA1.base64digest(websocket_key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11')
				# read the body's data and parse any incoming data.
				request = io[:request] ||= HTTPRequest.new(io)
				request[:method] = 'GET'
				request['host'] = "#{url.host}:#{url.port}"
				request[:query] = url.path
				request[:version] = 'HTTP/1.1'
				# reply.gsub! /set-cookie/i, 'Cookie'
				reply = StringIO.new reply
				reply.gets
				HTTP._parse_http io, reply

				# set-up handler response object. 
				io[:ws_extentions] = [].freeze
				(io[:websocket_handler] = WSClient.new request).on_open(WSEvent.new(io, nil))
			end
			return io[:websocket_handler]
			rescue => e
				io ? io.close : (socket ? socket.close : nil )
				raise e
		end
		class << self
			alias :connect_to :connect
		end
	end
end


######
## example requests

# GET /nickname HTTP/1.1
# Upgrade: websocket
# Connection: Upgrade
# Host: localhost:3000
# Origin: https://www.websocket.org
# Cookie: test=my%20cookies; user_token=2INa32_vDgx8Aa1qe43oILELpSdIe9xwmT8GTWjkS-w
# Pragma: no-cache
# Cache-Control: no-cache
# Sec-WebSocket-Key: 1W9B64oYSpyRL/yuc4k+Ww==
# Sec-WebSocket-Version: 13
# Sec-WebSocket-Extensions: x-webkit-deflate-frame
# User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10) AppleWebKit/600.1.25 (KHTML, like Gecko) Version/8.0 Safari/600.1.25