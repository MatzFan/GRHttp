module GRHttp

	# This (will be) a Rack handler for the GRHttp server.
	module Base
		class Rack
			def initialize app
				@app = app			
			end

			def start
				@listeners.each do |params|
					params[:pre_rack_handler] = params[:http_handler]
					params[:http_handler] = self
				end

				GRHttp.listen http_handler: self if @listeners.empty?

				self.start

			end
			def call request, response
				if tmp = request[:io].params[:pre_rack_handler]
					tmp = tmp.call(request, response)
					return tmp if tmp
				end
				response.run_rack @app
			end
		end
		Rack::Handler.register( 'grhttp', 'GRHttp::Base::Rack') if defined?(::Rack)
	end

	class HTTPResponse

		def run_rack app
			prep_for_rack
			res = app.call(@request)
			raise "Rack app returned an unexpected value: #{res.to_s}" unless res && res.is_a?(Array)
			@status = res[0]
			res[1].each {|h, v| self[h] = v}
			if res[2].is_a?(Array)
				@body = res[2]
			else
				@body = nil
				res[2].each {|d| send d}
				res[2].close if res[2].respond_to? :close
			end
		end
		protected

		def prep_for_rack
			RACK_DICTIONARY.each {|k, val| @request[k] = val.is_a?(Symbol) ? @request[val] : val}
			@request.each {|k, v| @request[k.upcase.gsub('-', '_')] = v if k.is_a?(String) && k.match(/^http_/)}
			@request['rack.version'] = ( @rack_version ||= Rack.version.split('.') )

		end

		RACK_DICTIONARY = {
			'REQUEST_METHOD'	=>	:method,
			'SCRIPT_NAME'		=>	'',
			'PATH_INFO'			=> :path,
			'QUERY_STRING'		=> :query,
			'SERVER_NAME'		=> 'localhost',
			'SERVER_PORT'		=> :port,
			'rack.url_scheme'	=> :requested_protocol,
			'rack.input'		=> StringIO.new(''),
			'rack.errors'		=> StringIO.new(''),
			'rack.multithread'	=> true,
			'rack.multiprocess'	=> true,
			'rack.hijack?'		=> false,
			'rack.hijack'		=> (Proc.new {false}),
			'rack.hijack_io'	=> nil,
			'rack.run_once'		=> false
		}
	end

end


######
## example requests

# GET /stream HTTP/1.1
# Host: localhost:3000
# Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8
# Cookie: user_token=2INa32_vDgx8Aa1qe43oILELpSdIe9xwmT8GTWjkS-w
# User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10) AppleWebKit/600.1.25 (KHTML, like Gecko) Version/8.0 Safari/600.1.25
# Accept-Language: en-us
# Accept-Encoding: gzip, deflate
# Connection: keep-alive