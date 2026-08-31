require 'json'
require 'net/http'
require 'uri'

module ParseAPI
	# Every non-2xx response from the API. Branch on +code+, never on the message.
	class Error < StandardError
		attr_reader :status, :code, :docs, :request_id

		def initialize(status:, code:, message:, docs: nil, request_id: nil)
			super(message)
			@status = status
			@code = code
			@docs = docs
			@request_id = request_id
		end
	end

	class Client
		DEFAULT_BASE_URL = 'https://api.parseapi.com'.freeze
		DEFAULT_TIMEOUT = 10
		DEFAULT_RETRIES = 2
		RETRY_STATUS = [429, 500, 502, 503, 504].freeze
		RETRY_AFTER_CAP = 5.0
		NETWORK_ERRORS = [
			Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ETIMEDOUT,
			Net::OpenTimeout, Net::ReadTimeout, IOError, EOFError, SocketError
		].freeze

		def initialize(api_key = nil, base_url: nil, timeout: nil, retries: nil)
			@api_key = api_key || ENV['PARSEAPI_KEY']
			raise ArgumentError, 'parseapi: missing API key. Pass one or set PARSEAPI_KEY.' if @api_key.nil? || @api_key.empty?

			@base_url = URI((base_url || ENV['PARSEAPI_BASE_URL'] || DEFAULT_BASE_URL).sub(%r{/+\z}, ''))
			@timeout = timeout || DEFAULT_TIMEOUT
			@retries = retries || DEFAULT_RETRIES
			@http = nil
		end

		# --- Lookup methods (one per endpoint, named after the route) ---

		def ip(ip, deep: false)
			get("/ip/#{seg(ip)}", deep: deep)
		end

		def ip_self(deep: false)
			get('/ip', deep: deep)
		end

		def continent(code)
			get("/continent/#{seg(code)}")
		end

		def continent_countries(code)
			get("/continent/#{seg(code)}/countries")
		end

		def bloc(code)
			get("/bloc/#{seg(code)}")
		end

		def bloc_countries(code)
			get("/bloc/#{seg(code)}/countries")
		end

		def country(code)
			get("/country/#{seg(code)}")
		end

		def country_states(code)
			get("/country/#{seg(code)}/states")
		end

		def state(code, country: nil)
			get("/state/#{seg(code)}", country: country)
		end

		def state_districts(code, country: nil)
			get("/state/#{seg(code)}/districts", country: country)
		end

		def district(code, country: nil, state: nil)
			get("/district/#{seg(code)}", country: country, state: state)
		end

		def city(name, country: nil, state: nil)
			get("/city/#{seg(name)}", country: country, state: state)
		end

		def city_id(id)
			get("/city/id/#{seg(id)}")
		end

		def city_search(q, country: nil, state: nil, limit: nil)
			get('/city', q: q, country: country, state: state, limit: limit)
		end

		def city_nearest(lat, lon)
			get('/city', lat: lat, lon: lon)
		end

		def city_nearby(name, radius: nil, unit: nil, country: nil, state: nil, limit: nil)
			get("/city/#{seg(name)}/nearby", radius: radius, unit: unit, country: country, state: state, limit: limit)
		end

		def postal(code, country: nil)
			get("/postal/#{seg(code)}", country: country)
		end

		def postal_nearby(code, country: nil, radius: nil, unit: nil)
			get("/postal/#{seg(code)}/nearby", country: country, radius: radius, unit: unit)
		end

		def postal_distance(from, to, country: nil)
			get("/postal/#{seg(from)}/distance/#{seg(to)}", country: country)
		end

		def email(email, deep: false)
			get("/email/#{seg(email)}", deep: deep)
		end

		def vat(number, country: nil, deep: false, from: nil)
			get("/vat/#{seg(number)}", country: country, deep: deep, from: from)
		end

		def iban(iban, country: nil)
			get("/iban/#{seg(iban)}", country: country)
		end

		def phone(number, country: nil, deep: false)
			get("/phone/#{seg(number)}", country: country, deep: deep)
		end

		def carrier(number, country: nil)
			get("/carrier/#{seg(number)}", country: country)
		end

		def caller(number, country: nil)
			get("/caller/#{seg(number)}", country: country)
		end

		def hlr(number, country: nil)
			get("/hlr/#{seg(number)}", country: country)
		end

		def domain(domain, deep: false)
			get("/domain/#{seg(domain)}", deep: deep)
		end

		def mx(domain)
			get("/mx/#{seg(domain)}")
		end

		def useragent(ua, deep: false)
			get('/useragent', { deep: deep }, { 'User-Agent' => ua })
		end

		def currency(code)
			get("/currency/#{seg(code)}")
		end

		def currency_rate(base, quote, date: nil, amount: nil)
			get("/currency/#{seg(base)}/#{seg(quote)}", date: date, amount: amount)
		end

		def language(code)
			get("/language/#{seg(code)}")
		end

		def name(name)
			get("/name/#{seg(name)}")
		end

		def timezone(id, at: nil)
			get("/timezone/#{seg(id)}", at: at)
		end

		def holiday(country, year: nil)
			get("/holiday/#{seg(country)}", year: year)
		end

		def holiday_date(country, date)
			get("/holiday/#{seg(country)}/#{seg(date)}")
		end

		def elevation(lat, lon)
			get('/elevation', lat: lat, lon: lon)
		end

		def point(lat, lon, deep: false)
			get('/point', lat: lat, lon: lon, deep: deep)
		end

		def weather(lat, lon, deep: false)
			get('/weather', lat: lat, lon: lon, deep: deep)
		end

		def emoji(emoji)
			get("/emoji/#{seg(emoji)}")
		end

		def emoji_search(q, limit: nil)
			get('/emoji', q: q, limit: limit)
		end

		private

		def seg(value)
			URI.encode_www_form_component(value.to_s).gsub('+', '%20')
		end

		def get(path, params = {}, headers = {})
			query = params.reject { |_name, value| value.nil? || value == false }
			uri = @base_url.dup
			uri.path = path
			uri.query = URI.encode_www_form(query) unless query.empty?

			attempt = 0
			loop do
				begin
					status, response_headers, body = execute(uri, request_headers(headers))
				rescue *NETWORK_ERRORS
					raise if attempt >= @retries

					sleep(retry_delay(attempt, nil))
					attempt += 1
					next
				end

				return JSON.parse(body) if (200..299).cover?(status)

				if RETRY_STATUS.include?(status) && attempt < @retries
					sleep(retry_delay(attempt, response_headers['retry-after']))
					attempt += 1
					next
				end

				raise build_error(status, body)
			end
		end

		def request_headers(extra)
			{ 'X-API-Key' => @api_key, 'User-Agent' => "parseapi-ruby/#{VERSION}" }.merge(extra)
		end

		# Returns [status, headers_hash, body_string]. Overridden in tests.
		def execute(uri, headers)
			http = connection
			request = Net::HTTP::Get.new(uri.request_uri)
			headers.each { |name, value| request[name] = value }
			response = http.request(request)
			header_hash = {}
			response.each_header { |name, value| header_hash[name.downcase] = value }
			[response.code.to_i, header_hash, response.body || '']
		end

		def connection
			if @http.nil?
				@http = Net::HTTP.new(@base_url.host, @base_url.port)
				@http.use_ssl = @base_url.scheme == 'https'
				@http.open_timeout = @timeout
				@http.read_timeout = @timeout
				@http.keep_alive_timeout = 30
			end
			@http.start unless @http.started?
			@http
		end

		def retry_delay(attempt, retry_after)
			if retry_after
				seconds = Float(retry_after, exception: false)
				return [seconds, RETRY_AFTER_CAP].min if seconds && seconds >= 0
			end
			rand * 0.25 * (2**attempt)
		end

		def build_error(status, body)
			parsed = begin
				JSON.parse(body)
			rescue JSON::ParserError
				{}
			end
			parsed = {} unless parsed.is_a?(Hash)
			Error.new(
				status: status,
				code: parsed['code'].is_a?(String) ? parsed['code'] : 'unknown_error',
				message: parsed['message'].is_a?(String) ? parsed['message'] : "Request failed with status #{status}",
				docs: parsed['docs'].is_a?(String) ? parsed['docs'] : nil,
				request_id: parsed['request_id'].is_a?(String) ? parsed['request_id'] : nil
			)
		end
	end
end
