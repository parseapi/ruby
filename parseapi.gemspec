require_relative 'lib/parseapi/version'

Gem::Specification.new do |spec|
	spec.name = 'parseapi'
	spec.version = ParseAPI::VERSION
	spec.authors = ['ParseAPI']
	spec.email = ['hello@parseapi.com']

	spec.summary = 'Official ParseAPI client for Ruby. One key, minimal JSON, fast.'
	spec.homepage = 'https://parseapi.com'
	spec.license = 'MIT'
	spec.required_ruby_version = '>= 3.0'

	spec.metadata['homepage_uri'] = spec.homepage
	spec.metadata['source_code_uri'] = 'https://github.com/parseapi/ruby'
	spec.metadata['documentation_uri'] = 'https://parseapi.com/docs'

	spec.files = Dir['lib/**/*.rb'] + ['README.md', 'LICENSE']
	spec.require_paths = ['lib']
end
