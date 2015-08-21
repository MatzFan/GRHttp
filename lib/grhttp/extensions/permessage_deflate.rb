module GRHttp
	module Base
		# This is the "permessage-deflate" websocket extension class.
		#
		# This is still work in progress, but can be used to demonstrate how to write your own extentions.
		class WSDeflateExt

			#usual request: permessage-deflate; client_max_window_bits
			# more info at: https://www.igvita.com/2013/11/27/configuring-and-optimizing-websocket-compression/#takeover

			# The allowed arguments for this extention.
			ALLOWED_ARGS = {
				"server_no_context_takeover" => true,
				"client_no_context_takeover" => true,
				"server_max_window_bits" => true,
				"client_max_window_bits" => true
			}
			def initialize args
				@args = args
				args.each do |o|
					if o =~ /no_context_takeover/i
						@no_context = true
					else
						k, v = o.split(/[\s]*=[\s]*/)
						case k
						when /server_max_window_bits/i
							@server_max_window_bits = 0-v.to_i if v
						when /client_max_window_bits/i
							@client_max_window_bits = 0-v.to_i if v
							@client_max_window_bits ||= -15
						end
					end

				end
				# @no_context = true
				@server_max_window_bits ||= -11

				unless @no_context
					@inflator = Zlib::Inflate.new(@client_max_window_bits || 0)
					@deflator = Zlib::Deflate.new Zlib::DEFAULT_COMPRESSION, (0-@server_max_window_bits)
				end

			end
			def name
				if @no_context
					"permessage-deflate; server_no_context_takeover; client_no_context_takeover#{"; client_max_window_bits=#{0-@client_max_window_bits}" if @client_max_window_bits }"
				else
					"permessage-deflate; server_max_window_bits=#{0-@server_max_window_bits}; #{"client_max_window_bits=#{0-@client_max_window_bits}" if @client_max_window_bits }"
				end
			end
			def close
				@deflator.close if @deflator
				@inflator.close if @inflator
			end
			def parse_message parser
				if parser[:rsv1]
					parser[:rsv1] = false
					if @no_context
						parser[:message] = Zlib::Inflate.new(@client_max_window_bits || 0).inflate parser[:message]
					else
						parser[:message] = @inflator.inflate parser[:message]
					end
				end
			end
			def parse_frame parser
				true
			end
			def edit_message buffer
				if buffer.encoding == Encoding::UTF_8 && buffer.bytesize >= 16
					data = nil
					if @no_context
						data = Zlib::Deflate.deflate(buffer)
					else
						data = @deflator.deflate(buffer, Zlib::SYNC_FLUSH)
					end
					buffer.clear << data
					return 0b01000000
				end
				0
			end
			def edit_frame buffer
				0
			end
			def self.call args
				args.each {|a| return false unless ALLOWED_ARGS[a.downcase.split('=')[0].strip] }
				WSDeflateExt.new args
			end
		end
		GRHttp.register_ws_extention 'permessage-deflate', WSDeflateExt
	end
end
