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
		params[:http_handler] ||= params[:handler] ||= block
		params[:upgrade_handler] ||= params[:handler]
		params[:handler] = Base::HTTPHandler
		params[:timeout] ||= 5
		GReactor.listen params
	end

	# Connects to a websocket as a websocket client and returns the connected client object or raises an exception.
	#
	# The method will block until eaither a connection is established or the timeout (defaults to 5 seconds) had been reached.
	#
	# It's possible to use this method within a {http://www.rubydoc.info/github/boazsegev/GReactor/master/GReactor#run_async-class_method GReactor.run_async} for asynchronous handling.
	#
	# this is actually a shortcut for {GRHttp::WSClient.connect}.
	def ws_connect url, options={}, &block
		GRHttp::WSClient.connect url, options={}, &block
	end

	# Registers a websocket extension to be used by GRHttp when receiving a websocket connection.
	#
	# This method accepts:
	# name:: the name of the websocket extension - this should be a String instance the euqals the IANA registered extention name. i.e. 'permessage-deflate'.
	# connection_handler:: An object that answers to `call(array)` that will recieve an Array of all the extension's settings requested by the client (could be empty) and return an extention object that answers the methods `parse(parser_hash)` and `edit(string)`. i.e. `-> {|args| MyExtention.new(args) if MyExtention.supports?(args)}
	#
	# Extension objects should answer the methods:
	# parse(parser_hash):: accepts a message parser hash which includes the :rsv1, :rsv2, :rsv3 and :body keys (and values). :rsvX values are `true` or `false`. :body is the unmasked string of the current frame. :message is the string of all the _prior_ messages in the frame's group (excluding :body). :fin states whether or not this is the final frame in it's frame group. The method is expected to edit the data in the hash in case an edit is required. The return value is ignored.
	# edit_message(buffer):: accepts the whole message buffer (String) being sent (UTF-8 encoding indicated the message is text, otherwise the message will be sent as binary data). The method is expected to edit the string in place (i.e. `str.clear; str << 'new data') and return the extension flag for a Binary OR operation (i.e. (0b1 << 6) == :rsv1).
	# edit_farme(buffer):: accepts one frame's buffer (String) being sent (UTF-8 encoding indicated the frame is text, otherwise the message will be sent as binary data). The method is expected to edit the buffer in place (i.e. `str.clear; str << 'new data') and return the extension flag for a Binary OR operation (i.e. (0b1 << 6) == :rsv1).
	#
	# `edit_message` and `edit_farme` MUST return a Fixnum object. They should return 0 if no flag is set.
	# Extension objects are expected to preserve state. In example, they should store the settings requested by the client and passed to the connection_handler.
	def register_ws_extention name, handler
		GRHttp::Base::WSHandler::SUPPORTED_EXTENTIONS[name] = handler
	end
	# Returns the extention's handler if it exists. Otherwise returns nil.
	def get_ws_extention name
		GRHttp::Base::WSHandler::SUPPORTED_EXTENTIONS[name]
	end
	# Deletes and returns the extention's handler if it exists. Otherwise returns nil.
	def remove_ws_extention name
		GRHttp::Base::WSHandler::SUPPORTED_EXTENTIONS.delete name
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

	# Returns the server's session's token name
	def session_token
		@session_token ||= SecureRandom.uuid
	end
	# Sets the server's session's token name
	def session_token= value
		@session_token = value
	end

	protected

	REACTOR_METHODS = GReactor.public_methods(false)
end
