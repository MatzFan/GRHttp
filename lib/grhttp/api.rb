module GRHttp

	# extend GReactor

	module_function

	# Opens a web-service (HTTP and Websocket) on the specified port.
	#
	# Accepts a parameter Hash and an optional block.
	#
	# The following parameters are recognized:
	# port:: The port number to listen to. Defaults to 3000 and increments by 1 with every portless listen call (3000, 3001, 3002...).
	# timeout:: The timeout for the connection (Keep-Alive HTTP/1.1 is the default behavior). Defaults to 5 seconds.
	# http_handler:: The object that will handle the connection. Should answer to `#call request, response`.
	# upgrade_handler:: The object that will handle WebSocket upgrade requests. Should answer to `#call request, response`, should return the new WebSocket Handler while setting any cookies for the response or false (ro refuse the request).
	# handler:: A unified handler. Sets both http_handler and upgrade_handler to the value of handler unless they are specifically set.
	# ssl:: Set this parameter to true to listen and react to SSL connections with a self signed certificate.
	# ssl_key + ssl_cert:: Set both these parameters to listen to an SSL connection with a registered certificate. Falls back to a self registered certificate if one of the two is missing.
	#
	#
	def listen params = {}, &block
		@listeners ||= {}
		params[:http_handler] ||= params[:handler] ||= block
		params[:upgrade_handler] ||= params[:handler]
		params[:handler] = Base::HTTPHandler
		params[:timeout] ||= 5
		GReactor.listen params
		@listeners[params[:port]] = params
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

	# Sets the message byte size limit for a Websocket message. Defaults to 0 (no limit)
	#
	# Although memory will be allocated for the latest TCP/IP frame,
	# this allows the websocket to disconnect if the incoming expected message size exceeds the allowed maximum size.
	#
	# If the sessage size limit is exceeded, the disconnection will be immidiate as an attack will be assumed. The protocol's normal disconnect sequesnce will be discarded.
	def ws_message_size_limit=val
		Base::WSHandler.message_size_limit = val
	end
	# Gets the message byte size limit for a Websocket message. Defaults to 0 (no limit)
	def ws_message_size_limit
		Base::WSHandler.message_size_limit
	end

	protected

	REACTOR_METHODS = GReactor.public_methods(false)
end
