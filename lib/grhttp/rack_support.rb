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
					params[:port] = options[:Port] if options[:Port] && params[:port] == 3000 && add
					params[:pre_rack_handler] = params[:http_handler]
					params[:http_handler] = self
					add = false
				end

				GRHttp.listen port: options[:Port], bind: options[:Host], http_handler: self if add

				GReactor.log_raw "\r\nStarting GRHttp v. #{GRHttp::VERSION} with GReactor #{GReactor::VERSION} for Rack.\r\nUse ^C to exit\r\n"

				# if GReactor.forking?
				# 	GReactor.forking 0
				# 	GReactor.warn 'Forking GRHttp is disabled when using Rack.'
				# end

				GReactor.stop.join if GReactor.running?
				GReactor.start(8)
				GReactor.join {GReactor.log_raw "\r\nGRHttp starting shutdown\r\n"}
				GReactor.log_raw "\r\nGRHttp completed shutdown\r\n"
				true
			end
			def call request, response
				if tmp = request[:io].params[:pre_rack_handler]
					tmp = tmp.call(request, response)
					return tmp if tmp
				end
				# response.quite!
				res = @app.call rack_env(request)
				raise "Rack app returned an unexpected value: #{res.to_s}" unless res && res.is_a?(Array)
				response.status = res[0]
				response.headers.clear
				response.headers.update res[1]
				response.body = res[2]
				response.raw_cookies.clear
				response.headers['Set-Cookie'] = response.headers.delete('Set-Cookie').split("\n").join("\r\nSet-Cookie: ") if response.headers['Set-Cookie']
				true
			end

			protected


			def self.run_rack request, app
				status = res[0]
				finished = true
				body = nil
				headers = {}

				# fix connection header? - Default to closing the connection rather than keep-alive. Turbolinks and Rack have issues.
				# if res[1]['Connection'.freeze] =~ /^k/i || (@request[:version].to_f > 1 && @request['connection'.freeze].nil?) || @request['connection'.freeze] =~ /^k/i
				if res[1]['Connection'.freeze] =~ /^k/i || (request['connection'.freeze] && request['connection'.freeze] =~ /^k/i)
					@io[:keep_alive] = true
					# res[1]['Connection'.freeze] ||= "Keep-Alive\r\nKeep-Alive: timeout=5".freeze
				else
					res[1]['Connection'.freeze] ||= "close".freeze unless request.io[:keep_alive]
				end

				# @io[:keep_alive] = true if res[1]['Connection'].to_s.match(/^k/i)
				# res[1]['Connection'] ||= "close"

				# Send Rack's headers
				out = ''
				out << "#{@http_version} #{@status} #{STATUS_CODES[@status] || 'unknown'}\r\n" #"Date: #{Time.now.httpdate}\r\n"
				out << ('Set-Cookie: ' + (res[1].delete('Set-Cookie').split("\n")).join("\r\nSet-Cookie: ") + "\r\n") if res[1]['Set-Cookie'.freeze]
				res[1].each {|h, v| out << "#{h.to_s}: #{v}\r\n"}

				out << "\r\n".freeze
				@io.write out
				out.clear

				# send body using Rack's rendering 
				res[2].each {|d| @io.write d }
				res[2].close if res[2].respond_to? :close
				@io.close unless @io[:keep_alive]
			end
			def self.rack_env request
				env = RACK_DICTIONARY.dup
				# env['pl.request'] = @request
				# env.each {|k, v| env[k] = @request[v] if v.is_a?(Symbol)}
				RACK_ADDON.each {|k, v| env[k] = (request[v].is_a?(String) ? ( request[v].frozen? ? request[v].dup.force_encoding('ASCII-8BIT') : request[v].force_encoding('ASCII-8BIT') ): request[v])}
				request.each {|k, v| env["HTTP_#{k.upcase.gsub('-', '_')}"] = v if k.is_a?(String) }
				env['rack.input'.freeze] ||= StringIO.new(''.force_encoding('ASCII-8BIT'.freeze))
				env['CONTENT_LENGTH'.freeze] = env.delete 'HTTP_CONTENT_LENGTH'.freeze if env['HTTP_CONTENT_LENGTH'.freeze]
				env['CONTENT_TYPE'.freeze] = env.delete 'HTTP_CONTENT_TYPE'.freeze if env['HTTP_CONTENT_TYPE'.freeze]
				env['HTTP_VERSION'.freeze] = "HTTP/#{request[:version].to_s}"
				env['QUERY_STRING'.freeze] ||= ''
				env['rack.errors'.freeze] = StringIO.new('')
				env
			end

			RACK_ADDON = {
				'PATH_INFO'			=> :original_path,
				'REQUEST_PATH'		=> :path,
				'QUERY_STRING'		=> :quary_params,
				'SERVER_NAME'		=> :host_name,
				'REQUEST_URI'		=> :query,
				'SERVER_PORT'		=> :port,
				'REMOTE_ADDR'		=> :client_ip,
				# 'gr.params'			=> :params,
				# 'gr.cookies'		=> :cookies,
				'REQUEST_METHOD'	=> :method,
				'rack.url_scheme'	=> :scheme,
				'rack.input'		=> :rack_input
			}

			RACK_DICTIONARY = {
				"GATEWAY_INTERFACE"	=>"CGI/1.2",
				'SERVER_SOFTWARE'	=> "GRHttp v. #{GRHttp::VERSION} on GReactor #{GReactor::VERSION}",
				'SCRIPT_NAME'		=> ''.force_encoding('ASCII-8BIT'),
				'rack.logger'		=> GReactor,
				'rack.multithread'	=> true,
				'rack.multiprocess'	=> (GReactor.forking?),
				# 'rack.hijack?'		=> false,
				# 'rack.hijack_io'	=> nil,
				'rack.run_once'		=> false
			}
			RACK_DICTIONARY['rack.version'] = ::Rack.version.split('.') if defined?(::Rack)
			HASH_SYM_PROC = Proc.new {|h,k| k = (Symbol === k ? k.to_s : k.to_s.to_sym); h.has_key?(k) ? h[k] : (h["gr.#{k.to_s}"] if h.has_key?("gr.#{k.to_s}") ) }
		end
	end
end

# ENV["RACK_HANDLER"] = 'grhttp'

# make GRHttp the default fallback position for Rack.
begin
	require 'rack/handler'
	Rack::Handler::WEBrick = Rack::Handler.get(:grhttp)
rescue Exception => e

end
::Rack::Handler.register( 'grhttp', 'GRHttp::Base::Rack') if defined?(::Rack)

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