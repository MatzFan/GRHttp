module GRHttp
	def Base
		def SessionManager
			def get id
				storage.fetch(id) || (storage.store(id, {}))
			end
			def store id
				storage.store id
			end
			# Sets the session storage object, to allow for different storage systems.
			#
			# A Session Storage object must answer only two methods:
			# fetch(id):: returns a Hash like session object with all the session's data.
			# store(id):: stores the session object, with all it's data AND returns the same session object.
			def storage= session_storage
				@storage = session_storage
			end
			def storage
				@storage ||= {}
			end
		end
	end
end
# A hash like interface for storing request session data.
# The store must implement: store(key, value) (aliased as []=);
# fetch(key, default = nil) (aliased as []);
# delete(key); clear;
