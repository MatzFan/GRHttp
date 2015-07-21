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
			raise "Websocket client must have an #on_message Proc." unless @on_message && @on_message.is_a?(Proc)
			@on_open = params[:on_open]
			@on_close = params[:on_close]
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
				@on_open = block if block
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

		# sends data through the socket. a shortcut for ws_client.response <<
		def << data
			@response << data
		end

		# closes the connection, if open
		def close
			@response.close if @response
		end

		# Create a simple Websocket Client(!)
		#
		# This method accepts two parameters:
		# url:: a String representing the URL of the websocket. i.e.: 'ws://foo.bar.com:80/ws/path'
		# options:: a Hash with options to be used. The options will be used to define
		# &block:: an optional block that accepts one parameter (data) and will be used as the `#on_message(data)`
		#
		# The method will either return a WebsocketClient instance object or it will raise an exception.
		#
		# An on_message Proc must be defined, or the method will fail.
		#
		# The on_message Proc can be defined using the optional block:
		#
		#      WebsocketClient.connect_to("ws://localhost:3000/") {|data| response << data} #echo example
		#
		# OR, the on_message Proc can be defined using the options Hash: 
		#
		#      WebsocketClient.connect_to("ws://localhost:3000/", on_connect: -> {}, on_message: -> {|data| response << data})
		#
		# The #on_message(data), #on_connect and #on_disconnect methods will be executed within the context of the WebsocketClient
		# object, and will have natice acess to the Websocket response object.
		#
		# After the WebsocketClient had been created, it's possible to update the #on_message and #on_disconnect methods:
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
		def self.connect_to url, options={}, &block
			socket = nil
			options[:on_message] ||= block
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

			# send protocol upgrade request
			websocket_key = [(Array.new(16) {rand 255} .pack 'c*' )].pack('m0*')
			io.write "GET #{url.path}#{url.query.to_s.empty? ? '' : ('?' + url.query)} HTTP/1.1\r\nHost: #{url.host}#{url.port ? (':'+url.port.to_s) : ''}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nOrigin: #{options[:ssl_client] ? 'https' : 'http'}://#{url.host}\r\nSec-WebSocket-Key: #{websocket_key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
			# wait for answer - make sure we don't over-read
			# (a websocket message might be sent immidiately after connection is established)
			reply = ''
			reply.force_encoding('binary')
			start_time = Time.now
			stop_reply = "\r\n\r\n"
			sleep 0.2
			until reply[-4..-1] == stop_reply
				add = io.read(1)
				add ? (reply << add) : (sleep 0.2)
				raise "connections was closed" if io.io.closed?
				raise "Websocket client handshake timed out (HTTP reply not recieved)\n\n Got Only: #{reply}" if Time.now >= (start_time + 5)
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
			(io[:websocket_handler] = WSClient.new io[:request]).on_open(WSEvent.new(io, nil))
			# add the socket to the EventMachine IO reactor
			GReactor.add_raw_io io.io, io
			return io[:websocket_handler]
			rescue => e
				socket.close if socket
				raise e
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