require_relative 'parseapi/version'
require_relative 'parseapi/client'

# Official ParseAPI client for Ruby.
#
#   parse = ParseAPI.new('your-api-key')
#   parse.country('US')
module ParseAPI
	# Sugar so `ParseAPI.new` builds a Client.
	def self.new(api_key = nil, **options)
		Client.new(api_key, **options)
	end
end
