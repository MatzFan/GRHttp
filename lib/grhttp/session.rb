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
		# Sets the session storage object, to allow for different storage systems.
		#
		# A Session Storage object must answer only one methods:
		# fetch(id):: returns a Hash like session object with all the session's data or a fresh session object if the session object did not exist before
		#
		# The Session Object should update itself in the storage whenever data is saved to the session Object.
		# This is important also because websocket 'session' could exist simultaneously with other HTTP requests and the data should be kept updated at all times.
		# If there are race conditions that apply for multi-threading / multi processing, the Session Object should manage them as well as possible.
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
