module GRHttp

	# This (will be) a Rack handler for the GRHttp server.
	module Base
		module Rack
			module_function
			def run(app, options = {})
				@app = app			
				add = true
				(GReactor.instance_variable_get(:@listeners) || {}).each do |params, io|
					# if this is the first listener with a default port - update the port number
					params[:port] = options[:Port] if params[:port] == 3000 && add
					params[:pre_rack_handler] = params[:http_handler]
					params[:http_handler] = self
					add = false
				end

				GRHttp.listen port: options[:Port], bind: options[:Host], http_handler: self if add

				GReactor.log_raw "\r\nStarting GRHttp v. #{GRHttp::VERSION} on GReactor #{GReactor::VERSION}.\r\n"
				GReactor.log_raw "\r\nUse ^C to exit\r\n"

				GReactor.start
				GReactor.join {GReactor.log_raw "\r\nGRHttp and GReactor starting shutdown\r\n"}
				GReactor.log_raw "\r\nGRHttp and GReactor completed shutdown\r\n"
			end
			def call request, response
				if tmp = request[:io].params[:pre_rack_handler]
					tmp = tmp.call(request, response)
					return tmp if tmp
				end
				response.quite!
				response.run_rack @app
			end
		end
		::Rack::Handler.register( 'grhttp', 'GRHttp::Base::Rack') if defined?(::Rack)
	end

	class HTTPResponse

		def run_rack app
			res = app.call(rack_env)
			raise "Rack app returned an unexpected value: #{res.to_s}" unless res && res.is_a?(Array)
			@status = res[0]
			#fix cookies
			# puts res[1]['Set-Cookie'].dump
			res[1]['Rack-Cookies'] = "true\r\nSet-Cookie: " + (res[1].delete('Set-Cookie').split("\n")).join("\r\nSet-Cookie: ") if res[1]['Set-Cookie']
			res[1].each {|h, v| self[h.dup] = v}
			# send body
			if res[2].is_a?(Array)
				@body = res[2]
			elsif res[2].is_a?(Rack::Chunked::Body)
				@body = nil
				res[2].instance_variable_get(:@body).each {|d| send d }
				res[2].close if res[2].respond_to? :close
			else
				@body = nil
				res[2].each {|d| send d }
				res[2].close if res[2].respond_to? :close
			end
		end
		protected
		HASH_SYM_PROC = Proc.new {|h,k| k = (Symbol === k ? k.to_s : k.to_s.to_sym); h.has_key?(k) ? h[k] : (h["gr.#{k.to_s}"] if h.has_key?("gr.#{k.to_s}") ) }

		def rack_env
			env = RACK_DICTIONARY.dup
			# env['pl.request'] = @request
			# env.each {|k, v| env[k] = @request[v] if v.is_a?(Symbol)}
			env.each {|k, v| env[k] = (@request[v].is_a?(String) ? ( @request[v].frozen? ? @request[v].dup.force_encoding('ASCII-8BIT') : @request[v].force_encoding('ASCII-8BIT') ): @request[v]) if v.is_a?(Symbol)}
			@request.headers.each {|k, v| env["HTTP_#{k.upcase.gsub('-', '_')}"] = v }
			env['rack.input'] ||= StringIO.new(''.force_encoding('ASCII-8BIT'))
			env['CONTENT_LENGTH'] = @request['content-length'] if @request['content-length']
			env['CONTENT_TYPE'] = @request['content-type'] if @request['content-type']
			env.delete 'HTTP_CONTENT_LENGTH'
			env.delete 'HTTP_CONTENT_TYPE'
			env['HTTP_VERSION'] = "HTTP/#{request[:version].to_s}"
			env['QUERY_STRING'] ||= ''
			env
		end

		RACK_DICTIONARY = {
			'SERVER_SOFTWARE'	=> "GRHttp v. #{GRHttp::VERSION} on GReactor #{GReactor::VERSION}",
			'REQUEST_METHOD'	=> :method,
			'SCRIPT_NAME'		=> ''.force_encoding('ASCII-8BIT'),
			'PATH_INFO'			=> :original_path,
			'REQUEST_PATH'		=> :path,
			'QUERY_STRING'		=> :quary_params,
			'SERVER_NAME'		=> :host_name,
			'REQUEST_URI'		=> :query,
			'SERVER_PORT'		=> :port,
			'REMOTE_ADDR'		=> :client_ip,
			"GATEWAY_INTERFACE"	=>"CGI/1.2",
			'pl.params'			=> :params,
			'pl.cookies'		=> :cookies,
			'rack.logger'		=> GReactor,
			'rack.url_scheme'	=> :requested_protocol,
			'rack.input'		=> :rack_input,
			'rack.errors'		=> StringIO.new(''),
			'rack.multithread'	=> true,
			'rack.multiprocess'	=> true,
			# 'rack.hijack?'		=> false,
			# 'rack.hijack_io'	=> nil,
			'rack.run_once'		=> false
		}
		RACK_DICTIONARY['rack.version'] = ::Rack.version.split('.') if defined?(::Rack)

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