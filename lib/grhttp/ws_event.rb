module GRHttp

	class WSEvent
		# the IO wrapper object used internally to send data. It's available for you mainly so that you could set data in the IO object's cache.
		attr_reader :io
		# The websocket's event data.
		attr_reader :data

		# The initializer is called by the GRHttp server, setting the websocket's event data and the IO used for sending websocket data.
		def initialize io, data = nil
			@io = io
			@data = data
		end

		# Returns the websocket connection's UUID, used for unicasting.
		def uuid
			io[:uuid] ||= SecureRandom.uuid
		end

		# Encodes data according to the websocket standard and sends the data over the websocket connection.
		def write data
			# should synchronize?
			# \@io.locker.synchronize { ... } 
			Base::WSHandler.send_data @io, data.to_s
		end
		alias :send :write
		alias :<< :write
		# Closes the websocket connection.
		def close
			@io.write( CLOSE_FRAME )
			@io.close
		end
		alias :disconnect :close
		# @return [true, false] returns true if the websocket connection is closed in both directions (calles the socket.closed? method).
		def closed?
			@io.io.closed?
		end
		# Sends a ping and returns he WSEvent object.
		def ping
			@io.write PING_FRAME
			self
		end
		# Sends a pong and returns he WSEvent object.
		def pong
			@io.write PONG_FRAME
			self
		end

		# Broadcasts data to ALL websocket connection _Handlers_ sharing the same process EXCEPT this websocket connection.
		#
		# A handler must implement the `#on_broadcast(data)` to accept broadcasts and unicasts.
		# The broadcast / unicast will be sent to the **handler** but NOT to the **client**.
		#
		# Accepts only ONE data object - usually a Hash, Array, String or a JSON formatted object.
		#
		# It is better to broadcast only data that would fit in a JSON string, as to allow easier multi-process / multi-machine scaling.
		#
		# For inter-process broadcasts/unicasts, use this method in conjuncture with a Pub/Sub service such as Redis.
		def broadcast data
			Base::WSHandler.broadcast data, self.io
		end

		# Broadcasts data to ONE websocket connection sharing the same process, as indicated by it's UUID.
		#
		# A handler must implement the `#on_broadcast(data)` to accept broadcasts and unicasts.
		# The broadcast / unicast will be sent to the **handler** but NOT to the **client**.
		#
		# Accepts:
		#
		# data:: ONE data object - usually a Hash, Array, String or a JSON formatted object.
		# uuid:: the websocket reciever's UUID.
		#
		# It is better to broadcast only data that would fit in a JSON string, as to allow easier multi-process / multi-machine scaling.
		#
		# For inter-process broadcasts/unicasts, use this method in conjuncture with a Pub/Sub service such as Redis.
		def unicast data, uuid
			Base::WSHandler.unicast data, uuid
		end

		# Starts auto-pinging every set interval (in seconds), until the websocket closes - this cannot be stopped once started.
		def autoping interval = 45
			AUTOPING_PROC.call self, interval
			true
		end

		# Starts auto-ponging every set interval (in seconds), until the websocket closes - this cannot be stopped once started.
		def autopong interval = 45
			AUTOPONG_PROC.call self, interval
			true
		end

		protected
		PONG_FRAME = "\x8A\x00".freeze
		PING_FRAME = "\x89\x00".freeze
		CLOSE_FRAME = "\x88\x00".freeze
		AUTOPING_PROC = Proc.new {|ws, i| GReactor.run_after i, ws.ping, i, &AUTOPING_PROC unless ws.closed?}
		AUTOPONG_PROC = Proc.new {|ws, i| GReactor.run_after i, ws.pong, i, &AUTOPONG_PROC unless ws.closed?}
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
