require "minitest/autorun"
require "bundler/setup"
require 'grhttp'


describe GRHttp::HTTP2::HPACK::Context do
	before do
		@context = GRHttp::HTTP2::HPACK::Context.new
	end

	describe "HPACK - encoding/dencoding a number" do
		it "Will correctly encode/decode a number." do
			(@context.instance_eval { extract_number(StringIO.new(''), 254, 1) }).must_equal 126
			(@context.instance_eval { extract_number(StringIO.new(0.chr), 255, 1) }).must_equal 127
			(@context.instance_eval { extract_number(StringIO.new(128.chr + 1.chr), 255, 1) }).must_equal 255
			(@context.instance_eval { pack_number 16800722, 1, 1 }).must_equal "\xFF\xD3\xB6\x81\b".force_encoding('binary')
			(@context.instance_eval { extract_number StringIO.new("\xD3\xB6\x81\b".force_encoding('binary')), 0x7F, 1 }).must_equal 16800722
		end
	end
	describe "HPACK - (Un)Packing a header field" do
		it "Will correctly find an indexed field." do
			(@context.instance_eval { decode_field StringIO.new("\x82") }).must_equal [:method, 'GET']
		end
		it "Will correctly decode a literal field." do
			(@context.instance_eval { decode_field StringIO.new("@\ncustom-key\rcustom-header") }).must_equal ['custom-key', 'custom-header']
		end
		it "Will correctly decode an indexed literal field." do
			(@context.instance_eval { decode_field StringIO.new("\x04\f/sample/path") }).must_equal [:path, '/sample/path']
		end

		it "Will correctly decode a Huffman encoded header list." do
			list = StringIO.new "\x82\x86\x84A\x8C\xF1\xE3\xC2\xE5\xF2:k\xA0\xAB\x90\xF4\xFFmore_data"
			(@context.instance_eval { decode_field list }).must_equal [:method, 'GET']
			(@context.instance_eval { decode_field list }).must_equal [:scheme, 'http']
			(@context.instance_eval { decode_field list }).must_equal [:path, '/']
			(@context.instance_eval { decode_field list }).must_equal [:authority, 'www.example.com']
			# chack for reader overflow
			list.read.must_equal 'more_data'
			# check for dynamic table update
			(@context.instance_eval { @list[62] }).must_equal [:authority, 'www.example.com']
		end
	end
	# describe "HPACK - encoding a number" do
	# 	it "Will correctly encode a number." do
	# 		(@context.instance_eval { pack_number(number, prefix) }).must_equal "literal string encoding"
	# 	end
	# end
end
