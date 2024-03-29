module GRHttp

	# This class is the part of the GRHttp server.
	# The request object is a Hash and the Request provides
	# simple shortcuts and access to the request's Hash data.
	#
	#
	# An HTTP Request
	class Request < Hash

		def initialize io = nil
			super()
			self[:io] = io if io
			self[:cookies] = Base::Cookies.new
			self[:params] = {}
		end

		public

		# the request's headers
		def headers
			self.select {|k,v| k.is_a? String }
		end
		# the request's method (GET, POST... etc').
		def request_method
			self[:method]
		end
		# set request's method (GET, POST... etc').
		def request_method= value
			self[:method] = value
		end
		# the parameters sent by the client.
		def params
			self[:params]
		end
		# the cookies sent by the client.
		def cookies
			self[:cookies]
		end

		# the query string
		def query
			self[:query]
		end

		# the original (frozen) path (resource requested).
		def original_path
			self[:original_path]
		end

		# the requested path (rewritable).
		def path
			self[:path]
		end
		def path=(new_path)
			self[:path] = new_path
		end

		# The HTTP version for this request
		def version
			self[:version]
		end

		# the base url ([http/https]://host[:port])
		def base_url switch_scheme = nil
			"#{switch_protocol || self[:scheme]}://#{self[:host_name]}#{self[:port]? ":#{self[:port]}" : ''}"
		end

		# the request's url, without any GET parameters ([http/https]://host[:port]/path)
		def request_url switch_scheme = nil
			"#{base_url switch_protocol}#{self[:original_path]}"
		end

		# the protocol's scheme (http/https/ws/wss) managing this request
		def scheme
			self[:scheme]
		end

		# @return [true, false] returns true if the requested was an SSL protocol (true also if the connection is clear-text behind an SSL Proxy, such as with some PaaS providers).
		def ssl?
			io.ssl? || self[:scheme] == 'https'.freeze || self[:scheme] == 'wss'.freeze
		end
		alias :secure? :ssl?

		# @return [BasicIO, SSLBasicIO] the io used for the request.
		def io
			self[:io]			
		end

		# method recognition

		HTTP_GET = 'GET'.freeze
		# returns true of the method == GET
		def get?
			self[:method] == HTTP_GET
		end

		HTTP_HEAD = 'HEAD'.freeze
		# returns true of the method == HEAD
		def head?
			self[:method] == HTTP_HEAD
		end
		HTTP_POST = 'POST'.freeze
		# returns true of the method == POST
		def post?
			self[:method] == HTTP_POST
		end
		HTTP_PUT = 'PUT'.freeze
		# returns true of the method == PUT
		def put?
			self[:method] == HTTP_PUT
		end
		HTTP_DELETE = 'DELETE'.freeze
		# returns true of the method == DELETE
		def delete?
			self[:method] == HTTP_DELETE
		end
		HTTP_TRACE = 'TRACE'.freeze
		# returns true of the method == TRACE
		def trace?
			self[:method] == HTTP_TRACE
		end
		HTTP_OPTIONS = 'OPTIONS'.freeze
		# returns true of the method == OPTIONS
		def options?
			self[:method] == HTTP_OPTIONS
		end
		HTTP_CONNECT = 'CONNECT'.freeze
		# returns true of the method == CONNECT
		def connect?
			self[:method] == HTTP_CONNECT
		end
		HTTP_PATCH = 'PATCH'.freeze
		# returns true of the method == PATCH
		def patch?
			self[:method] == HTTP_PATCH
		end
		HTTP_CTYPE = 'content-type'.freeze; HTTP_JSON = /application\/json/
		# returns true if the request is of type JSON.
		def json?
			self[HTTP_CTYPE] =~ HTTP_JSON
		end
		HTTP_XML = /text\/xml/
		# returns true if the request is of type XML.
		def xml?
			self[HTTP_CTYPE].match HTTP_XML
		end
		# returns true if this is a websocket upgrade request
		def websocket?
			@is_websocket ||= (self['upgrade'.freeze] && self['upgrade'.freeze].to_s =~ /websocket/i.freeze &&  self['connection'.freeze].to_s =~ /upg/i.freeze && true)
		end
		alias :upgrade? :websocket?
	end
end
