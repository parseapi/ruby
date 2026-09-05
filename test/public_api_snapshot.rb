require_relative '../lib/parseapi'

# The checked-in manifest makes public argument names part of release review.
module PublicAPISnapshot
	def self.capture
		result = { 'ParseAPI.new' => ParseAPI.method(:new).parameters.map { |pair| pair.map(&:to_s) } }
		[ParseAPI::Client, ParseAPI::Error].each do |type|
			names = (type.public_instance_methods(false) + [:initialize]).uniq.sort
			result[type.name] = names.to_h do |name|
				[name.to_s, type.instance_method(name).parameters.map { |pair| pair.map(&:to_s) }]
			end
		end
		result
	end
end
