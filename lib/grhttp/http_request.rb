module GRHttp

	# This class is the part of the GRHttp server.
	# The request object is a Hash and the HTTPRequest provides
	# simple shortcuts and access to the request' Hash data.
	#
	#
	class HTTPRequest < Hash

		def initialize io = nil
			super()
			self[:io] = io if io
			self[:cookies] = Cookies.new
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

		# the base url ([http/https]://host[:port])
		def base_url switch_protocol = nil
			"#{switch_protocol || self[:requested_protocol]}://#{self[:host_name]}#{self[:port]? ":#{self[:port]}" : ''}"
		end

		# the request's url, without any GET parameters ([http/https]://host[:port]/path)
		def request_url switch_protocol = nil
			"#{base_url switch_protocol}#{self[:original_path]}"
		end

		# the protocol managing this request
		def protocol
			self[:requested_protocol]
		end

		# the io used for the request.
		def io
			self[:io]			
		end

		# method recognition

		# returns true of the method == GET
		def get?
			self[:method] == 'GET'
		end
		# returns true of the method == HEAD
		def head?
			self[:method] == 'HEAD'
		end
		# returns true of the method == POST
		def post?
			self[:method] == 'POST'
		end
		# returns true of the method == PUT
		def put?
			self[:method] == 'PUT'
		end
		# returns true of the method == DELETE
		def delete?
			self[:method] == 'DELETE'
		end
		# returns true of the method == TRACE
		def trace?
			self[:method] == 'TRACE'
		end
		# returns true of the method == OPTIONS
		def options?
			self[:method] == 'OPTIONS'
		end
		# returns true of the method == CONNECT
		def connect?
			self[:method] == 'CONNECT'
		end
		# returns true of the method == PATCH
		def patch?
			self[:method] == 'PATCH'
		end
		# returns true if the request is of type JSON.
		def json?
			self['content-type'].match /application\/json/
		end
		# returns true if the request is of type XML.
		def xml?
			self['content-type'].match /text\/xml/
		end
		# returns true if this is a websocket upgrade request
		def upgrade?
			self['upgrade'] && self['upgrade'].to_s.downcase == 'websocket' &&  self['connection'].to_s.downcase == 'upgrade'
		end

	end
end
