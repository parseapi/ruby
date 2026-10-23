require 'json'
require 'net/http'
require 'uri'
require 'time'

module ParseAPI
	# Every non-2xx response from the API. Branch on +code+, never on the message.
	class Error < StandardError
		attr_reader :status, :code, :docs, :request_id, :retry_after, :candidates

		def initialize(status:, code:, message:, docs: nil, request_id: nil, retry_after: nil)
			super(message)
			@status = status
			@code = code
			@docs = docs
			@request_id = request_id
			@retry_after = retry_after
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

		def city(name, country: nil, state: nil, deep: false, lang: nil, type: nil, grain: nil, hierarchy: false, aliases: false, ambiguity: nil, format: nil, romanized: false)
			get("/city/#{seg(name)}", country: country, state: state, deep: deep, lang: lang, type: type, grain: grain, hierarchy: hierarchy, aliases: aliases, ambiguity: ambiguity, romanized: romanized, format: format)
		end

		def city_id(id, deep: false, lang: nil, hierarchy: false, format: nil, romanized: false)
			get("/city/id/#{seg(id)}", deep: deep, lang: lang, hierarchy: hierarchy, romanized: romanized, format: format)
		end

		def city_search(query, country: nil, state: nil, limit: nil, deep: false, lang: nil, type: nil, grain: nil, hierarchy: false, aliases: false, min_population: nil, max_population: nil, timezone: nil, bbox: nil, sort: nil, order: nil, page: false, cursor: nil, format: nil, countries: nil, exclude_countries: nil, timezones: nil, min_elevation: nil, max_elevation: nil, match: nil, max_distance: nil, romanized: false)
			spelling = !match.nil? || !max_distance.nil?
			response = get(spelling ? '/city/search' : '/city', q: query, match: match, max_distance: max_distance, country: country, state: state, limit: limit, deep: deep, lang: lang, type: type, grain: grain, hierarchy: hierarchy, aliases: aliases, min_population: min_population, max_population: max_population, timezone: timezone, bbox: bbox, sort: sort, order: order, page: page, cursor: cursor, romanized: romanized, format: format, countries: city_csv(countries), exclude_countries: city_csv(exclude_countries), timezones: city_csv(timezones), min_elevation: min_elevation, max_elevation: max_elevation)
			if spelling && format.nil?
				classic = {"q"=>query, "cities"=>response.fetch("data"), "next_cursor"=>response["next_cursor"]}
				classic["country"] = country unless country.nil?
				classic["state"] = state unless state.nil?
				return classic
			end
			response
		end

		def city_nearest(lat, lon, deep: false, lang: nil, country: nil, state: nil, type: nil, grain: nil, hierarchy: false, format: nil, romanized: false)
			get('/city', lat: lat, lon: lon, deep: deep, lang: lang, country: country, state: state, type: type, grain: grain, hierarchy: hierarchy, romanized: romanized, format: format)
		end

		def city_nearby(name, radius: nil, unit: nil, country: nil, state: nil, limit: nil, deep: false, lang: nil, type: nil, grain: nil, hierarchy: false, aliases: false, ambiguity: nil, min_population: nil, max_population: nil, timezone: nil, bbox: nil, sort: nil, order: nil, page: false, cursor: nil, format: nil, countries: nil, exclude_countries: nil, timezones: nil, min_elevation: nil, max_elevation: nil, romanized: false)
			get("/city/#{seg(name)}/nearby", radius: radius, unit: unit, country: country, state: state, limit: limit, deep: deep, lang: lang, type: type, grain: grain, hierarchy: hierarchy, aliases: aliases, ambiguity: ambiguity, min_population: min_population, max_population: max_population, timezone: timezone, bbox: bbox, sort: sort, order: order, page: page, cursor: cursor, romanized: romanized, format: format, countries: city_csv(countries), exclude_countries: city_csv(exclude_countries), timezones: city_csv(timezones), min_elevation: min_elevation, max_elevation: max_elevation)
		end

		# Look up a postal area. Pass country when known. Check nullable coordinates before another
		# location lookup.
		def city_ancestors(id, hierarchy: false, deep: false, lang: nil, romanized: false)
			get("/city/id/#{seg(id)}/ancestors", romanized: romanized, hierarchy: hierarchy, deep: deep, lang: lang)
		end




		def city_children(id, limit: nil, cursor: nil, hierarchy: false, deep: false, lang: nil, romanized: false)
			get("/city/id/#{seg(id)}/children", limit: limit, cursor: cursor, romanized: romanized, hierarchy: hierarchy, deep: deep, lang: lang)
		end



		def city_distance(from, to)
			get("/city/id/#{seg(from)}/distance/#{seg(to)}")
		end


		def city_list(country: nil, state: nil, limit: nil, deep: false, lang: nil, type: nil, grain: nil, hierarchy: false, min_population: nil, max_population: nil, timezone: nil, bbox: nil, sort: nil, order: nil, cursor: nil, countries: nil, exclude_countries: nil, timezones: nil, min_elevation: nil, max_elevation: nil, romanized: false)
			get('/city', browse: true, country: country, state: state, limit: limit, deep: deep, lang: lang, type: type, grain: grain, hierarchy: hierarchy, min_population: min_population, max_population: max_population, timezone: timezone, bbox: bbox, sort: sort, order: order, cursor: cursor, romanized: romanized, format: 'list', countries: city_csv(countries), exclude_countries: city_csv(exclude_countries), timezones: city_csv(timezones), min_elevation: min_elevation, max_elevation: max_elevation)
		end


		def city_nearby_coords(lat, lon, radius: nil, unit: nil, country: nil, state: nil, limit: nil, deep: false, lang: nil, type: nil, grain: nil, hierarchy: false, min_population: nil, max_population: nil, timezone: nil, bbox: nil, sort: nil, order: nil, cursor: nil, countries: nil, exclude_countries: nil, timezones: nil, min_elevation: nil, max_elevation: nil, romanized: false)
			get('/city', lat: lat, lon: lon, nearby: true, radius: radius, unit: unit, country: country, state: state, limit: limit, deep: deep, lang: lang, type: type, grain: grain, hierarchy: hierarchy, min_population: min_population, max_population: max_population, timezone: timezone, bbox: bbox, sort: sort, order: order, cursor: cursor, romanized: romanized, format: 'list', countries: city_csv(countries), exclude_countries: city_csv(exclude_countries), timezones: city_csv(timezones), min_elevation: min_elevation, max_elevation: max_elevation)
		end


		def city_siblings(id, limit: nil, cursor: nil, hierarchy: false, deep: false, lang: nil, romanized: false)
			get("/city/id/#{seg(id)}/siblings", limit: limit, cursor: cursor, romanized: romanized, hierarchy: hierarchy, deep: deep, lang: lang)
		end


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

		# Fetch a directory profile by its stable Company ID.
		def company_id(id, deep: false)
			get("/company/id/#{seg(id)}", deep: deep)
		end

		# Use at most one selector, or discover by country, industry or selected registration. The API
		# validates filters; pair the four-digit industry string with industry_type: "sic". Pass a
		# returned cursor with the same selector and filters. Deep belongs to each result.
		def company_search(query: nil, domain: nil, ticker: nil, identifier: nil, country: nil, exchange: nil, authority: nil, limit: nil, cursor: nil, deep: false, industry: nil, industry_type: nil)
			get('/company', q: query, domain: domain, ticker: ticker, identifier: identifier, country: country, exchange: exchange, authority: authority, limit: limit, cursor: cursor, deep: deep, industry: industry, industry_type: industry_type)
		end

		# Read the directory edition and source coverage.
		def company_coverage
			get('/company/directory/coverage')
		end

		# Parse an email and check its format and domain. Deep explicitly requests a metered
		# deliverability check. Deep checks use one attempt by default. An explicit retry count can
		# repeat paid usage.
		def email(email, deep: false)
			get("/email/#{seg(email)}", deep: deep)
		end



		def bin(bin, deep: false)
			get("/bin/#{seg(bin)}", deep: deep)
		end



		# Look up a 2-11 digit card prefix, preserving leading zeros.
		def card(bin, deep: false)
			raise ArgumentError, 'parseapi: Card requires a 2-11 digit prefix string.' unless bin.is_a?(String) && bin.length <= 64 && /\A[0-9]{2,11}\z/.match?(bin.delete(" \t\r\n-"))
			get("/card/#{seg(bin)}", deep: deep)
		end		# Parse a phone number and its formats. Pass country for national numbers when needed. Deep
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

		# US NAICS 2022 definition and hierarchy.
		# Compatibility names for Industry.
		def naics(code, deep: false)
			industry(code, deep: deep)
		end

		def naics_search(query, limit: nil, deep: false)
			industry_search(query, limit: limit, deep: deep)
		end

		def industry(code, deep: false)
			get("/industry/#{seg(code)}", deep: deep)
		end

		# Keyword search. Limit defaults to 10 and accepts 1-50.
		def industry_search(query, limit: nil, deep: false)
			get('/industry', q: query, limit: limit, deep: deep)
		end



		def language(code, deep: false, lang: nil)
			get("/language/#{seg(code)}", deep: deep, lang: lang)
		end

		# Name locale selects CLDR formatting, default en, without changing parsing or gender context.
		def name(name, country: nil, deep: false, name_locale: nil)
			get("/name/#{seg(name)}", country: country, deep: deep, name_locale: name_locale)
		end

		# Current local time, UTC by default. With to or targets, offsetless at is source wall time.
		def time(timezone = nil, at: nil, to: nil, deep: false, lang: nil, disambiguation: nil, targets: nil, ip: nil, city: nil, country: nil, state: nil, iata: nil, icao: nil, unlocode: nil, address: nil)
			raise ArgumentError, 'Time source must be an IANA timezone ID. Use timezone discovery to list IDs.' if timezone && %w[zones help].include?(timezone.strip.downcase)
			source = time_source(timezone, ip: ip, city: city, country: country, state: state, iata: iata, icao: icao, unlocode: unlocode, address: address)
			get(timezone.nil? ? '/time' : "/time/#{seg(timezone)}", **source, at: at, to: to, deep: deep, lang: lang, disambiguation: disambiguation, targets: time_targets(targets, to))
		end

		def time_at(lat, lon, at: nil, to: nil, deep: false, lang: nil, disambiguation: nil, targets: nil)
			get('/time', lat: lat, lon: lon, at: at, to: to, deep: deep, lang: lang, disambiguation: disambiguation, targets: time_targets(targets, to))
		end

		def time_zones(query = nil, country: nil, area: nil, offset: nil, abbreviation: nil, dst: nil, observes_dst: nil, at: nil, details: false, sort: nil)
			get('/time/zones', q: query, country: country, area: area, offset: offset, abbreviation: abbreviation, dst: dst.nil? ? nil : dst.to_s, observes_dst: observes_dst.nil? ? nil : observes_dst.to_s, at: at, details: details, sort: sort)
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

		def emoji(emoji, deep: false, lang: nil, shortcode_source: nil)
			get("/emoji/#{seg(emoji)}", deep: deep, lang: lang, shortcode_source: shortcode_source)
		end

		def emoji_search(query, limit: nil, deep: false, lang: nil, category: nil, subcategory: nil, version: nil, max_version: nil, include_skin_tones: nil, offset: nil)
			get('/emoji', q: query, limit: limit, deep: deep, lang: lang, category: category, subcategory: subcategory, version: version, max_version: max_version, include_skin_tones: include_skin_tones.nil? ? nil : include_skin_tones.to_s, offset: offset)
		end

		def emoji_browse(limit: nil, deep: false, lang: nil, category: nil, subcategory: nil, version: nil, max_version: nil, include_skin_tones: nil, offset: nil)
			get('/emoji', limit: limit, deep: deep, lang: lang, category: category, subcategory: subcategory, version: version, max_version: max_version, include_skin_tones: include_skin_tones.nil? ? nil : include_skin_tones.to_s, offset: offset)
		end

		# Download the full filtered JSON catalog, including offline resolution maps.
		def emoji_catalog(deep: true, lang: nil, category: nil, subcategory: nil, version: nil, max_version: nil, include_skin_tones: nil, profile: nil)
			get('/emoji/catalog', profile: profile, deep: deep.to_s, lang: lang, category: category, subcategory: subcategory, version: version, max_version: max_version, include_skin_tones: include_skin_tones.nil? ? nil : include_skin_tones.to_s)
		end

		def emoji_metadata
			get('/emoji/metadata')
		end

		def emoji_categories
			get('/emoji/categories')
		end

		# Positions are UTF-16 code units; end is exclusive.
		def emoji_parse(text, deep: false, lang: nil)
			get('/emoji/parse', { deep: deep, lang: lang }, {}, { text: text })
		end

		def emoji_convert(text, direction:, shortcode_source:)
			get('/emoji/convert', {direction: direction, shortcode_source: shortcode_source}, {}, {text: text})
		end


		private

		def time_source(timezone, **values)
			primary = values.values_at(:ip, :city, :iata, :icao, :unlocode, :address).compact
			if values.values.any? { |v| !v.nil? && (!v.is_a?(String) || v.strip.empty?) } ||
				(!timezone.nil? && values.values.any? { |v| !v.nil? }) || primary.length > 1 ||
				(!values[:country].nil? && !primary.empty? && values[:city].nil? && values[:address].nil?) ||
				(!values[:state].nil? && ((values[:city].nil? && values[:address].nil?) || values[:country].nil?)) ||
				(!values[:address].nil? && values[:country].nil?)
				raise ArgumentError, 'Pass one Time source, using country only with city or address and state only with city or address and country.'
			end
			values
		end

		def time_targets(targets, to)
			return nil if targets.nil?
			unless to.nil? && targets.is_a?(Array) && (1..10).cover?(targets.length) && targets.all? { |zone| zone.is_a?(String) && !zone.strip.empty? && !zone.include?(',') }
				raise ArgumentError, 'Time targets requires 1 to 10 timezone IDs and cannot be combined with to.'
			end
			targets.join(',')
		end




		def seg(value)
			URI.encode_www_form_component(value.to_s).gsub('+', '%20')
		end

		def get(path, params = {}, headers = {}, json = nil)
			retries = retries_for(path, params)
			query = params.reject { |_name, value| value.nil? || value == false }
			uri = @base_url.dup
			uri.path = path
			uri.query = URI.encode_www_form(query) unless query.empty?

			encoded = json.nil? ? nil : JSON.generate(json)
			attempt = 0
			loop do
				begin
					status, response_headers, body = if encoded.nil?
						execute(uri, request_headers(headers))
					else
						execute(uri, request_headers(headers.merge('Content-Type' => 'application/json')), 'POST', encoded)
					end
				rescue *NETWORK_ERRORS
					raise if attempt >= retries

					sleep(retry_delay(attempt, nil))
					attempt += 1
					next
				end

				return JSON.parse(body) if (200..299).cover?(status)

				retry_after = response_headers['retry-after']
				if RETRY_STATUS.include?(status) && attempt < retries && (wait = retry_delay(attempt, retry_after))
					sleep(wait)
					attempt += 1
					next
				end

				raise build_error(status, body, retry_after)
			end
		end

		def request_headers(extra)
			{ 'X-API-Key' => @api_key, 'User-Agent' => "parseapi-ruby/#{VERSION}" }.merge(extra).merge('Parse-Version' => API_VERSION)
		end

		# Returns [status, headers_hash, body_string]. Overridden in tests.
		def execute(uri, headers, method = 'GET', body = nil)
			return (method == 'GET' ? @transport.call(uri.to_s, headers) : @transport.call(uri.to_s, headers, method, body)) if @transport

			timeout = !@timeout_explicit && uri.path.start_with?('/stack/') ? 35 : @timeout
			http = connection(timeout)
			request = (method == 'POST' ? Net::HTTP::Post : Net::HTTP::Get).new(uri.request_uri)
			request.body = body unless body.nil?
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
				if /\A[0-9]+(?:\.[0-9]+)?\z/.match?(retry_after.strip)
					seconds = Float(retry_after, exception: false)
					return seconds && seconds.finite? && seconds <= RETRY_AFTER_CAP ? seconds : nil
				end
				begin
					seconds = [Time.httpdate(retry_after) - Time.now, 0].max
					return seconds > RETRY_AFTER_CAP ? nil : seconds
				rescue ArgumentError
					# Fall back to jitter when the header is not a delay or HTTP date.
				end
			end
			rand * [0.25 * (2**[attempt, 5].min), RETRY_AFTER_CAP].min
		end

		def retries_for(path, params)
			return @retries unless @retries.nil?

			product = path.split('/', 3)[1]
			metered = METERED_CORE.include?(product) || (%w[email vat address].include?(product) && params[:deep] == true)
			metered ? 0 : DEFAULT_RETRIES
		end

		def city_csv(value)
			value.is_a?(Array) ? value.join(',') : value
		end


		def build_error(status, body, retry_after = nil)
			parsed = begin
				JSON.parse(body)
			rescue JSON::ParserError
				{}
			end
			parsed = {} unless parsed.is_a?(Hash)
			error = Error.new(
				status: status,
				code: parsed['code'].is_a?(String) ? parsed['code'] : 'unknown_error',
				message: parsed['message'].is_a?(String) ? parsed['message'] : "Request failed with status #{status}",
				docs: parsed['docs'].is_a?(String) ? parsed['docs'] : nil,
				request_id: parsed['request_id'].is_a?(String) ? parsed['request_id'] : nil,
				retry_after: retry_after
			)
			if status == 409 && error.code == 'ambiguous_city' && parsed['candidates'].is_a?(Array)
				candidates = parsed['candidates'].first(2).map do |row|
					next unless row.is_a?(Hash) && row['id'].is_a?(String) && /\Acity_[a-z0-9]{12}\z/.match?(row['id']) && row['object'] == 'city'
					candidate = { 'id' => row['id'], 'object' => 'city' }
					%w[name name_local country country_name state state_name type].each do |field|
						value = row[field]
						candidate[field] = value if row.key?(field) && (value.nil? || (value.is_a?(String) && value.length <= 255))
					end
					candidate
				end.compact
				error.instance_variable_set(:@candidates, candidates)
			end
			error
		end
	end
end
