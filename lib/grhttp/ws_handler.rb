module GRHttp


	module Base
		# The GReactor's[https://github.com/boazsegev/GReactor] WebSocket handler used by the GRHttp server.
		module WSHandler

			module_function

			# This method is called by the reactor.
			# By default, this method reads the data from the IO and calls the `#on_message data` method.
			#
			# This method is called within a lock on the connection (Mutex) - craeful from double locking.
			def call io
				extract_message io, io.read.to_s.bytes
			end
			# This method is called by the reactor.
			# By default, this method reads the data from the IO and calls the `#on_message data` method.
			def on_disconnect io
				h = io[:websocket_handler]
				h.on_close(WSEvent.new(io, nil)) if h.respond_to? :on_close
			end

			# Sets the message byte size limit for a Websocket message. Defaults to 0 (no limit)
			#
			# Although memory will be allocated for the latest TCP/IP frame,
			# this allows the websocket to disconnect if the incoming expected message size exceeds the allowed maximum size.
			#
			# If the sessage size limit is exceeded, the disconnection will be immidiate as an attack will be assumed. The protocol's normal disconnect sequesnce will be discarded.
			def message_size_limit=val
				@message_size_limit = val
			end
			# Gets the message byte size limit for a Websocket message. Defaults to 0 (no limit)
			def message_size_limit
				@message_size_limit
			end

			# perform the HTTP handshake for WebSockets. send a 400 Bad Request error if handshake fails.
			def http_handshake request, response, handler
				# review handshake (version, extentions)
				# should consider adopting the websocket gem for handshake and framing:
				# https://github.com/imanel/websocket-ruby
				# http://www.rubydoc.info/github/imanel/websocket-ruby
				return refuse response unless handler
				io = request[:io]
				io[:keep_alive] = true
				response.status = 101
				response['upgrade'] = 'websocket'
				response['content-length'] = '0'
				response['connection'] = 'Upgrade'
				response['sec-websocket-version'] = '13'
				# Note that the client is only offering to use any advertised extensions
				# and MUST NOT use them unless the server indicates that it wishes to use the extension.
				io[:ws_extentions] = []
				request['sec-websocket-extensions'].to_s.split(/[\s]*[,][\s]*/).each {|ex| ex = ex.split(/[\s]*;[\s]*/); io[:ws_extentions] << ex if SUPPORTED_EXTENTIONS[ ex[0] ]}
				response['sec-websocket-extensions'] = io[:ws_extentions].map {|e| e[0] } .join (',')
				response.headers.delete 'sec-websocket-extensions' if response['sec-websocket-extensions'].empty?
				response['Sec-WebSocket-Accept'] = Digest::SHA1.base64digest(request['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11')
				response.finish
				# GReactor.log_raw "#{@request[:client_ip]} [#{Time.now.utc}] - #{@connection.object_id} Upgraded HTTP to WebSockets.\n"
				request.cookies.set_response nil
				io[:ws_parser] = {body: [], stage: 0, step: 0, message: ''}
				io[:ws_extentions].freeze
				io[:websocket_handler] = handler
				io.params[:handler] = self
				io.timeout = 60
				handler.on_open(WSEvent.new(io, nil)) if handler.respond_to? :on_open
				return true
			end

			def is_valid_request? request, response
				return true if request['upgrade'].to_s.downcase == 'websocket' && 
										request['sec-websocket-key'] &&
										request['connection'].to_s.downcase == 'upgrade' &&
										# (request['sec-websocket-extensions'].split(/[\s]*[,][\s]*/).reject {|ex| ex == '' || SUPPORTED_EXTENTIONS[ex.split(/[\s]*;[\s]*/)[0]] } ).empty? &&
										(request['sec-websocket-version'].to_s.downcase.split(/[, ]/).map {|s| s.strip} .include?( '13' ))

				refuse response
			end

			# Formats the data as one or more WebSocket frames.
			def frame_data io, data, op_code = nil, fin = true
				# set up variables
				frame = ''.force_encoding('binary')
				op_code ||= (data.encoding.name == 'UTF-8' ? 1 : 2)


				if data[FRAME_SIZE_LIMIT] && fin
					# fragment big data chuncks into smaller frames - op-code reset for 0 for all future frames.
					data = data.dup
					data.force_encoding('binary')
					[frame << frame_data(io, data.slice!(0...FRAME_SIZE_LIMIT), op_code, false), op_code = 0] while data.length > FRAME_SIZE_LIMIT # 1048576
					# frame << frame_data(io, data.slice!(0..1048576), op_code, false)
					# data = 
					# op_code = 0
				end

				# apply extenetions to the frame
				ext = 0
				# # ext |= call each io.protocol.extenetions with data #changes data and returns flags to be set
				# io[:ws_extentions].each { |ex| ext |= WSProtocol::SUPPORTED_EXTENTIONS[ex[0]][2].call data, ex[1..-1]}

				# set 
				frame << ( (fin ? 0b10000000 : 0) | (op_code & 0b00001111) | ext).chr

				if data.length < 125
					frame << data.length.chr
				elsif data.length.bit_length <= 16					
					frame << 126.chr
					frame << [data.length].pack('S>')
				else
					frame << 127.chr
					frame << [data.length].pack('Q>')
				end
				frame.force_encoding(data.encoding)
				frame << data
				frame.force_encoding('binary')
				frame
			end

			def close_frame
				CLOSE_FRAME
			end

			# Broadcasts data to ALL the websocket connections EXCEPT the once specified (if specified).
			#
			# Data broadcasted will be recived by the websocket handler it's #on_broadcast(ws) method (if exists).
			#
			# Accepts:
			#
			# data:: One object of data. Usually a Hash, Array, String or a JSON formatted object.
			# ignore_io (optional):: The IO to be ignored by the broadcast. Usually the broadcaster's IO.
			# 
			def broadcast data, ignore_io = nil
				if ignore_io
					ig_id = ignore_io.object_id
					GReactor.each {|io| h = io[:websocket_handler]; h.on_broadcast WSEvent.new(io, data) if h && io.object_id != ig_id && h.respond_to?(:on_broadcast)}
				else
					GReactor.each {|io| h = io[:websocket_handler]; h.on_broadcast WSEvent.new(io, data) if h && h.respond_to?(:on_broadcast)}
				end
				true
			end

			# Unicast data to a specific websocket connection (ONLY the connection specified).
			#
			# Data broadcasted will be recived by the websocket handler it's #on_broadcast(ws) method (if exists).
			# Accepts:
			# 
			def unicast uuid, data
				return false unless uuid
				GReactor.each {|io| next unless io[:uuid] == uuid; h = io[:websocket_handler]; h.on_broadcast WSEvent.new(io, data) if h && h.respond_to?(:on_broadcast); break}
				true
			end

			protected
			FRAME_SIZE_LIMIT = 131_072
			SUPPORTED_EXTENTIONS = {}
			CLOSE_FRAME = "\x88\x00".freeze
			message_size_limit = 0

			def self.refuse response
				response.status = 400
				response['sec-websocket-extensions'] = SUPPORTED_EXTENTIONS.keys.join(', ')
				response['sec-websocket-version'] = '13'
				response.finish
				false
			end

			# parse the message and send it to the handler
			#
			# test: frame = ["819249fcd3810b93b2fb69afb6e62c8af3e83adc94ee2ddd"].pack("H*").bytes; parser[:stage] = 0; parser = {}
			# accepts:
			# frame:: an array of bytes
			def self.extract_message io, data
				parser = io[:ws_parser] ||= {}
				until data.empty?
						if parser[:stage] == 0 && !data.empty?
						parser[:fin] = data[0][7] == 1
						parser[:rsv1] = data[0][6] == 1
						parser[:rsv2] = data[0][5] == 1
						parser[:rsv3] = data[0][4] == 1
						parser[:op_code] = data[0] & 0b00001111
						parser[:p_op_code] ||= data[0] & 0b00001111
						parser[:stage] += 1
						data.shift
					end
					if parser[:stage] == 1
						parser[:mask] = data[0][7]
						parser[:len] = data[0] & 0b01111111
						data.shift
						if parser[:len] == 126
							parser[:len] = merge_bytes( *(data.slice!(0,2)) ) # should be = ?
						elsif parser[:len] == 127
							# len = 0
							parser[:len] = merge_bytes( *(data.slice!(0,8)) ) # should be = ?
						end
						parser[:step] = 0
						parser[:stage] += 1
						review_message_size io, parser
					end
					if parser[:stage] == 2 && parser[:mask] == 1
						parser[:mask_key] = data.slice!(0,4)
						parser[:stage] += 1
					elsif  parser[:mask] != 1
						parser[:stage] += 1
					end
					if parser[:stage] == 3 && parser[:step] < parser[:len]
						# data.length.times {|i| data[0] = data[0] ^ parser[:mask_key][parser[:step] % 4] if parser[:mask_key]; parser[:step] += 1; parser[:body] << data.shift; break if parser[:step] == parser[:len]}
						slice_length = [data.length, (parser[:len]-parser[:step])].min
						if parser[:mask_key]
							masked = data.slice!(0, slice_length)
							masked.map!.with_index {|b, i|  b ^ parser[:mask_key][ ( i + parser[:step] ) % 4]  }
							parser[:body].concat masked
						else
							parser[:body].concat data.slice!(0, slice_length)
						end
						parser[:step] += slice_length
					end
					complete_frame io unless parser[:step] < parser[:len]
				end
				true
			end

			# takes and Array of bytes and combines them to an int(16 Bit), 32Bit or 64Bit number
			def self.merge_bytes *bytes
				return bytes.pop if bytes.length == 1
				bytes.pop ^ (merge_bytes(*bytes) << 8)
			end

			# The proc queued whenever a frame is complete.
			COMPLETE_FRAME_PROC = Proc.new {|h, e| h.on_message e}

			# handles the completed frame and sends a message to the handler once all the data has arrived.
			def self.complete_frame io
				parser = io[:ws_parser]
				io[:ws_extentions].each {|ex| SUPPORTED_EXTENTIONS[ex[0]][1].call(parser[:body], ex[1..-1]) if SUPPORTED_EXTENTIONS[ex[0]]}

				case parser[:op_code]
				when 9 # ping
					# handle parser[:op_code] == 9 (ping)
					GReactor.callback io, :send, frame_data(io, parser[:body].pack('C*'), 10)
					parser[:p_op_code] = nil if parser[:p_op_code] == 9
				when 10 #pong
					# handle parser[:op_code] == 10 (pong)
					parser[:p_op_code] = nil if parser[:p_op_code] == 10
				when 8 # close
					# handle parser[:op_code] == 8 (close)
					io.send( CLOSE_FRAME )
					io.close
					parser[:p_op_code] = nil if parser[:p_op_code] == 8
				else
					parser[:message] << parser[:body].pack('C*')
					# handle parser[:op_code] == 0 / fin == false (continue a frame that hasn't ended yet)
					if parser[:fin]
						HTTP.make_utf8! parser[:message] if parser[:p_op_code] == 1
						GReactor.queue [io[:websocket_handler], WSEvent.new(io, parser[:message])], COMPLETE_FRAME_PROC
						parser[:message] = ''
						parser[:p_op_code] = nil
					end
				end
				parser[:stage] = 0
				parser[:body].clear
				parser[:step] = 0
				parser[:p_op_code] = nil
			end
			#reviews the message size and closes the connection if expected message size is over the allowed limit.
			def self.review_message_size io, parser
				if ( @message_size_limit.to_i > 0 ) && ( ( parser[:len] + parser[:message].bytesize ) > @message_size_limit.to_i )
					io.close
					parser[:message].clear
					parser[:step] = 0
					parser[:body].clear
					parser = -1
					GReactor.warn "Websocket message above limit's set - closing connection."
					return false
				end
				true
			end

		end
	end

	# Sets the message byte size limit for a Websocket message. Defaults to 0 (no limit)
	#
	# Although memory will be allocated for the latest TCP/IP frame,
	# this allows the websocket to disconnect if the incoming expected message size exceeds the allowed maximum size.
	#
	# If the sessage size limit is exceeded, the disconnection will be immidiate as an attack will be assumed. The protocol's normal disconnect sequesnce will be discarded.
	def self.ws_message_size_limit=val
		Base::WSHandler.message_size_limit = val
	end
	# Gets the message byte size limit for a Websocket message. Defaults to 0 (no limit)
	def self.ws_message_size_limit
		Base::WSHandler.message_size_limit
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
