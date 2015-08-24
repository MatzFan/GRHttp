#!/usr/bin/env ruby

module GRHttp
	class HTTP2 < GReactor::Protocol
		module HPACK
			class IndexTable
				attr_reader :size
				attr_accessor :max_size
				def initialize
					@list = []
					@max_size = @size = 4_096 # initial defaul size by standard
				end
				def [] index
					return STATIC_LIST[index] if index < STATIC_LENGTH
					@list[index - STATIC_LENGTH]
				end
				def insert name, value = nil
					@list.unshift ( value ? [name, value] : [name])
					@list.pop while @list.count > @max_size
					self
				end
				def replace index, name, value
					index = index - STATIC_LENGTH
					raise 'HPACK Error - index invalid' if index < 0
					@list[index] = value ? [name, value] : [name]
					self
				end
				def resize value
					@size = value if value && value < @max_size
					@list.pop while @list.count > @max_size
					self
				end
			end

			class Context
				def initialize
					@list = IndexTable.new
				end

				def decode data
					data = StringIO.new data
					results = []
					while field = decode_field data
						results << field
					end
					results
				end

				# enabling cacheing will add new headers to the encoding/decoding list but will always ignore cookies
				# (which will be encoded, but not cached).
				def encode headers, cache = true
				end

				protected
				def decode_field data # expects a StringIO or other IO object
					if byte[7] == 1 # 0b1000_0000 == 0b1000_0000
						# An indexed header field starts with the '1' 1-bit pattern, followed by the index of the matching header field, represented as an integer with a 7-bit prefix (see Section 5.1).
					elsif byte & 192 == 63 # 0b1100_0000 == 0b0100_0000
						# A literal header field with incremental indexing representation starts with the '01' 2-bit pattern.
						# If the header field name matches the header field name of an entry stored in the static table or the dynamic table, the header field name can be represented using the index of that entry. In this case, the index of the entry is represented as an integer with a 6-bit prefix (see Section 5.1). This value is always non-zero.
						# Otherwise, the header field name is represented as a string literal (see Section 5.2). A value 0 is used in place of the 6-bit index, followed by the header field name.


					elsif byte & 240 # 0b1111_0000 == 0
						# A literal header field without indexing representation starts with the '0000' 4-bit pattern.
						# If the header field name matches the header field name of an entry stored in the static table or the dynamic table, the header field name can be represented using the index of that entry.
						# In this case, the index of the entry is represented as an integer with a 4-bit prefix (see Section 5.1). This value is always non-zero.
						# Otherwise, the header field name is represented as a string literal (see Section 5.2) and a value 0 is used in place of the 4-bit index, followed by the header field name.


					elsif byte & 240 == 16 # 0b1111_0000 == 0b0001_0000
						# A literal header field never-indexed representation starts with the '0001' 4-bit pattern + 4+ bits for index
					elsif byte & 224 == 32 # 0b1110_0000 == 0b0010_0000
						# A dynamic table size update starts with the '001' 3-bit pattern
						# followed by the new maximum size, represented as an integer with a 5-bit prefix (see Section 5.1).
					else
						# error?
					end
							
				end
			end


			STATIC_LIST = [ nil,
				[":authority"],
				[":method", "GET" ],
				[":method", "POST" ],
				[":path", "/" ],
				[":path", "/index.html" ],
				[":scheme", "http" ],
				[":scheme", "https" ],
				[":status", "200" ],
				[":status", "204" ],
				[":status", "206" ],
				[":status", "304" ],
				[":status", "400" ],
				[":status", "404" ],
				[":status", "500" ],
				["accept-charset"],
				["accept-encoding", "gzip, deflate" ],
				["accept-language"],
				["accept-ranges"],
				["accept"],
				["access-control-allow-origin"],
				["age"],
				["allow"],
				["authorization"],
				["cache-control"],
				["content-disposition"],
				["content-encoding"],
				["content-language"],
				["content-length"],
				["content-location"],
				["content-range"],
				["content-type"],
				["cookie"],
				["date"],
				["etag"],
				["expect"],
				["expires"],
				["from"],
				["host"],
				["if-match"],
				["if-modified-since"],
				["if-none-match"],
				["if-range"],
				["if-unmodified-since"],
				["last-modified"],
				["link"],
				["location"],
				["max-forwards"],
				["proxy-authenticate"],
				["proxy-authorization"],
				["range"],
				["referer"],
				["refresh"],
				["retry-after"],
				["server"],
				["set-cookie"],
				["strict-transport-security"],
				["transfer-encoding"],
				["user-agent"],
				["vary"],
				["via"],
				["www-authenticate"],
			]
			STATIC_LENGTH = STATIC_LIST.length

			HUFFMAN = [
				0b11111111_11000,
				0b11111111_11111111_1011000,
				0b11111111_11111111_11111110_0010,
				0b11111111_11111111_11111110_0011,
				0b11111111_11111111_11111110_0100,
				0b11111111_11111111_11111110_0101,
				0b11111111_11111111_11111110_0110,
				0b11111111_11111111_11111110_0111,
				0b11111111_11111111_11111110_1000,
				0b11111111_11111111_11101010,
				0b11111111_11111111_11111111_111100,
				0b11111111_11111111_11111110_1001,
				0b11111111_11111111_11111110_1010,
				0b11111111_11111111_11111111_111101,
				0b11111111_11111111_11111110_1011,
				0b11111111_11111111_11111110_1100,
				0b11111111_11111111_11111110_1101,
				0b11111111_11111111_11111110_1110,
				0b11111111_11111111_11111110_1111,
				0b11111111_11111111_11111111_0000,
				0b11111111_11111111_11111111_0001,
				0b11111111_11111111_11111111_0010,
				0b11111111_11111111_11111111_111110,
				0b11111111_11111111_11111111_0011,
				0b11111111_11111111_11111111_0100,
				0b11111111_11111111_11111111_0101,
				0b11111111_11111111_11111111_0110,
				0b11111111_11111111_11111111_0111,
				0b11111111_11111111_11111111_1000,
				0b11111111_11111111_11111111_1001,
				0b11111111_11111111_11111111_1010,
				0b11111111_11111111_11111111_1011,
				0b010100,
				0b11111110_00,
				0b11111110_01,
				0b11111111_1010,
				0b11111111_11001,
				0b010101,
				0b11111000,
				0b11111111_010,
				0b11111110_10,
				0b11111110_11,
				0b11111001,
				0b11111111_011,
				0b11111010,
				0b010110,
				0b010111,
				0b011000,
				0b00000,
				0b00001,
				0b00010,
				0b011001,
				0b011010,
				0b011011,
				0b011100,
				0b011101,
				0b011110,
				0b011111,
				0b1011100,
				0b11111011,
				0b11111111_1111100,
				0b100000,
				0b11111111_1011,
				0b11111111_00,
				0b11111111_11010,
				0b100001,
				0b1011101,
				0b1011110,
				0b1011111,
				0b1100000,
				0b1100001,
				0b1100010,
				0b1100011,
				0b1100100,
				0b1100101,
				0b1100110,
				0b1100111,
				0b1101000,
				0b1101001,
				0b1101010,
				0b1101011,
				0b1101100,
				0b1101101,
				0b1101110,
				0b1101111,
				0b1110000,
				0b1110001,
				0b1110010,
				0b11111100,
				0b1110011,
				0b11111101,
				0b11111111_11011,
				0b11111111_11111110_000,
				0b11111111_11100,
				0b11111111_111100,
				0b100010,
				0b11111111_1111101,
				0b00011,
				0b100011,
				0b00100,
				0b100100,
				0b00101,
				0b100101,
				0b100110,
				0b100111,
				0b00110,
				0b1110100,
				0b1110101,
				0b101000,
				0b101001,
				0b101010,
				0b00111,
				0b101011,
				0b1110110,
				0b101100,
				0b01000,
				0b01001,
				0b101101,
				0b1110111,
				0b1111000,
				0b1111001,
				0b1111010,
				0b1111011,
				0b11111111_1111110,
				0b11111111_100,
				0b11111111_111101,
				0b11111111_11101,
				0b11111111_11111111_11111111_1100,
				0b11111111_11111110_0110,
				0b11111111_11111111_010010,
				0b11111111_11111110_0111,
				0b11111111_11111110_1000,
				0b11111111_11111111_010011,
				0b11111111_11111111_010100,
				0b11111111_11111111_010101,
				0b11111111_11111111_1011001,
				0b11111111_11111111_010110,
				0b11111111_11111111_1011010,
				0b11111111_11111111_1011011,
				0b11111111_11111111_1011100,
				0b11111111_11111111_1011101,
				0b11111111_11111111_1011110,
				0b11111111_11111111_11101011,
				0b11111111_11111111_1011111,
				0b11111111_11111111_11101100,
				0b11111111_11111111_11101101,
				0b11111111_11111111_010111,
				0b11111111_11111111_1100000,
				0b11111111_11111111_11101110,
				0b11111111_11111111_1100001,
				0b11111111_11111111_1100010,
				0b11111111_11111111_1100011,
				0b11111111_11111111_1100100,
				0b11111111_11111110_11100,
				0b11111111_11111111_011000,
				0b11111111_11111111_1100101,
				0b11111111_11111111_011001,
				0b11111111_11111111_1100110,
				0b11111111_11111111_1100111,
				0b11111111_11111111_11101111,
				0b11111111_11111111_011010,
				0b11111111_11111110_11101,
				0b11111111_11111110_1001,
				0b11111111_11111111_011011,
				0b11111111_11111111_011100,
				0b11111111_11111111_1101000,
				0b11111111_11111111_1101001,
				0b11111111_11111110_11110,
				0b11111111_11111111_1101010,
				0b11111111_11111111_011101,
				0b11111111_11111111_011110,
				0b11111111_11111111_11110000,
				0b11111111_11111110_11111,
				0b11111111_11111111_011111,
				0b11111111_11111111_1101011,
				0b11111111_11111111_1101100,
				0b11111111_11111111_00000,
				0b11111111_11111111_00001,
				0b11111111_11111111_100000,
				0b11111111_11111111_00010,
				0b11111111_11111111_1101101,
				0b11111111_11111111_100001,
				0b11111111_11111111_1101110,
				0b11111111_11111111_1101111,
				0b11111111_11111110_1010,
				0b11111111_11111111_100010,
				0b11111111_11111111_100011,
				0b11111111_11111111_100100,
				0b11111111_11111111_1110000,
				0b11111111_11111111_100101,
				0b11111111_11111111_100110,
				0b11111111_11111111_1110001,
				0b11111111_11111111_11111000_00,
				0b11111111_11111111_11111000_01,
				0b11111111_11111110_1011,
				0b11111111_11111110_001,
				0b11111111_11111111_100111,
				0b11111111_11111111_1110010,
				0b11111111_11111111_101000,
				0b11111111_11111111_11110110_0,
				0b11111111_11111111_11111000_10,
				0b11111111_11111111_11111000_11,
				0b11111111_11111111_11111001_00,
				0b11111111_11111111_11111011_110,
				0b11111111_11111111_11111011_111,
				0b11111111_11111111_11111001_01,
				0b11111111_11111111_11110001,
				0b11111111_11111111_11110110_1,
				0b11111111_11111110_010,
				0b11111111_11111111_00011,
				0b11111111_11111111_11111001_10,
				0b11111111_11111111_11111100_000,
				0b11111111_11111111_11111100_001,
				0b11111111_11111111_11111001_11,
				0b11111111_11111111_11111100_010,
				0b11111111_11111111_11110010,
				0b11111111_11111111_00100,
				0b11111111_11111111_00101,
				0b11111111_11111111_11111010_00,
				0b11111111_11111111_11111010_01,
				0b11111111_11111111_11111111_1101,
				0b11111111_11111111_11111100_011,
				0b11111111_11111111_11111100_100,
				0b11111111_11111111_11111100_101,
				0b11111111_11111110_1100,
				0b11111111_11111111_11110011,
				0b11111111_11111110_1101,
				0b11111111_11111111_00110,
				0b11111111_11111111_101001,
				0b11111111_11111111_00111,
				0b11111111_11111111_01000,
				0b11111111_11111111_1110011,
				0b11111111_11111111_101010,
				0b11111111_11111111_101011,
				0b11111111_11111111_11110111_0,
				0b11111111_11111111_11110111_1,
				0b11111111_11111111_11110100,
				0b11111111_11111111_11110101,
				0b11111111_11111111_11111010_10,
				0b11111111_11111111_1110100,
				0b11111111_11111111_11111010_11,
				0b11111111_11111111_11111100_110,
				0b11111111_11111111_11111011_00,
				0b11111111_11111111_11111011_01,
				0b11111111_11111111_11111100_111,
				0b11111111_11111111_11111101_000,
				0b11111111_11111111_11111101_001,
				0b11111111_11111111_11111101_010,
				0b11111111_11111111_11111101_011,
				0b11111111_11111111_11111111_1110,
				0b11111111_11111111_11111101_100,
				0b11111111_11111111_11111101_101,
				0b11111111_11111111_11111101_110,
				0b11111111_11111111_11111101_111,
				0b11111111_11111111_11111110_000,
				0b11111111_11111111_11111011_10,
				0b11111111_11111111_11111111_111111].map {|i| i.to_s(2)};
		end
	end
end