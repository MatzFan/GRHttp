# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'grhttp/version'

Gem::Specification.new do |spec|
  spec.name          = "grhttp"
  spec.version       = GRHttp::VERSION
  spec.authors       = ["Boaz Segev"]
  spec.email         = ["boaz@2be.co.il"]

  spec.summary       = %q{A native Ruby generic HTTP and WebSocket server (uses the GReactor library).}
  spec.description   = %q{A native Ruby generic HTTP and WebSocket server (uses the GReactor library).}
  spec.homepage      = "https://github.com/boazsegev/HTTP-WS-GR/"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org by setting 'allowed_push_host', or
  # delete this section to allow pushing this gem to any host.
  # if spec.respond_to?(:metadata)
  #   spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  # else
  #   raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  # end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.10"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_dependency "greactor", "~> 0.0.5"
end
