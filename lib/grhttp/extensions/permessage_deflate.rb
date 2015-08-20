module GRHttp
	module Base
		# This is the "permessage-deflate" websocket extension class.
		#
		# This is still work in progress, but can be used to demonstrate how to write your own extentions.
		class WSDeflateExt
			def initialize args
				
			end
			def parse parser
				if parser[:rsv1]
					parser[:body] = Zlib.inflate parser[:body]
				end
			end
			def edit_message buffer
				if buffer.encoding == Encoding::UTF_8 && buffer.bytesize >= 64
					buffer.clear << Zlib.deflate(buffer)
					return 0b01000000
				end
			end
			def edit_frame buffer
				0
			end
			def self.call args
				if false
					return WSDeflateExt.new args
				end
				nil
			end
		end
		# GRHttp.register_ws_extention 'permessage-deflate', WSDeflateExt
	end
end
