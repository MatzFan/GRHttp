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
				extract_message io, a = StringIO.new(io.read.to_s)
				a.string.clear
				a.close

			end
			# This method is called by the reactor after the connection is closed.
			def on_close io
				h = io[:websocket_handler]
				h.on_close(WSEvent.new(io, nil)) if h.respond_to? :on_close
				if io[:ws_extentions]
					io[:ws_extentions].each { |ex| ex.close }
					io[:ws_extentions] = nil
				end
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
				return refuse response unless handler || handler == true
				io = request[:io]
				io[:keep_alive] = true
				response.status = 101
				response['upgrade'.freeze] = 'websocket'.freeze
				response['content-length'.freeze] = '0'.freeze
				response['connection'.freeze] = 'Upgrade'.freeze
				response['sec-websocket-version'.freeze] = '13'.freeze
				# Note that the client is only offering to use any advertised extensions
				# and MUST NOT use them unless the server indicates that it wishes to use the extension.
				io[:ws_extentions] = []
				ext = []
				request['sec-websocket-extensions'.freeze].to_s.split(/[\s]*[,][\s]*/).each {|ex| ex = ex.split(/[\s]*;[\s]*/); ( ( tmp = SUPPORTED_EXTENTIONS[ ex[0] ].call(ex[1..-1]) ) && (io[:ws_extentions] << tmp) && (ext << tmp.name) ) if SUPPORTED_EXTENTIONS[ ex[0] ] }
				ext.compact!
				response['sec-websocket-extensions'.freeze] = ext.join(', ') if ext.any?
				response['Sec-WebSocket-Accept'.freeze] = Digest::SHA1.base64digest(request['sec-websocket-key'.freeze] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'.freeze)
				# GReactor.log_raw "#{@request[:client_ip]} [#{Time.now.utc}] - #{@connection.object_id} Upgraded HTTP to WebSockets.\n"
				# request.io.params[:handler].send_response response 
				response.finish
				io[:ws_parser] = parser_hash
				io[:ws_extentions].freeze
				io[:websocket_handler] = handler
				io.params[:handler] = self
				io.timeout = 60
				handler.on_open(WSEvent.new(io, nil)) if handler.respond_to? :on_open
				return true
			end

			# sends the data as one (or more) Websocket frames
			def send_data io, data, op_code = nil, fin = true, ext = 0
				return false if !data || data.empty?
				return false if io.nil? || io.closed?
				data = data.dup
				unless op_code # apply extenetions to the message as a whole
					op_code = (data.encoding == ::Encoding::UTF_8 ? 1 : 2) 
					io[:ws_extentions].each { |ex| ext |= ex.edit_message data } if io[:ws_extentions]
				end
				byte_size = data.bytesize
				if byte_size > (FRAME_SIZE_LIMIT+2)
					sections = byte_size/FRAME_SIZE_LIMIT + (byte_size%FRAME_SIZE_LIMIT ? 1 : 0)
					send_data( io, data.slice!( 0...FRAME_SIZE_LIMIT ), op_code, data.empty?, ext) && (ext = op_code = 0) until data.empty?
					# sections.times { |i| send_data io, data.slice!( 0...FRAME_SIZE_LIMIT ), op_code, (i==sections) }
				end
				# # ext |= call each io.protocol.extenetions with data #changes data and returns flags to be set
				io[:ws_extentions].each { |ex| ext |= ex.edit_frame data } if io[:ws_extentions]
				header = ( (fin ? 0b10000000 : 0) | (op_code & 0b00001111) | ext).chr.force_encoding(::Encoding::ASCII_8BIT)

				if byte_size < 125
					header << byte_size.chr
				elsif byte_size.bit_length <= 16					
					header << 126.chr
					header << [byte_size].pack('S>'.freeze)
				else
					header << 127.chr
					header << [byte_size].pack('Q>'.freeze)
				end
				io.write header
				io.write(data) && true
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
					GReactor.each {|io| next unless io.is_a?(::GReactor::BasicIO); GReactor.queue DO_BROADCAST_PROC, [io, data] unless io.object_id == ig_id}
				else
					GReactor.each {|io| next unless io.is_a?(::GReactor::BasicIO); GReactor.queue DO_BROADCAST_PROC, [io, data] }
				end
				true
			end

			# Unicast data to a specific websocket connection (ONLY the connection specified).
			#
			# Data broadcasted will be recived by the websocket handler it's #on_broadcast(ws) method (if exists).
			# Accepts:
			# uuid:: the UUID of the websocket connection recipient.
			# data:: the data to be sent.
			#
			# @return [true, false] Returns true if the object was found and the unicast was sent (the task will be executed asynchronously once the unicast was sent).
			def unicast uuid, data
				return false unless uuid && data
				GReactor.each {|io| next unless io.is_a?(::GReactor::BasicIO) && io[:uuid] == uuid; GReactor.queue DO_BROADCAST_PROC, [io, data]; return true}
				false
			end

			protected
			FRAME_SIZE_LIMIT = 17_895_697
			SUPPORTED_EXTENTIONS = {}
			CLOSE_FRAME = "\x88\x00".freeze
			message_size_limit = 0
			DO_BROADCAST_PROC = Proc.new {|io, data|  h = io[:websocket_handler]; h.on_broadcast WSEvent.new(io, data) if h && h.respond_to?(:on_broadcast)}
			def self.parser_hash
				{body: '', stage: 0, step: 0, mask_key: [], len_bytes: []}
			end

			def self.refuse response
				response.status = 400
				response['sec-websocket-extensions'.freeze] = SUPPORTED_EXTENTIONS.keys.join(', ')
				response['sec-websocket-version'.freeze] = '13'.freeze
				false
			end

			# parse the message and send it to the handler
			#
			# test: frame = ["819249fcd3810b93b2fb69afb6e62c8af3e83adc94ee2ddd"].pack("H*").bytes; parser[:stage] = 0; parser = {}
			# accepts:
			# data:: an IO object (usually a StringIO object)
			def self.extract_message io, data
				parser = (io[:ws_parser] ||= parser_hash)
				until data.eof?
					if parser[:stage] == 0
						tmp = data.getbyte
						return unless tmp
						parser[:fin] = tmp[7] == 1
						parser[:rsv1] = tmp[6] == 1
						parser[:rsv2] = tmp[5] == 1
						parser[:rsv3] = tmp[4] == 1
						parser[:op_code] = tmp & 0b00001111
						parser[:p_op_code] ||= tmp & 0b00001111
						parser[:stage] += 1
					end
					if parser[:stage] == 1
						tmp = data.getbyte
						return unless tmp
						parser[:mask] = tmp[7]
						parser[:mask_key].clear
						parser[:len] = tmp & 0b01111111
						parser[:len_bytes].clear
						parser[:stage] += 1
					end
					if parser[:stage] == 2
						tmp = 0
						tmp = 2 if parser[:len] == 126
						tmp = 8 if parser[:len] == 127
						while parser[:len_bytes].length < tmp
							parser[:len_bytes] << data.getbyte
							return parser[:len_bytes].pop unless parser[:len_bytes].last
						end
						parser[:len] = merge_bytes( parser[:len_bytes] ) if tmp > 0
						parser[:step] = 0
						parser[:stage] += 1
						return false unless review_message_size io, parser
					end
					if parser[:stage] == 3 && parser[:mask] == 1
						until parser[:mask_key].length == 4
							parser[:mask_key] << data.getbyte
							return parser[:mask_key].pop unless parser[:mask_key].last
						end
						parser[:stage] += 1
					elsif  parser[:stage] == 3 && parser[:mask] != 1
						parser[:stage] += 1
					end
					if parser[:stage] == 4
						if parser[:body].bytesize < parser[:len]
							tmp = data.read(parser[:len] - parser[:body].bytesize)
							return unless tmp
							parser[:body] << tmp
						end
						if parser[:body].bytesize >= parser[:len]
							parser[:body].bytesize.times {|i| parser[:body][i] = (parser[:body][i].ord ^ parser[:mask_key][i % 4]).chr} if parser[:mask] == 1
							parser[:stage] = 99
						end
					end
					complete_frame io if parser[:stage] == 99
				end
				true
			end

			# takes and Array of bytes and combines them to an int(16 Bit), 32Bit or 64Bit number
			def self.merge_bytes bytes
				return 0 unless bytes.any?
				return bytes.pop if bytes.length == 1
				bytes.pop ^ (merge_bytes(bytes) << 8)
			end

			# The proc queued whenever a frame is complete.
			COMPLETE_FRAME_PROC = Proc.new {|h, e| h.on_message e}

			# handles the completed frame and sends a message to the handler once all the data has arrived.
			def self.complete_frame io
				parser = io[:ws_parser]
				io[:ws_extentions].each {|ex| ex.parse_frame(parser) } if io[:ws_extentions]

				case parser[:op_code]
				when 9 # ping
					# handle parser[:op_code] == 9 (ping)
					GReactor.callback self, :send_data, io, parser[:body], 10
					parser[:p_op_code] = nil if parser[:p_op_code] == 9
				when 10 #pong
					# handle parser[:op_code] == 10 (pong)
					parser[:p_op_code] = nil if parser[:p_op_code] == 10
				when 8 # close
					# handle parser[:op_code] == 8 (close)
					io.write( CLOSE_FRAME )
					io.close
					parser[:p_op_code] = nil if parser[:p_op_code] == 8
				else
					parser[:message] ? ((parser[:message] << parser[:body]) && parser[:body].clear) : ((parser[:message] = parser[:body]) && parser[:body] = '')
					# handle parser[:op_code] == 0 / fin == false (continue a frame that hasn't ended yet)
					if parser[:fin]
						io[:ws_extentions].each {|ex| ex.parse_message(parser) } if io[:ws_extentions]
						GRHttp::Base.make_utf8! parser[:message] if parser[:p_op_code] == 1
						GReactor.queue COMPLETE_FRAME_PROC, [io[:websocket_handler], WSEvent.new(io, parser[:message])]
						parser[:message] = nil
						parser[:p_op_code] = nil
					end
				end
				parser[:stage] = 0
				parser[:body].clear
				parser[:step] = 0
				parser[:mask_key].clear
				parser[:p_op_code] = nil
			end
			#reviews the message size and closes the connection if expected message size is over the allowed limit.
			def self.review_message_size io, parser
				if ( @message_size_limit.to_i > 0 ) && ( ( parser[:len] + (parser[:message] ? parser[:message].bytesize : 0) ) > @message_size_limit.to_i )
					io.close
					parser.delete :message
					parser[:step] = 0
					parser[:body].clear
					parser[:mask_key].clear
					parser = -1
					GReactor.warn "Websocket message above limit's set - closing connection."
					return false
				end
				true
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
