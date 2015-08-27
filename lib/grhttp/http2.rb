module GRHttp

	class HTTP2 < ::GReactor::Protocol
		class Stream
			attr_accessor :window_size
		end
		def initialize io, original_request = nil
			# do stuff, i.e. related to the header:
			# HTTP2-Settings: <base64url encoding of HTTP/2 SETTINGS payload>
			GReactor.warn "HTTP/2 connection openne but not HTTP/2 isn't supported yet."

			super(io)
			#
			# also manage original request:
			# half closed by client.
			# use stream number 1 for the reply.
		end
		def on_open

			# Header compression is stateful
			@decoder = HPACK::Decoder.new
			@encoder = HPACK::Encoder.new

			# the header-stream cache
			@header_buffer = ''
			@header_end_stream = false
			@header_sid = nil

			# frame parser starting posotion
			@frame = {}

			# the last stream to be processed (For the GOAWAY frame)
			@last_stream = 0

			# the connection window size and the initial (new) stream window size
			@initial_window_size = @window_size = 65_535

			# maximum frame size
			@max_frame_size = 16_384

			# connection is only established after the preface was sent
			@connected = false


			# send connection preface (Section 3.5) consisting of a (can be empty) SETTINGS frame (Section 6.5).
			#
			# should prepare to accept a client connection preface which starts with:
			# 0x505249202a20485454502f322e300d0a0d0a534d0d0a0d0a
			# == PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n
			# + SETTINGS frame
		end
		def on_close
			@deflator.close if @deflator
			@inflator.close if @inflator
		end

		def on_message data
			data = ::StringIO.new data
			parse_preface data unless @connected
			true while parse_frame data
			data.string.clear
		end

		# Process a connection error and act accordingly.
		#
		# @return [true, false, nil] returns true if connection handling can continue of false (or nil) for a fatal error.
		def connection_error type
			case type
			when NO_ERROR
			when PROTOCOL_ERROR
			when INTERNAL_ERROR
			when FLOW_CONTROL_ERROR
			when SETTINGS_TIMEOUT
			when STREAM_CLOSED
			when FRAME_SIZE_ERROR
			when REFUSED_STREAM
			when CANCEL
			when COMPRESSION_ERROR
			when CONNECT_ERROR
			when ENHANCE_YOUR_CALM
			when INADEQUATE_SECURITY
			when HTTP_1_1_REQUIRED
			else
			end
					
			nil
		end

		# Error codes:

		# The associated condition is not a result of an error. For example, a GOAWAY might include this code to indicate graceful shutdown of a connection.
		NO_ERROR = 0x0
		# The endpoint detected an unspecific protocol error. This error is for use when a more specific error code is not available.
		PROTOCOL_ERROR = 0x1
		# The endpoint encountered an unexpected internal error.
		INTERNAL_ERROR = 0x2
		# The endpoint detected that its peer violated the flow-control protocol.
		FLOW_CONTROL_ERROR = 0x3
		# The endpoint sent a SETTINGS frame but did not receive a response in a timely manner. See Section 6.5.3 ("Settings Synchronization").
		SETTINGS_TIMEOUT = 0x4
		# The endpoint received a frame after a stream was half-closed.
		STREAM_CLOSED = 0x5
		# The endpoint received a frame with an invalid size.
		FRAME_SIZE_ERROR = 0x6
		# The endpoint refused the stream prior to performing any application processing (see Section 8.1.4 for details).
		REFUSED_STREAM = 0x7
		# Used by the endpoint to indicate that the stream is no longer needed.
		CANCEL = 0x8
		# The endpoint is unable to maintain the header compression context for the connection.
		COMPRESSION_ERROR = 0x9
		# The connection established in response to a CONNECT request (Section 8.3) was reset or abnormally closed.
		CONNECT_ERROR = 0xa
		# The endpoint detected that its peer is exhibiting a behavior that might be generating excessive load.
		ENHANCE_YOUR_CALM = 0xb
		# The underlying transport has properties that do not meet minimum security requirements (see Section 9.2).
		INADEQUATE_SECURITY = 0xc
		# The endpoint requires that HTTP/1.1 be used instead of HTTP/2.
		HTTP_1_1_REQUIRED = 0xd


		protected

		# Sends an HTTP frame with the requested payload
		#
		# @return [true, false] returns true if the frame was sent and false if the frame couldn't be sent (i.e. payload too big, connection closed etc').
		def emit_frame payload, sid = 0, type = 0, flags = 0
			frame = [payload.bytesize, type, flags, sid, payload].pack('N C C N a*'.freeze)
			frame.slice! 0
			@io.write(frame)
		end

		# Sends an HTTP frame group with the requested payload. This means the group will not be interrupted and will be sent as one unit.
		#
		# @return [true, false] returns true if the frame was sent and false if the frame couldn't be sent (i.e. payload too big, connection closed etc').
		def emit_data payload, type = 0, flags = 0
		end

		def parse_preface data
			return true if @connected
			unless data.read(24) == "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
				data.string.clear
				data.rewind
				return connection_error PROTOCOL_ERROR
			end
			true
		end

		def parse_frame data
			frame = (@frame ||= {})
			unless frame[:length]
				tmp = (frame[:length_bytes] ||= "\x00")
				tmp << data.read(4 - tmp.bytesize).to_s
				return false if tmp.bytesize < 4
				frame[:length] = frame.delete(:length_bytes).unpack('N')[0]
			end
			# TODO: error if length is greater than max_size (16_384 is default)
			if frame[:length] > @max_frame_size
				return false unless connection_error FRAME_SIZE_ERROR
			end
			unless frame[:type]
				tmp = data.getc
				return false unless tmp
				frame[:type] = tmp.ord
			end
			unless frame[:flags]
				tmp = data.getc
				return false unless tmp
				frame[:flags] = tmp.ord
			end
			unless frame[:sid]
				tmp = (frame[:sid_bytes] ||= '')
				tmp << data.read(4 - tmp.bytesize).to_s
				return false if tmp.bytesize < 4
				tmp = frame.delete(:sid_bytes).unpack('N')[0]
				frame[:sid] = tmp & 2147483647
				frame[:R] = tmp & 2147483648
			end
			unless frame[:complete]
				tmp = (frame[:body] ||= '')
				tmp << data.read(frame[:length] - tmp.bytesize).to_s
				return false if tmp.bytesize < frame[:length]
				frame[:complete] = true
			end
			#TODO: something - Async?
			process_frame frame
			# reset frame buffer
			@frame = {}
			true
		end

		def process_frame frame

			case frame[:type]
			when 0 # DATA
			when 1, 9 # HEADERS, CONTINUATION
				process_headers frame
			when 2 # PRIORITY
			when 3 # RST_STREAM
			when 4 # SETTINGS
			# when 5 # PUSH_PROMISE - Should only be sent by the server
			when 6 # PING
				process_ping frame
			when 7 # GOAWAY
			when 8 # WINDOW_UPDATE
			when 9 # 
			else # Error, frame not recognized
			end

			# The PING frame (type=0x6) (most important!!!) is a mechanism for measuring a minimal round-trip time from the sender, as well as determining whether an idle connection is still functional
			#   ACK flag: 0x1 - if not present, must send frame back.
			#   PING frames are not associated with any individual stream. If a PING frame is received with a stream identifier field value other than 0x0, the recipient MUST respond with a connection error (Section 5.4.1) of type PROTOCOL_ERROR.
			# DATA frames (type=0x0) convey arbitrary, variable-length sequences of octets associated with a stream. One or more DATA frames are used, for instance, to carry HTTP request or response payloads
			# The HEADERS frame (type=0x1) 
			# The RST_STREAM frame (type=0x3 - 32bit error code) allows for immediate termination of a stream. RST_STREAM is sent to request cancellation of a stream or to indicate that an error condition has occurred.
			# The SETTINGS frame (type=0x4) conveys configuration parameters that affect how endpoints communicate.
			#     The payload of a SETTINGS frame consists of zero or more parameters, each consisting of an unsigned 16-bit setting identifier and an unsigned 32-bit value
			# The CONTINUATION frame (type=0x9)
			#	The CONTINUATION frame defines the following flag:
			#	END_HEADERS (0x4):
			#	When set, bit 2 indicates that this frame ends a header block
			# The PRIORITY frame (type=0x2) specifies the sender-advised priority of a stream (Section 5.3). It can be sent in any stream state, including idle or closed streams
			# The PUSH_PROMISE frame (type=0x5) is used to notify the peer endpoint in advance of streams the sender intends to initiate.
			# The GOAWAY frame (type=0x7) is used to initiate shutdown of a connection or to signal serious error conditions.
			#   The GOAWAY frame applies to the connection, not a specific stream (DIS 0x0)
			#   R (1 bit) LAST_STREAM_ID  (31 bit) ERROR_CODE (32 bit) DEBUG_DATA(optional) (*)
			# The WINDOW_UPDATE frame (type=0x8) is used to implement flow control
			#   A WINDOW_UPDATE frame with a length other than 4 octets MUST be treated as a connection error (Section 5.4.1) of type FRAME_SIZE_ERROR.

		end

		def process_ping frame
			return connection_error PROTOCOL_ERROR if frame[:sid] != 0
			return true if frame[:flags][0] == 1
			emit_frame frame[:body], 6, 1
		end

		def process_headers frame
			if @header_sid && (frame[:type] == 1 || frame[:sid] != @header_sid)
				return connection_error PROTOCOL_ERROR
			end
			@header_end_stream = true if frame[:type] == 1 && frame[:flag][0] == 1

			@header_buffer << frame[:body]

			return unless frame[:flag][2] == 1 # fin

			headers = @decoder.decode @header_buffer # this is where HPACK comes in

			# TODO: manage headers and streams

			@header_buffer.clear
			@header_end_stream = false
			@header_sid = nil

		end

		def process_request request
			
		end

		public

		def self.handshake request, io, data
			return false unless request['upgrade'] =~ /h2c/ && request['http2-settings']
			io.write "HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: h2c\r\n\r\n"
			io.params[:handler] = HTTP2.new(io, request)
			unless data.eof?
				io.params[:handler].on_message data.read
			end
		end
	end
end

# require "irb"
# IRB.start

# GR::Settings.set_forking 4

# GR.on_shutdown { puts "\r\nGoodbye.\r\n" }

# # GR.create_logger nil
# GR.start(1) { GR.listen timeout: 5, handler: HTTP::HTTP, port: 3000, ssl_protocols: ['h2', 'http/1', 'http/1.1', 'http'] }






# Error Codes:
# NO_ERROR (0x0):
# The associated condition is not a result of an error. For example, a GOAWAY might include this code to indicate graceful shutdown of a connection.
# PROTOCOL_ERROR (0x1):
# The endpoint detected an unspecific protocol error. This error is for use when a more specific error code is not available.
# INTERNAL_ERROR (0x2):
# The endpoint encountered an unexpected internal error.
# FLOW_CONTROL_ERROR (0x3):
# The endpoint detected that its peer violated the flow-control protocol.
# SETTINGS_TIMEOUT (0x4):
# The endpoint sent a SETTINGS frame but did not receive a response in a timely manner. See Section 6.5.3 ("Settings Synchronization").
# STREAM_CLOSED (0x5):
# The endpoint received a frame after a stream was half-closed.
# FRAME_SIZE_ERROR (0x6):
# The endpoint received a frame with an invalid size.
# REFUSED_STREAM (0x7):
# The endpoint refused the stream prior to performing any application processing (see Section 8.1.4 for details).
# CANCEL (0x8):
# Used by the endpoint to indicate that the stream is no longer needed.
# COMPRESSION_ERROR (0x9):
# The endpoint is unable to maintain the header compression context for the connection.
# CONNECT_ERROR (0xa):
# The connection established in response to a CONNECT request (Section 8.3) was reset or abnormally closed.
# ENHANCE_YOUR_CALM (0xb):
# The endpoint detected that its peer is exhibiting a behavior that might be generating excessive load.
# INADEQUATE_SECURITY (0xc):
# The underlying transport has properties that do not meet minimum security requirements (see Section 9.2).
# HTTP_1_1_REQUIRED (0xd):
# The endpoint requires that HTTP/1.1 be used instead of HTTP/2.






# # Settings Codes:

# SETTINGS_HEADER_TABLE_SIZE (0x1):
# Allows the sender to inform the remote endpoint of the maximum size of the header compression table used to decode header blocks, in octets. The encoder can select any size equal to or less than this value by using signaling specific to the header compression format inside a header block (see [COMPRESSION]). The initial value is 4,096 octets.

# SETTINGS_ENABLE_PUSH (0x2):
# This setting can be used to disable server push (Section 8.2). An endpoint MUST NOT send a PUSH_PROMISE frame if it receives this parameter set to a value of 0. An endpoint that has both set this parameter to 0 and had it acknowledged MUST treat the receipt of a PUSH_PROMISE frame as a connection error (Section 5.4.1) of type PROTOCOL_ERROR.

# The initial value is 1, which indicates that server push is permitted. Any value other than 0 or 1 MUST be treated as a connection error (Section 5.4.1) of type PROTOCOL_ERROR.

# SETTINGS_MAX_CONCURRENT_STREAMS (0x3):
# Indicates the maximum number of concurrent streams that the sender will allow. This limit is directional: it applies to the number of streams that the sender permits the receiver to create. Initially, there is no limit to this value. It is recommended that this value be no smaller than 100, so as to not unnecessarily limit parallelism.

# A value of 0 for SETTINGS_MAX_CONCURRENT_STREAMS SHOULD NOT be treated as special by endpoints. A zero value does prevent the creation of new streams; however, this can also happen for any limit that is exhausted with active streams. Servers SHOULD only set a zero value for short durations; if a server does not wish to accept requests, closing the connection is more appropriate.

# SETTINGS_INITIAL_WINDOW_SIZE (0x4):
# Indicates the sender's initial window size (in octets) for stream-level flow control. The initial value is 216-1 (65,535) octets.

# This setting affects the window size of all streams (see Section 6.9.2).

# Values above the maximum flow-control window size of 231-1 MUST be treated as a connection error (Section 5.4.1) of type FLOW_CONTROL_ERROR.

# SETTINGS_MAX_FRAME_SIZE (0x5):
# Indicates the size of the largest frame payload that the sender is willing to receive, in octets.

# The initial value is 214 (16,384) octets. The value advertised by an endpoint MUST be between this initial value and the maximum allowed frame size (224-1 or 16,777,215 octets), inclusive. Values outside this range MUST be treated as a connection error (Section 5.4.1) of type PROTOCOL_ERROR.

# SETTINGS_MAX_HEADER_LIST_SIZE (0x6):
# This advisory setting informs a peer of the maximum size of header list that the sender is prepared to accept, in octets. The value is based on the uncompressed size of header fields, including the length of the name and value in octets plus an overhead of 32 octets for each header field.


