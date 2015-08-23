require 'time'
require 'json'
require 'yaml'
require 'uri'
require 'securerandom'
require 'stringio'
require 'tmpdir'
require 'zlib'

require 'greactor'

require "grhttp/version"

require "grhttp/http_base"

require "grhttp/http1"

require "grhttp/hpack"
require "grhttp/http2"

require "grhttp/session"


require "grhttp/ws_handler"
require "grhttp/ws_event"
require "grhttp/ws_client"

require "grhttp/request"
require "grhttp/response"

require "grhttp/api"

require "grhttp/rack_support"

require "grhttp/extensions/permessage_deflate"

# please read the {file:README.md} file for an introduction to GRHttp.
#
# here's the famous Hello World to get you thinking:
#
#       require 'grhttp'
#
#       GRHttp.start {   GRHttp.listen {|request, response| 'Hello World!' }      }
#
module GRHttp
	# using GReactor

  # Your code goes here...
end
