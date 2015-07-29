module GRHttp
	module Base
		class SessionStorage < Hash
			def fetch key
				return super if has_key?(key)
				store key, {}
			end
		end
	end
	module SessionManager
		module_function
		# returns a session object
		def get id
			storage.fetch(id)
		end
		# stores a session object
		def store id, session_object
			storage.store id, session_object
		end
		# Sets the session storage object, to allow for different storage systems.
		#
		# A Session Storage object must answer only two methods:
		# fetch(id):: returns a Hash like session object with all the session's data or a fresh session object if the session object did not exist before
		# store(id):: stores the session object, with all it's data AND returns the same session object.
		def storage= session_storage
			@storage = session_storage
		end
		def storage
			@storage ||= GRHttp::Base::SessionStorage.new
		end
	end
end
# A hash like interface for storing request session data.
# The store must implement: store(key, value) (aliased as []=);
# fetch(key, default = nil) (aliased as []);
# delete(key); clear;
