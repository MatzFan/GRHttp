require 'stringio'
module GRHttp

	class WSEvent
		attr_reader :io, :data

		def initialize io, data = nil
			@io = io
			@data = data
		end

		# Encodes data according to the websocket standard and sends the data over the websocket connection.
		def write data
			# should synchronize?
			# @io.locker.synchronize { ... } 
			@io.send Base::WSHandler.frame_data(@io, data.to_s) if data
		end
		alias :send :write
		alias :<< :write
		# Closes the websocket connection.
		def close
			@io.send( CLOSE_FRAME )
			@io.close
		end
		alias :disconnect :close
		# @return [true, false] returns true if the websocket connection is closed.
		def closed?
			@io.closed?
		end
		# Sends a ping and returns he WSEvent object.
		def ping
			@io.send( PING_FRAME )
			self
		end
		# Sends a pong and returns he WSEvent object.
		def pong
			@io.send( PONG_FRAME )
			self
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
		AUTOPING_PROC = Proc.new {|ws, i| GReactor.run_every i, 1, ws.ping, i, &AUTOPING_PROC unless ws.closed?}
		AUTOPONG_PROC = Proc.new {|ws, i| GReactor.run_every i, 1, ws.pong, i, &AUTOPONG_PROC unless ws.closed?}
		PING_PROC = Proc.new {|res| EventMachine.timed_job ping_interval, 1, [res.ping], PING_PROC unless res.service.disconnected? || !ping_interval }
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
