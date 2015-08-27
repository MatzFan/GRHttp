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
					@actual_size = 0
				end
				def [] index
					raise "HPACK Error - invalid header index: 0" if index == 0
					return STATIC_LIST[index] if index < STATIC_LENGTH
					raise "HPACK Error - invalid header index: 0" if @list.count <= (index - STATIC_LENGTH)
					@list[index - STATIC_LENGTH]
				end
				alias :get_index :[]
				def get_name index
					get_index(index)[0]
				end
				def insert *field
					@list.unshift field
					field.each {|f| @actual_size += f.to_s.bytesize}; @actual_size += 32
					resize
					field
				end
				def find *field
					index = STATIC_LIST.index(field)
					index ||= @list.index(feild)
					index ? (index + STATIC_LENGTH) : nil
				end
				def find_name name
					STATIC_LIST.each_with_index do |f, i|
						return i if f && f[0] == name
					end
					@list.each_with_index do |f, i|
						return i+STATIC_LENGTH if f[0] == name
					end
					nil
				end
				def resize value
					@size = value if value && value < @max_size
					while (@actual_size > @size) && @list.any?
						@list.pop.each {|i| @actual_size -= i.to_s.bytesize}
						@actual_size -= 32
					end
					self
				end
			end

			class Context
				def initialize
					@list = IndexTable.new
				end
				protected
				def decode_field data # expects a StringIO or other IO object
					byte = data.getbyte
					if byte[7] == 1 # 0b1000_0000 == 0b1000_0000
						# An indexed header field starts with the '1' 1-bit pattern, followed by the index of the matching header field, represented as an integer with a 7-bit prefix (see Section 5.1).
						num = extract_number data, byte, 1
						@list[num]
					elsif byte & 192 == 64 # 0b1100_0000 == 0b0100_0000
						# A literal header field with incremental indexing representation starts with the '01' 2-bit pattern.
						# If the header field name matches the header field name of an entry stored in the static table or the dynamic table, the header field name can be represented using the index of that entry. In this case, the index of the entry is represented as an integer with a 6-bit prefix (see Section 5.1). This value is always non-zero.
						# Otherwise, the header field name is represented as a string literal (see Section 5.2). A value 0 is used in place of the 6-bit index, followed by the header field name.
						num = extract_number data, byte, 2
						field_name = (num == 0) ? extract_string(data) : @list.get_name(num)
						field_value = extract_string(data)
						@list.insert field_name, field_value
					elsif byte & 224 # 0b1110_0000 == 0
						# A literal header field without indexing representation starts with the '0000' 4-bit pattern.
						# If the header field name matches the header field name of an entry stored in the static table or the dynamic table, the header field name can be represented using the index of that entry.
						# In this case, the index of the entry is represented as an integer with a 4-bit prefix (see Section 5.1). This value is always non-zero.
						# Otherwise, the header field name is represented as a string literal (see Section 5.2) and a value 0 is used in place of the 4-bit index, followed by the header field name.
						# OR
						# A literal header field never-indexed representation starts with the '0001' 4-bit pattern + 4+ bits for index
						num = extract_number data, byte, 4
						field_name = (num == 0) ? extract_string(data) : @list.get_name(num)
						field_value = extract_string(data)
						[field_name, field_value]
					elsif byte & 224 == 32 # 0b1110_0000 == 0b0010_0000
						# A dynamic table size update starts with the '001' 3-bit pattern
						# followed by the new maximum size, represented as an integer with a 5-bit prefix (see Section 5.1).
						@list.resize extract_number(data, byte, 5)
						[].freeze
					else
						raise "HPACK Error - invalid field indicator."
					end
				end
				def encode_field name, value
					if value.is_a?(Array)
						return (value.map {|v| encode_field name, v} .join)
					end
					if name == 'set-cookie'
						buffer = ''
						buffer << pack_number( 55, 16, 4)
						buffer << pack_string(value)
						return buffer
					end
					index = @list.find(name, value)
					return pack_number( index, 1, 1) if index
					index = @list.find_name name
					@list.insert name, value
					buffer = ''
					if index
						buffer << pack_number( index, 64, 2)
					else
						buffer << pack_number( 0, 64, 2)
						buffer << pack_string(name)
					end
					buffer << pack_string(value)
					buffer
				end
				def extract_number data, prefix, prefix_length
					mask = 255 >> prefix_length
					return prefix & mask unless (prefix & mask) == mask
					count = prefix = 0
					loop do
						c = data.getbyte
						prefix = prefix | ((c & 127) << (7*count))
						break if c[7] == 0
						count += 1
					end
					prefix + mask
				# rescue e =>
				# 	raise "HPACK Error - number input invalid"
				end
				def pack_number number, prefix, prefix_length
					n_length = 8-prefix_length
					if (number + 1 ).bit_length <= n_length
						return ((prefix << n_length) | number).chr
					end
					prefix = [(prefix << n_length) | (2**n_length - 1)]
					number -= 2**n_length - 1
					loop do
						prefix << ((number & 127) | 128)
						number = number >> 7
						break if number == 0
					end
					(prefix << (prefix.pop & 127)).pack('C*'.freeze)
				end
				def pack_string string, deflate = true
					string = deflate(string) if deflate
					(pack_number(string.bytesize, (deflate ? 1 : 0), 1) + string).force_encoding ::Encoding::ASCII_8BIT
				end
				def extract_string data
					byte = data.getbyte
					hoffman = byte[7] == 1
					length = extract_number data, byte, 1
					if hoffman
						inflate data.read(length)
					else
						data.read length
					end
				end
				def inflate data
					data = StringIO.new data
					str = ''
					buffer = ''
					until data.eof?
						byte = data.getbyte
						8.times do |i|
							buffer << byte[7-i].to_s
							if HUFFMAN[buffer]
								str << HUFFMAN[buffer].chr rescue raise("HPACK Error - Huffman EOS found")
								buffer.clear
							end
						end
					end
					raise "HPACK Error - Huffman padding too long (#{buffer.length}): #{buffer}" if buffer.length > 29
					str
				end
				def deflate data
					str = ''
					buffer = ''
					data.bytes.each do |i|
						buffer << HUFFMAN.key(i)
						if (buffer % 8) == 0
							str << [buffer].pack('b*')
							buffer.clear
						end
					end
					(8-(buffer.bytesize % 8)).times { buffer << '1'}
					str << [buffer].pack('b*')
					buffer.clear
					str
				end
			end

			class Decoder < Context
				def decode data
					data = StringIO.new data
					results = {}
					while (field = decode_field(data))
						results[field[0]] ? (results[field[0]].is_a?(String) ? (results[field[0]] = [results[field[0]], field[1]]) : (results[field[0]] << field[1]) ) : (results[field[0]] = field[1]) if field[1]
					end
					results
				end
			end
			class Encoder < Context
				def encode headers = {}
					buffer = ''
					headers.each {|k, v| buffer << encode_field(b,v) if v}
					buffer
				end
			end


			STATIC_LIST = [ nil,
				[:authority],
				[:method, "GET" ],
				[:method, "POST" ],
				[:path, "/" ],
				[:path, "/index.html" ],
				[:scheme, "http" ],
				[:scheme, "https" ],
				[:status, "200" ],
				[:status, "204" ],
				[:status, "206" ],
				[:status, "304" ],
				[:status, "400" ],
				[:status, "404" ],
				[:status, "500" ],
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
				["www-authenticate"] ].map! {|a| a.map! {|s| s.is_a?(String) ? s.freeze : s } && a.freeze if a}
			STATIC_LENGTH = STATIC_LIST.length

			HUFFMAN = [
				"1111111111000", 
				"11111111111111111011000", 
				"1111111111111111111111100010", 
				"1111111111111111111111100011", 
				"1111111111111111111111100100", 
				"1111111111111111111111100101", 
				"1111111111111111111111100110", 
				"1111111111111111111111100111", 
				"1111111111111111111111101000", 
				"111111111111111111101010", 
				"111111111111111111111111111100", 
				"1111111111111111111111101001", 
				"1111111111111111111111101010", 
				"111111111111111111111111111101", 
				"1111111111111111111111101011", 
				"1111111111111111111111101100", 
				"1111111111111111111111101101", 
				"1111111111111111111111101110", 
				"1111111111111111111111101111", 
				"1111111111111111111111110000", 
				"1111111111111111111111110001", 
				"1111111111111111111111110010", 
				"111111111111111111111111111110", 
				"1111111111111111111111110011", 
				"1111111111111111111111110100", 
				"1111111111111111111111110101", 
				"1111111111111111111111110110", 
				"1111111111111111111111110111", 
				"1111111111111111111111111000", 
				"1111111111111111111111111001", 
				"1111111111111111111111111010", 
				"1111111111111111111111111011", 
				"010100", 
				"1111111000", 
				"1111111001", 
				"111111111010", 
				"1111111111001", 
				"010101", 
				"11111000", 
				"11111111010", 
				"1111111010", 
				"1111111011", 
				"11111001", 
				"11111111011", 
				"11111010", 
				"010110", 
				"010111", 
				"011000", 
				"00000", 
				"00001", 
				"00010", 
				"011001", 
				"011010", 
				"011011", 
				"011100", 
				"011101", 
				"011110", 
				"011111", 
				"1011100", 
				"11111011", 
				"111111111111100", 
				"100000", 
				"111111111011", 
				"1111111100", 
				"1111111111010", 
				"100001", 
				"1011101", 
				"1011110", 
				"1011111", 
				"1100000", 
				"1100001", 
				"1100010", 
				"1100011", 
				"1100100", 
				"1100101", 
				"1100110", 
				"1100111", 
				"1101000", 
				"1101001", 
				"1101010", 
				"1101011", 
				"1101100", 
				"1101101", 
				"1101110", 
				"1101111", 
				"1110000", 
				"1110001", 
				"1110010", 
				"11111100", 
				"1110011", 
				"11111101", 
				"1111111111011", 
				"1111111111111110000", 
				"1111111111100", 
				"11111111111100", 
				"100010", 
				"111111111111101", 
				"00011", 
				"100011", 
				"00100", 
				"100100", 
				"00101", 
				"100101", 
				"100110", 
				"100111", 
				"00110", 
				"1110100", 
				"1110101", 
				"101000", 
				"101001", 
				"101010", 
				"00111", 
				"101011", 
				"1110110", 
				"101100", 
				"01000", 
				"01001", 
				"101101", 
				"1110111", 
				"1111000", 
				"1111001", 
				"1111010", 
				"1111011", 
				"111111111111110", 
				"'", 
				"11111111111101", 
				"1111111111101", 
				"1111111111111111111111111100", 
				"11111111111111100110", 
				"1111111111111111010010", 
				"11111111111111100111", 
				"11111111111111101000", 
				"1111111111111111010011", 
				"1111111111111111010100", 
				"1111111111111111010101", 
				"11111111111111111011001", 
				"1111111111111111010110", 
				"11111111111111111011010", 
				"11111111111111111011011", 
				"11111111111111111011100", 
				"11111111111111111011101", 
				"11111111111111111011110", 
				"111111111111111111101011", 
				"11111111111111111011111", 
				"111111111111111111101100", 
				"111111111111111111101101", 
				"1111111111111111010111", 
				"11111111111111111100000", 
				"111111111111111111101110", 
				"11111111111111111100001", 
				"11111111111111111100010", 
				"11111111111111111100011", 
				"11111111111111111100100", 
				"111111111111111011100", 
				"1111111111111111011000", 
				"11111111111111111100101", 
				"1111111111111111011001", 
				"11111111111111111100110", 
				"11111111111111111100111", 
				"111111111111111111101111", 
				"1111111111111111011010", 
				"111111111111111011101", 
				"11111111111111101001", 
				"1111111111111111011011", 
				"1111111111111111011100", 
				"11111111111111111101000", 
				"11111111111111111101001", 
				"111111111111111011110", 
				"11111111111111111101010", 
				"1111111111111111011101", 
				"1111111111111111011110", 
				"111111111111111111110000", 
				"111111111111111011111", 
				"1111111111111111011111", 
				"11111111111111111101011", 
				"11111111111111111101100", 
				"111111111111111100000", 
				"111111111111111100001", 
				"1111111111111111100000", 
				"111111111111111100010", 
				"11111111111111111101101", 
				"1111111111111111100001", 
				"11111111111111111101110", 
				"11111111111111111101111", 
				"11111111111111101010", 
				"1111111111111111100010", 
				"1111111111111111100011", 
				"1111111111111111100100", 
				"11111111111111111110000", 
				"1111111111111111100101", 
				"1111111111111111100110", 
				"11111111111111111110001", 
				"11111111111111111111100000", 
				"11111111111111111111100001", 
				"11111111111111101011", 
				"1111111111111110001", 
				"1111111111111111100111", 
				"11111111111111111110010", 
				"1111111111111111101000", 
				"1111111111111111111101100", 
				"11111111111111111111100010", 
				"11111111111111111111100011", 
				"11111111111111111111100100", 
				"111111111111111111111011110", 
				"111111111111111111111011111", 
				"11111111111111111111100101", 
				"111111111111111111110001", 
				"1111111111111111111101101", 
				"1111111111111110010", 
				"111111111111111100011", 
				"11111111111111111111100110", 
				"111111111111111111111100000", 
				"111111111111111111111100001", 
				"11111111111111111111100111", 
				"111111111111111111111100010", 
				"111111111111111111110010", 
				"111111111111111100100", 
				"111111111111111100101", 
				"11111111111111111111101000", 
				"11111111111111111111101001", 
				"1111111111111111111111111101", 
				"111111111111111111111100011", 
				"111111111111111111111100100", 
				"111111111111111111111100101", 
				"11111111111111101100", 
				"111111111111111111110011", 
				"11111111111111101101", 
				"111111111111111100110", 
				"1111111111111111101001", 
				"111111111111111100111", 
				"111111111111111101000", 
				"11111111111111111110011", 
				"1111111111111111101010", 
				"1111111111111111101011", 
				"1111111111111111111101110", 
				"1111111111111111111101111", 
				"111111111111111111110100", 
				"111111111111111111110101", 
				"11111111111111111111101010", 
				"11111111111111111110100", 
				"11111111111111111111101011", 
				"111111111111111111111100110", 
				"11111111111111111111101100", 
				"11111111111111111111101101", 
				"111111111111111111111100111", 
				"111111111111111111111101000", 
				"111111111111111111111101001", 
				"111111111111111111111101010", 
				"111111111111111111111101011", 
				"1111111111111111111111111110", 
				"111111111111111111111101100", 
				"111111111111111111111101101", 
				"111111111111111111111101110", 
				"111111111111111111111101111", 
				"111111111111111111111110000", 
				"11111111111111111111101110", 
				"111111111111111111111111111111"].map.with_index {|s, i| [s, i]} .to_h
		end
	end
end