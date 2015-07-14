module GRHttp

	# extend GReactor

	module_function

	def listen params = {}, &block
		params[:http_handler] ||= params[:handler] ||= block
		params[:handler] = Base::HTTPHandler
		params[:timeout] ||= 5
		GReactor.listen params
	end

	def method_missing name, *args, &block
		return super unless REACTOR_METHODS.include? name
		GReactor.send name, *args, &block
	end
	def respond_to_missing?(name, include_private = false)
		REACTOR_METHODS.include?(name) or super
	end

	protected

	REACTOR_METHODS = GReactor.public_methods(false)
end
