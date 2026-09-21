require 'json'
require 'net/http'
require 'uri'
require 'time'

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
		API_VERSION = '2.0.0'.freeze
		private_constant :API_VERSION
		DEFAULT_BASE_URL = 'https://api.parseapi.com'.freeze
		DEFAULT_TIMEOUT = 10
		DEFAULT_RETRIES = 2
		RETRY_STATUS = [429, 500, 502, 503, 504].freeze
		RETRY_AFTER_CAP = 5.0
		METERED_CORE = %w[carrier caller hlr litigator reassigned].freeze
		NETWORK_ERRORS = [
			Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ETIMEDOUT,
			Net::OpenTimeout, Net::ReadTimeout, IOError, EOFError, SocketError
		].freeze

		def initialize(api_key = nil, base_url: nil, timeout: nil, retries: nil, transport: nil)
			# You found Dev. https://parseapi.com/dev
			@api_key = api_key || ENV['PARSEAPI_KEY']
			raise ArgumentError, 'parseapi: missing API key. Pass one or set PARSEAPI_KEY.' if @api_key.nil? || @api_key.empty?

			@base_url = URI((base_url || ENV['PARSEAPI_BASE_URL'] || DEFAULT_BASE_URL).sub(%r{/+\z}, ''))
			@timeout = timeout || DEFAULT_TIMEOUT
			@timeout_explicit = !timeout.nil?
			@retries = retries
			raise ArgumentError, 'parseapi: timeout must be a finite positive number.' unless @timeout.is_a?(Numeric) && @timeout.finite? && @timeout > 0
			raise ArgumentError, 'parseapi: retries must be a non-negative integer or nil.' unless @retries.nil? || (@retries.is_a?(Integer) && @retries >= 0)
			raise ArgumentError, 'parseapi: transport must be callable.' unless transport.nil? || transport.respond_to?(:call)
			@transport = transport
			@http = nil
		end

		# Release the connection. A later lookup opens a new one.
		def close
			@http.finish if @http&.started?
			@http = nil
			nil
		end

		def inspect
			"#<#{self.class} api_key=[REDACTED] timeout=#{@timeout} retries=#{@retries.nil? ? 'auto' : @retries}>"
		end


		# Look up an IP. Deep enrichment is included with a paid plan, without a separate check meter.
		def ip(ip, deep: false, lang: nil)
			get("/ip/#{seg(ip)}", deep: deep, lang: lang)
		end

		# Look up the public IP making this request. On a server, this is the server's IP.
		def ip_self(deep: false, lang: nil)
			get('/ip', deep: deep, lang: lang)
		end

		def continent(code, lang: nil)
			get("/continent/#{seg(code)}", lang: lang)
		end

		def continent_countries(code, lang: nil)
			get("/continent/#{seg(code)}/countries", lang: lang)
		end

		def bloc(code)
			get("/bloc/#{seg(code)}")
		end

		def bloc_countries(code, lang: nil)
			get("/bloc/#{seg(code)}/countries", lang: lang)
		end

		def country(code, deep: false, lang: nil)
			get("/country/#{seg(code)}", deep: deep, lang: lang)
		end

		def country_states(code, lang: nil)
			get("/country/#{seg(code)}/states", lang: lang)
		end

		def state(code, country: nil, deep: false, lang: nil)
			get("/state/#{seg(code)}", country: country, deep: deep, lang: lang)
		end

		def state_districts(code, country: nil, deep: false, lang: nil)
			get("/state/#{seg(code)}/districts", country: country, deep: deep, lang: lang)
		end

		def district(code, country: nil, state: nil, deep: false, lang: nil)
			get("/district/#{seg(code)}", country: country, state: state, deep: deep, lang: lang)
		end

		def city(name, country: nil, state: nil, deep: false, lang: nil)
			get("/city/#{seg(name)}", country: country, state: state, deep: deep, lang: lang)
		end

		def city_id(id, deep: false, lang: nil)
			get("/city/id/#{seg(id)}", deep: deep, lang: lang)
		end

		def city_search(query, country: nil, state: nil, limit: nil, deep: false, lang: nil)
			get('/city', q: query, country: country, state: state, limit: limit, deep: deep, lang: lang)
		end

		def city_nearest(lat, lon, deep: false, lang: nil)
			get('/city', lat: lat, lon: lon, deep: deep, lang: lang)
		end

		def city_nearby(name, radius: nil, unit: nil, country: nil, state: nil, limit: nil, deep: false, lang: nil)
			get("/city/#{seg(name)}/nearby", radius: radius, unit: unit, country: country, state: state, limit: limit, deep: deep, lang: lang)
		end

		# Look up a postal area. Pass country when known. Check nullable coordinates before another
		# location lookup.
		def postal(code, country: nil, deep: false, lang: nil)
			get("/postal/#{seg(code)}", country: country, deep: deep, lang: lang)
		end

		def postal_nearby(code, country: nil, radius: nil, unit: nil, deep: false, lang: nil)
			get("/postal/#{seg(code)}/nearby", country: country, radius: radius, unit: unit, deep: deep, lang: lang)
		end

		def postal_distance(from, to, country: nil, deep: false, lang: nil)
			get("/postal/#{seg(from)}/distance/#{seg(to)}", country: country, deep: deep, lang: lang)
		end

		def address(address, country: nil, deep: false)
			get("/address/#{seg(address)}", country: country, deep: deep)
		end

		# Find address suggestions using the context supplied. Prefer postal, or city and state, from
		# the form; ip is an optional end-user locality hint for server-side calls. An empty result has
		# reason more_input, missing_context or no_matches. Suggestions have reason null. Operational
		# failures are errors.
		def address_search(query, country: nil, postal: nil, city: nil, state: nil, ip: nil)
			get('/address', q: query, country: country, postal: postal, city: city, state: state, ip: ip)
		end

		def company(number, country: nil, deep: false, lang: nil)
			get("/company/#{seg(number)}", country: country, deep: deep, lang: lang)
		end

		# Parse an email and check its format and domain. Deep explicitly requests a metered
		# deliverability check. Deep checks use one attempt by default. An explicit retry count can
		# repeat paid usage.
		def email(email, deep: false)
			get("/email/#{seg(email)}", deep: deep)
		end

		# Check VAT format and checksum. Deep requests a metered registry check where supported. Deep
		# checks use one attempt by default. Supply your own VAT number for a consultation reference
		# when supported.
		def vat(number, country: nil, deep: false, from: nil)
			get("/vat/#{seg(number)}", country: country, deep: deep, from: from)
		end

		def iban(iban, country: nil, deep: false)
			get("/iban/#{seg(iban)}", country: country, deep: deep)
		end

		# Look up a 6-11 digit card prefix, preserving leading zeros.
		def bin(bin, deep: false)
			get("/bin/#{seg(bin)}", deep: deep)
		end


		def npi(npi, deep: false, lang: nil)
			get("/npi/#{seg(npi)}", deep: deep, lang: lang)
		end

		# Parse a phone number and its formats. Pass country for national numbers when needed. Deep
		# adds numbering-plan geography on every plan. Carrier, caller, and HLR are separate metered lookups.
		def phone(number, country: nil, deep: false)
			get("/phone/#{seg(number)}", country: country, deep: deep)
		end

		# Request a metered carrier lookup. No automatic retries by default.
		def carrier(number, country: nil, deep: false)
			get("/carrier/#{seg(number)}", country: country, deep: deep)
		end

		# Request a metered caller-name lookup for a NANP number. No automatic retries by default.
		def caller(number, country: nil)
			get("/caller/#{seg(number)}", country: country)
		end

		# Look up phone status at the last check. Live means assigned and connected means reachable at
		# that check. Cached results may be returned. Null means unconfirmed. Deep adds network
		# diagnostics within the same metered lookup. No automatic retries by default.
		def hlr(number, country: nil, deep: false)
			get("/hlr/#{seg(number)}", country: country, deep: deep)
		end

		# Identify website technologies and versions by category.
		# All categories are lists. Scope, pages and partial describe bounded coverage.
		# Lists are nil when no page could be checked and empty for no matches.
		def stack(domain, deep: false, pretty: false)
			get("/stack/#{seg(domain)}", deep: deep, pretty: pretty)
		end

		# Check whether a domain is registered. Deep adds registration dates, registrar, status and DNSSEC on paid plans.
		def domain(domain, deep: false)
			get("/domain/#{seg(domain)}", deep: deep)
		end

		def asn(asn, lang: nil)
			get("/asn/#{seg(asn)}", lang: lang)
		end

		def mac(mac)
			get("/mac/#{seg(mac)}")
		end

		# Published DNS records with TTLs. Omit type to check all supported types.
		# Type selects the question, including its CNAME chain. Pooled on every plan.
		def dns(domain, type: nil)
			get("/dns/#{seg(domain)}", type: type)
		end

		def mx(domain)
			get("/mx/#{seg(domain)}")
		end

		def useragent(ua, deep: false)
			get('/useragent', { deep: deep }, { 'User-Agent' => ua })
		end

		def vin(vin, deep: false)
			get("/vin/#{seg(vin)}", deep: deep)
		end

		# US NAICS 2022 definition and hierarchy.
		def naics(code, deep: false)
			get("/naics/#{seg(code)}", deep: deep)
		end

		# Keyword search. Limit defaults to 10 and accepts 1-50.
		def naics_search(query, limit: nil, deep: false)
			get('/naics', q: query, limit: limit, deep: deep)
		end

		# Look up the general US duty schedule line. Paid deep adds units and the special and other
		# schedule columns. Add origin with deep to resolve country-specific measures. Without origin,
		# schedule detail remains available and origin-dependent fields are null. A null effective rate
		# is not a zero rate.
		def tariff(code, deep: false, origin: nil)
			get("/tariff/#{seg(code)}", deep: deep, origin: origin)
		end

		def tariff_search(query)
			get('/tariff', q: query)
		end

		def currency(code, deep: false, lang: nil)
			get("/currency/#{seg(code)}", deep: deep, lang: lang)
		end

		def currency_rate(base, quote, date: nil, amount: nil)
			get("/currency/#{seg(base)}/#{seg(quote)}", date: date, amount: amount)
		end

		def language(code, deep: false, lang: nil)
			get("/language/#{seg(code)}", deep: deep, lang: lang)
		end

		# Name locale selects CLDR formatting, default en, without changing parsing or gender context.
		def name(name, country: nil, deep: false, name_locale: nil)
			get("/name/#{seg(name)}", country: country, deep: deep, name_locale: name_locale)
		end

		# Current local time, UTC by default. With to, offsetless at is source wall time.
		def time(timezone = nil, at: nil, to: nil, deep: false, lang: nil)
			get(timezone.nil? ? '/time' : "/time/#{seg(timezone)}", at: at, to: to, deep: deep, lang: lang)
		end

		def time_at(lat, lon, at: nil, to: nil, deep: false, lang: nil)
			get('/time', lat: lat, lon: lon, at: at, to: to, deep: deep, lang: lang)
		end

		def timezone(id, at: nil, to: nil, deep: false, lang: nil)
			get("/timezone/#{seg(id)}", at: at, to: to, deep: deep, lang: lang)
		end

		def timezone_at(lat, lon, at: nil, deep: false, lang: nil)
			get('/timezone', lat: lat, lon: lon, at: at, deep: deep, lang: lang)
		end

		def date(date, format: nil, to: nil, deep: false, lang: nil)
			get("/date/#{seg(date)}", format: format, to: to, deep: deep, lang: lang)
		end

		def date_today(to: nil, deep: false, lang: nil)
			get('/date', to: to, deep: deep, lang: lang)
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

		# Resolve the country, state, district and timezone at coordinates. Deep adds terrain and
		# compact nearest-city context on every plan. The timezone ID stays in core. The nearest city is
		# null when none is within 200 km.
		def point(lat, lon, deep: false, lang: nil)
			get('/point', lat: lat, lon: lon, deep: deep, lang: lang)
		end

		# Get current conditions in metric and imperial units. Paid deep adds specialist current
		# measurements, forecasts and related detail. With deep, date selects a past UTC day (YYYY-MM-
		# DD) in deep.history alongside current conditions. Date alone does not request history.
		def weather(lat, lon, deep: false, date: nil)
			get('/weather', lat: lat, lon: lon, deep: deep, date: date)
		end

		def emoji(emoji, deep: false, lang: nil)
			get("/emoji/#{seg(emoji)}", deep: deep, lang: lang)
		end

		def emoji_search(query, limit: nil, deep: false, lang: nil)
			get('/emoji', q: query, limit: limit, deep: deep, lang: lang)
		end

		# Parse or convert a measurement. Amount is a decimal string. Without to, use the
		# type's canonical unit. Locale and system (us or imperial) resolve explicit ambiguity.
		def measure(measure, to: nil, locale: nil, system: nil)
			get("/measure/#{seg(measure)}", to: to, locale: locale, system: system)
		end

		# Discover reviewed units. unit filters compatible conversion targets.
		def measure_units(query: nil, type: nil, unit: nil, lang: nil)
			get('/measure/units', q: query, type: type, unit: unit, lang: lang)
		end

		private

		def seg(value)
			URI.encode_www_form_component(value.to_s).gsub('+', '%20')
		end

		def get(path, params = {}, headers = {})
			retries = retries_for(path, params)
			query = params.reject { |_name, value| value.nil? || value == false }
			uri = @base_url.dup
			uri.path = path
			uri.query = URI.encode_www_form(query) unless query.empty?

			attempt = 0
			loop do
				begin
					status, response_headers, body = execute(uri, request_headers(headers))
				rescue *NETWORK_ERRORS
					raise if attempt >= retries

					sleep(retry_delay(attempt, nil))
					attempt += 1
					next
				end

				return JSON.parse(body) if (200..299).cover?(status)

				if RETRY_STATUS.include?(status) && attempt < retries
					sleep(retry_delay(attempt, response_headers['retry-after']))
					attempt += 1
					next
				end

				raise build_error(status, body)
			end
		end

		def request_headers(extra)
			{ 'X-API-Key' => @api_key, 'User-Agent' => "parseapi-ruby/#{VERSION}" }.merge(extra).merge('Parse-Version' => API_VERSION)
		end

		# Returns [status, headers_hash, body_string]. Overridden in tests.
		def execute(uri, headers)
			return @transport.call(uri.to_s, headers) if @transport

			timeout = !@timeout_explicit && uri.path.start_with?('/stack/') ? 35 : @timeout
			http = connection(timeout)
			request = Net::HTTP::Get.new(uri.request_uri)
			headers.each { |name, value| request[name] = value }
			response = http.request(request)
			header_hash = {}
			response.each_header { |name, value| header_hash[name.downcase] = value }
			[response.code.to_i, header_hash, response.body || '']
		end

		def connection(timeout = @timeout)
			if @http.nil?
				@http = Net::HTTP.new(@base_url.host, @base_url.port)
				@http.use_ssl = @base_url.scheme == 'https'
				# The client owns retries, including retries: 0.
				@http.max_retries = 0
				@http.keep_alive_timeout = 30
			end
			@http.open_timeout = timeout
			@http.read_timeout = timeout
			@http.write_timeout = timeout
			@http.start unless @http.started?
			@http
		end

		def retry_delay(attempt, retry_after)
			if retry_after
				seconds = Float(retry_after, exception: false)
				return [seconds, RETRY_AFTER_CAP].min if seconds && seconds.finite? && seconds >= 0
				begin
					return [[Time.httpdate(retry_after) - Time.now, 0].max, RETRY_AFTER_CAP].min
				rescue ArgumentError
					# Fall back to jitter when the header is not a delay or HTTP date.
				end
			end
			rand * 0.25 * (2**attempt)
		end

		def retries_for(path, params)
			return @retries unless @retries.nil?

			product = path.split('/', 3)[1]
			metered = METERED_CORE.include?(product) || (%w[email vat address].include?(product) && params[:deep] == true)
			metered ? 0 : DEFAULT_RETRIES
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
