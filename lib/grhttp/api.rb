module GRHttp

	# extend GReactor

	module_function

	# Opens a web-service (HTTP and Websocket) on the specified port.
	#
	# Accepts a parameter Hash and an optional block.
	#
	# The following parameters are recognized:
	# port:: The port number to listen to. Defaults to 3000 and increments by 1 with every portless listen call (3000, 3001, 3002...).
	# http_handler:: The object that will handle the connection. Should answer to `#call request, response`.
	# upgrade_handler:: The object that will handle WebSocket upgrade requests. Should answer to `#call request, response`, should return the new WebSocket Handler while setting any cookies for the response or false (ro refuse the request).
	# ssl:: Set this parameter to true to listen and react to SSL connections with a self signed certificate.
	# ssl_key + ssl_cert:: Set both these parameters to listen to an SSL connection with a registered certificate. Falls back to a self registered certificate if one of the two is missing.
	#
	#
	def listen params = {}, &block
		params[:http_handler] ||= params[:handler] ||= block
		params[:handler] = Base::HTTPHandler
		params[:timeout] ||= 5
		GReactor.listen params
	end

	# Defers any missing methods to the GReactor Library.
	def method_missing name, *args, &block
		return super unless REACTOR_METHODS.include? name
		GReactor.send name, *args, &block
	end
	# Defers any missing methods to the GReactor Library.
	def respond_to_missing?(name, include_private = false)
		REACTOR_METHODS.include?(name) or super
	end

	protected

	REACTOR_METHODS = GReactor.public_methods(false)
end
