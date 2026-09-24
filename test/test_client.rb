require 'minitest/autorun'
require 'json'
require_relative '../lib/parseapi'
require_relative 'public_api_snapshot'

# Test double: records URLs/headers, returns queued responses without network.
class StubClient < ParseAPI::Client
	attr_reader :calls

	def initialize(*args, responses: nil, **kwargs)
		super(*args, **kwargs)
		@calls = []
		@responses = responses
	end

	private

	def execute(uri, headers)
		@calls << { url: uri.to_s, headers: headers }
		return [200, {}, '{}'] if @responses.nil?
		raise 'stub exhausted' if @responses.empty?

		response = @responses.shift
		raise response if response.is_a?(Exception)
		response
	end
end

class TestUrlMapping < Minitest::Test
	def test_postal_choices_preserve_observation_without_inferring_city
		choice = { 'city' => 'SYDNEY', 'state' => 'NSW', 'state_name' => 'New South Wales', 'future' => true }
		other = { 'city' => 'HAYMARKET', 'state' => 'NSW', 'state_name' => 'New South Wales' }
		[{}, { 'localities' => nil }, { 'localities' => [] }, { 'localities' => [choice] }, { 'localities' => [choice, other] }].each do |extra|
			body = { 'postal' => '2000', 'country' => 'AU', 'city' => nil }.merge(extra)
			client = stub_client(responses: [[200, {}, JSON.generate(body)]])
			assert_equal body, client.postal('2000', country: 'AU')
		end
	end

	def test_public_api_matches_the_reviewed_manifest
		expected = JSON.parse(File.read(File.join(__dir__, 'public_api.json')))
		assert_equal expected, PublicAPISnapshot.capture
	end

	def stub_client(**kwargs)
		StubClient.new('test_key_123', retries: 0, **kwargs)
	end

	def test_stack_deadline_defaults_and_explicit_settings
		response = Struct.new(:code, :body).new('200', '{"domain":"xn--bcher-kva.example","url":"https://xn--bcher-kva.example/","checked_at":null,"scope":"site","pages":0,"partial":null,"cms":null,"servers":null,"frameworks":null,"ecommerce":null,"analytics":null,"chat":null,"payments":null,"hosting":null,"deep":{},"future":true}')
		def response.each_header; yield 'content-type', 'application/json'; end
		[nil, 10, 1.2, 45].each do |configured|
			http = Net::HTTP.new('example.com', 443)
			captured = []
			http.define_singleton_method(:start) { self }
			http.define_singleton_method(:started?) { true }
			http.define_singleton_method(:request) do |_request|
				captured << [open_timeout, read_timeout, write_timeout]
				response
			end
			original_new = Net::HTTP.method(:new)
			Net::HTTP.define_singleton_method(:new) { |*_args| http }
			begin
				client = ParseAPI::Client.new('fixture', timeout: configured)
				assert_nil client.stack('example.com')['frameworks']
				client.domain('example.com')
				assert_equal({}, client.stack('example.com', deep: true)['deep'])
				assert_equal [configured || 35, configured || 10, configured || 35], captured.map(&:first)
				assert captured.all? { |timeouts| timeouts.uniq.length == 1 }
			ensure
				Net::HTTP.define_singleton_method(:new, original_new)
			end
		end
	end

	def test_stack_preserves_null_empty_and_core_versions
		records = JSON.parse('[{"domain":"xn--bcher-kva.example","url":"https://xn--bcher-kva.example/","checked_at":null,"scope":"homepage","pages":0,"partial":null,"cms":null,"servers":null,"frameworks":null,"ecommerce":null,"analytics":null,"chat":null,"payments":null,"hosting":null,"future":true},{"domain":"xn--bcher-kva.example","url":"https://xn--bcher-kva.example/","checked_at":"2026-09-21T12:00:00Z","scope":"homepage","pages":1,"partial":true,"cms":[],"servers":[],"frameworks":[],"ecommerce":[],"analytics":[],"chat":[],"payments":[],"hosting":[],"deep":{},"future":true},{"domain":"xn--bcher-kva.example","url":"https://xn--bcher-kva.example/","checked_at":"2026-09-21T12:00:00Z","scope":"homepage","pages":1,"partial":true,"cms":[{"technology":"wordpress","name":"WordPress","version":"6.8.2"}],"servers":[{"technology":"nginx","name":"nginx","version":null}],"frameworks":[{"technology":"react","name":"React","version":null}],"ecommerce":[],"analytics":[],"chat":[],"payments":[],"hosting":[],"future":true},{"domain":"xn--bcher-kva.example","url":"https://xn--bcher-kva.example/","checked_at":"2026-09-21T12:00:00Z","scope":"site","pages":6,"partial":false,"cms":[{"technology":"wordpress","name":"WordPress","version":"6.8.2"},{"technology":"ghost","name":"Ghost","version":null}],"servers":[{"technology":"nginx","name":"nginx","version":null},{"technology":"apache","name":"Apache","version":null}],"frameworks":[{"technology":"nextjs","name":"Next.js","version":"15.0.0","future":true},{"technology":"react","name":"React","version":null}],"ecommerce":[{"technology":"woocommerce","name":"WooCommerce","version":null}],"analytics":[{"technology":"google-analytics","name":"Google Analytics","version":null}],"chat":[{"technology":"intercom","name":"Intercom","version":null}],"payments":[{"technology":"stripe","name":"Stripe","version":null}],"hosting":[{"technology":"vercel","name":"Vercel","version":null}],"future":true},{"domain":"xn--bcher-kva.example","url":"https://xn--bcher-kva.example/","checked_at":"2026-09-21T12:00:00Z","scope":"site","pages":3,"partial":true,"cms":[],"servers":[],"frameworks":[{"technology":"nextjs","name":"Next.js","version":null,"future":true}],"ecommerce":[],"analytics":[],"chat":[],"payments":[],"hosting":[],"deep":{},"future":true},{"domain":"xn--bcher-kva.example","url":"https://xn--bcher-kva.example/","checked_at":null,"scope":"site","pages":0,"partial":null,"cms":null,"servers":null,"frameworks":null,"ecommerce":null,"analytics":null,"chat":null,"payments":null,"hosting":null,"deep":{},"future":true}]')
		records.each do |body|
			client = stub_client(responses: [[200, {}, JSON.generate(body)], [200, {}, JSON.generate(body)]])
			assert_equal body, client.stack('bücher.example', deep: true, pretty: true)
			assert_equal body, client.stack('example.com')
			assert_equal 'https://api.parseapi.com/stack/b%C3%BCcher.example?deep=true&pretty=true', client.calls[0][:url]
			assert_equal 'https://api.parseapi.com/stack/example.com', client.calls[1][:url]
			assert_equal '2.0.0', client.calls[0][:headers]['Parse-Version']
		end
	end

	def test_email_enrichment_preserves_false_null_and_future_codes
		[{}, { 'deep' => {} }, { 'deep' => { 'first_name' => nil, 'no_reply' => nil, 'tag' => nil, 'mail_provider' => nil, 'status' => nil, 'reason' => nil } }, { 'deep' => { 'first_name' => 'Jane', 'no_reply' => false, 'tag' => 'news', 'mail_provider' => 'future-provider', 'deliverable' => true, 'catchall' => false, 'status' => 'future-status', 'reason' => 'future_reason' }, 'future' => true }].each do |extra|
			body = { 'email' => 'jane.doe+news@example.com' }.merge(extra)
			client = stub_client(responses: [[200, {}, JSON.generate(body)]])
			assert_equal body, client.email(body['email'], deep: true)
		end
	end

	def test_dns_preserves_presentation_and_empty_records
		[[], [{ 'name' => 'example.com.', 'type' => 'TXT', 'ttl' => 0, 'value' => '"one" "two"', 'future' => nil }]].each do |records|
			body = { 'domain' => 'example.com', 'records' => records, 'future' => true }
			client = stub_client(responses: [[200, {}, JSON.generate(body)]])
			assert_equal body, client.dns('example.com', type: 'TXT')
		end
	end

	def test_card_preserves_null_false_and_prefix
		body = { 'bin' => '00123456', 'prefix' => '001234', 'country' => nil, 'issuer' => 'Fixture Bank', 'brand' => 'future-brand', 'type' => nil, 'prepaid' => false, 'deep' => {}, 'future' => true }
		client = stub_client(responses: [[200, {}, JSON.generate(body)]])
		assert_equal body, client.card('00 1234-56')
	end

	def test_name_preserves_nullable_evidence_and_future_fields
		body = { 'name' => '王', 'valid' => true, 'deep' => { 'gender' => nil, 'salutation' => nil }, 'future' => true }
		client = stub_client(responses: [[200, {}, JSON.generate(body)]])
		assert_equal body, client.name('王', country: 'CN', deep: true)
	end

	def test_name_formatting_locale_and_nullable_results
		[{ 'short' => 'R.J. Smith', 'directory' => 'Smith, Robert James', 'initials' => 'RJS' }, { 'short' => nil, 'directory' => nil, 'initials' => nil }, { 'gender' => nil }, {}].each do |detail|
			body = { 'name' => 'Robert James Smith', 'deep' => detail }
			client = stub_client(responses: [[200, {}, JSON.generate(body)], [200, {}, JSON.generate(body)]])
			assert_equal body, client.name('Robert James Smith', country: 'US', deep: true, name_locale: 'en-GB')
			assert_equal 'https://api.parseapi.com/name/Robert%20James%20Smith?country=US&deep=true&name_locale=en-GB', client.calls[0][:url]
			client.name('Andrea', country: 'IT', deep: true)
			assert_equal 'https://api.parseapi.com/name/Andrea?country=IT&deep=true', client.calls[1][:url]
		end
	end

	TABLE = {
		'card' => [->(p) { p.card('001234') }, 'https://api.parseapi.com/card/001234'],
		'card separators' => [->(p) { p.card('00 1234-56') }, 'https://api.parseapi.com/card/00%201234-56'],
		'dns' => [->(p) { p.dns('example.com') }, 'https://api.parseapi.com/dns/example.com'],
		'dns type' => [->(p) { p.dns('_dmarc.bücher.example.', type: 'txt') }, 'https://api.parseapi.com/dns/_dmarc.b%C3%BCcher.example.?type=txt'],
		'naics' => [->(p) { p.naics('31-33') }, 'https://api.parseapi.com/naics/31-33'],
		'naics encoded' => [->(p) { p.naics('54/11') }, 'https://api.parseapi.com/naics/54%2F11'],
		'naics_search' => [->(p) { p.naics_search('coffee & tea', limit: 5) }, 'https://api.parseapi.com/naics?q=coffee+%26+tea&limit=5'],
		'naics_search default' => [->(p) { p.naics_search('plumbing') }, 'https://api.parseapi.com/naics?q=plumbing'],
		'name country' => [->(p) { p.name('Andrea / Smith', country: 'IT') }, 'https://api.parseapi.com/name/Andrea%20%2F%20Smith?country=IT'],
		'measure' => [->(p) { p.measure('5 ft 11 in', to: 'cm', locale: 'en-US', system: 'us') }, 'https://api.parseapi.com/measure/5%20ft%2011%20in?to=cm&locale=en-US&system=us'],
		'measure compound' => [->(p) { p.measure('1 kg/m^3', to: 'g/L') }, 'https://api.parseapi.com/measure/1%20kg%2Fm%5E3?to=g%2FL'],
		'measure_units' => [->(p) { p.measure_units(query: 'US gallon', type: 'volume', unit: 'L') }, 'https://api.parseapi.com/measure/units?q=US+gallon&type=volume&unit=L'],
		'measure_units all' => [->(p) { p.measure_units }, 'https://api.parseapi.com/measure/units'],
		'ip' => [->(p) { p.ip('8.8.8.8') }, 'https://api.parseapi.com/ip/8.8.8.8'],
		'ip_self' => [->(p) { p.ip_self }, 'https://api.parseapi.com/ip'],
		'ip deep' => [->(p) { p.ip('8.8.8.8', deep: true) }, 'https://api.parseapi.com/ip/8.8.8.8?deep=true'],
		'continent' => [->(p) { p.continent('NA') }, 'https://api.parseapi.com/continent/NA'],
		'continent_countries' => [->(p) { p.continent_countries('NA') }, 'https://api.parseapi.com/continent/NA/countries'],
		'bloc' => [->(p) { p.bloc('EU') }, 'https://api.parseapi.com/bloc/EU'],
		'bloc_countries' => [->(p) { p.bloc_countries('SCHENGEN') }, 'https://api.parseapi.com/bloc/SCHENGEN/countries'],
		'country' => [->(p) { p.country('US') }, 'https://api.parseapi.com/country/US'],
		'country_states' => [->(p) { p.country_states('US') }, 'https://api.parseapi.com/country/US/states'],
		'state' => [->(p) { p.state('NC', country: 'US') }, 'https://api.parseapi.com/state/NC?country=US'],
		'state_districts' => [->(p) { p.state_districts('NC', country: 'US') }, 'https://api.parseapi.com/state/NC/districts?country=US'],
		'district' => [->(p) { p.district('37081') }, 'https://api.parseapi.com/district/37081'],
		'city' => [->(p) { p.city('charlotte', state: 'NC') }, 'https://api.parseapi.com/city/charlotte?state=NC'],
		'city_id' => [->(p) { p.city_id('city_mb8mbqrkz8zb') }, 'https://api.parseapi.com/city/id/city_mb8mbqrkz8zb'],
		'city_search' => [->(p) { p.city_search('char', country: 'US', limit: 10) }, 'https://api.parseapi.com/city?q=char&country=US&limit=10'],
		'city_nearest' => [->(p) { p.city_nearest(35.2271, -80.8431) }, 'https://api.parseapi.com/city?lat=35.2271&lon=-80.8431'],
		'city_nearby' => [->(p) { p.city_nearby('denver', radius: 8, unit: 'mi', limit: 3) }, 'https://api.parseapi.com/city/denver/nearby?radius=8&unit=mi&limit=3'],
		'state_name' => [->(p) { p.state('colorado') }, 'https://api.parseapi.com/state/colorado'],
		'postal' => [->(p) { p.postal('28202', country: 'US') }, 'https://api.parseapi.com/postal/28202?country=US'],
		'postal_bare' => [->(p) { p.postal('SW1A 1AA') }, 'https://api.parseapi.com/postal/SW1A%201AA'],
		'postal_nearby' => [->(p) { p.postal_nearby('28202', country: 'US', radius: 40, unit: 'km') }, 'https://api.parseapi.com/postal/28202/nearby?country=US&radius=40&unit=km'],
		'postal_distance' => [->(p) { p.postal_distance('28202', '10001', country: 'US') }, 'https://api.parseapi.com/postal/28202/distance/10001?country=US'],
		'address' => [->(p) { p.address('1600 Pennsylvania Ave NW, Washington, DC 20500', country: 'US') }, 'https://api.parseapi.com/address/1600%20Pennsylvania%20Ave%20NW%2C%20Washington%2C%20DC%2020500?country=US'],
		'address_search' => [->(p) { p.address_search('123 main', country: 'US', postal: '27401', city: 'Greensboro', state: 'NC', ip: '8.8.8.8') }, 'https://api.parseapi.com/address?q=123+main&country=US&postal=27401&city=Greensboro&state=NC&ip=8.8.8.8'],
		'company' => [->(p) { p.company('732829320', country: 'FR', deep: true) }, 'https://api.parseapi.com/company/732829320?country=FR&deep=true'],
		'email' => [->(p) { p.email('a@b.com') }, 'https://api.parseapi.com/email/a%40b.com'],
		'vat' => [->(p) { p.vat('DE136695976') }, 'https://api.parseapi.com/vat/DE136695976'],
		'iban' => [->(p) { p.iban('DE89370400440532013000') }, 'https://api.parseapi.com/iban/DE89370400440532013000'],
		'iban country' => [->(p) { p.iban('89370400440532013000', country: 'DE') }, 'https://api.parseapi.com/iban/89370400440532013000?country=DE'],
		'npi' => [->(p) { p.npi('1881018208') }, 'https://api.parseapi.com/npi/1881018208'],
		'npi deep' => [->(p) { p.npi('1881018208', deep: true) }, 'https://api.parseapi.com/npi/1881018208?deep=true'],
		'vat from deep' => [->(p) { p.vat('DE136695976', from: 'IE6388047V', deep: true) }, 'https://api.parseapi.com/vat/DE136695976?deep=true&from=IE6388047V'],
		'phone encodes plus' => [->(p) { p.phone('+14155552671', deep: true) }, 'https://api.parseapi.com/phone/%2B14155552671?deep=true'],
		'carrier encodes plus' => [->(p) { p.carrier('+14155552671') }, 'https://api.parseapi.com/carrier/%2B14155552671'],
		'caller with country' => [->(p) { p.caller('4155552671', country: 'US') }, 'https://api.parseapi.com/caller/4155552671?country=US'],
		'hlr' => [->(p) { p.hlr('+447712345678') }, 'https://api.parseapi.com/hlr/%2B447712345678'],
		'domain' => [->(p) { p.domain('example.com') }, 'https://api.parseapi.com/domain/example.com'],
		'asn' => [->(p) { p.asn('AS13335') }, 'https://api.parseapi.com/asn/AS13335'],
		'mac' => [->(p) { p.mac('00:1B:63:84:45:E6') }, 'https://api.parseapi.com/mac/00%3A1B%3A63%3A84%3A45%3AE6'],
		'mx' => [->(p) { p.mx('example.com') }, 'https://api.parseapi.com/mx/example.com'],
		'useragent' => [->(p) { p.useragent('TestUA/1.0') }, 'https://api.parseapi.com/useragent'],
		'vin' => [->(p) { p.vin('1HGCM82633A004352') }, 'https://api.parseapi.com/vin/1HGCM82633A004352'],
		'vin deep' => [->(p) { p.vin('1HGCM82633A004352', deep: true) }, 'https://api.parseapi.com/vin/1HGCM82633A004352?deep=true'],
		'tariff' => [->(p) { p.tariff('8471.30.01.00', deep: true, origin: 'CN') }, 'https://api.parseapi.com/tariff/8471.30.01.00?deep=true&origin=CN'],
		'tariff_search' => [->(p) { p.tariff_search('sunglasses') }, 'https://api.parseapi.com/tariff?q=sunglasses'],
		'currency' => [->(p) { p.currency('USD') }, 'https://api.parseapi.com/currency/USD'],
		'currency_rate' => [->(p) { p.currency_rate('USD', 'EUR') }, 'https://api.parseapi.com/currency/USD/EUR'],
		'currency_rate date amount' => [->(p) { p.currency_rate('USD', 'JPY', date: '2026-08-28', amount: 100) }, 'https://api.parseapi.com/currency/USD/JPY?date=2026-08-28&amount=100'],
		'language' => [->(p) { p.language('en') }, 'https://api.parseapi.com/language/en'],
		'name encodes spaces' => [->(p) { p.name('Smith, John') }, 'https://api.parseapi.com/name/Smith%2C%20John'],
		'time UTC' => [->(p) { p.time }, 'https://api.parseapi.com/time'],
		'time conversion' => [->(p) { p.time('America/New_York', at: '2026-09-05T15:00', to: 'Europe/London') }, 'https://api.parseapi.com/time/America%2FNew_York?at=2026-09-05T15%3A00&to=Europe%2FLondon'],
		'time coordinates' => [->(p) { p.time_at(0, 0, at: '1970-01-01T00:00:00Z', to: 'UTC') }, 'https://api.parseapi.com/time?lat=0&lon=0&at=1970-01-01T00%3A00%3A00Z&to=UTC'],
		'timezone encodes slash' => [->(p) { p.timezone('America/New_York') }, 'https://api.parseapi.com/timezone/America%2FNew_York'],
		'timezone conversion' => [->(p) { p.timezone('America/New_York', at: '2026-09-05T15:00', to: 'Europe/London') }, 'https://api.parseapi.com/timezone/America%2FNew_York?at=2026-09-05T15%3A00&to=Europe%2FLondon'],
		'timezone coordinates' => [->(p) { p.timezone_at(0, 0, at: '2026-09-05T12:00Z') }, 'https://api.parseapi.com/timezone?lat=0&lon=0&at=2026-09-05T12%3A00Z'],
		'date' => [->(p) { p.date('03/04/2026', format: 'mdy', to: '2026-04-01') }, 'https://api.parseapi.com/date/03%2F04%2F2026?format=mdy&to=2026-04-01'],
		'date today' => [->(p) { p.date_today }, 'https://api.parseapi.com/date'],
		'date today distance' => [->(p) { p.date_today(to: '2026-12-25') }, 'https://api.parseapi.com/date?to=2026-12-25'],
		'holiday' => [->(p) { p.holiday('US', year: 1955) }, 'https://api.parseapi.com/holiday/US?year=1955'],
		'holiday_date' => [->(p) { p.holiday_date('US', '2026-12-25') }, 'https://api.parseapi.com/holiday/US/2026-12-25'],
		'elevation' => [->(p) { p.elevation(35.2, -80.8) }, 'https://api.parseapi.com/elevation?lat=35.2&lon=-80.8'],
		'point deep' => [->(p) { p.point(36.0726, -79.792, deep: true) }, 'https://api.parseapi.com/point?lat=36.0726&lon=-79.792&deep=true'],
		'weather' => [->(p) { p.weather(40.7128, -74.006, deep: true) }, 'https://api.parseapi.com/weather?lat=40.7128&lon=-74.006&deep=true'],
		'weather history' => [->(p) { p.weather(40.7128, -74.006, deep: true, date: '2026-09-01') }, 'https://api.parseapi.com/weather?lat=40.7128&lon=-74.006&deep=true&date=2026-09-01'],
		'emoji' => [->(p) { p.emoji('rocket') }, 'https://api.parseapi.com/emoji/rocket'],
		'emoji_search' => [->(p) { p.emoji_search('fire', limit: 20) }, 'https://api.parseapi.com/emoji?q=fire&limit=20']
	}.freeze

	TABLE.each do |name, (invoke, expected)|
		define_method("test_url_#{name.gsub(/\W/, '_')}") do
			client = stub_client
			invoke.call(client)
			assert_equal expected, client.calls.first[:url]
		end
	end

	def test_headers
		client = stub_client
		client.country('US')
		headers = client.calls.first[:headers]
		assert_equal 'test_key_123', headers['X-API-Key']
		assert_match(/\Aparseapi-ruby\/\d+\.\d+\.\d+\z/, headers['User-Agent'])
	end

	def test_useragent_header_override
		client = stub_client
		client.useragent('Mozilla/5.0 (Test)')
		assert_equal 'Mozilla/5.0 (Test)', client.calls.first[:headers]['User-Agent']
	end

	def test_missing_key
		saved = ENV.delete('PARSEAPI_KEY')
		assert_raises(ArgumentError) { ParseAPI::Client.new }
	ensure
		ENV['PARSEAPI_KEY'] = saved if saved
	end

	def test_env_key
		saved = ENV['PARSEAPI_KEY']
		ENV['PARSEAPI_KEY'] = 'env_key_456'
		client = StubClient.new(retries: 0)
		client.country('US')
		assert_equal 'env_key_456', client.calls.first[:headers]['X-API-Key']
	ensure
		saved ? ENV['PARSEAPI_KEY'] = saved : ENV.delete('PARSEAPI_KEY')
	end

	def test_base_url_override
		client = StubClient.new('k', base_url: 'http://localhost:3000/', retries: 0)
		client.country('US')
		assert_equal 'http://localhost:3000/country/US', client.calls.first[:url]
	end

	def test_error_shape
		body = JSON.generate(code: 'not_found', message: 'City not found', docs: 'https://parseapi.com/docs#not_found', request_id: 'req_abc')
		client = StubClient.new('k', retries: 0, responses: [[404, {}, body]])
		err = assert_raises(ParseAPI::Error) { client.city('notarealcityxyz') }
		assert_equal 404, err.status
		assert_equal 'not_found', err.code
		assert_equal 'City not found', err.message
		assert_equal 'https://parseapi.com/docs#not_found', err.docs
		assert_equal 'req_abc', err.request_id
	end

	def test_non_json_error_body
		client = StubClient.new('k', retries: 0, responses: [[400, {}, 'gateway timeout']])
		err = assert_raises(ParseAPI::Error) { client.country('US') }
		assert_equal 'unknown_error', err.code
	end

	def test_retry_then_success
		responses = [
			[500, {}, '{"code":"server_error","message":"boom"}'],
			[200, {}, '{"country":"us"}']
		]
		client = StubClient.new('k', retries: 2, responses: responses)
		assert_equal 'us', client.country('US')['country']
		assert_equal 2, client.calls.length
	end

	def test_no_retry_on_404
		client = StubClient.new('k', retries: 2, responses: [[404, {}, '{"code":"not_found","message":"nope"}']])
		assert_raises(ParseAPI::Error) { client.country('XX') }
		assert_equal 1, client.calls.length
	end

	def test_gives_up_after_retries
		responses = Array.new(3) { [429, {}, '{"code":"rate_limited","message":"slow down"}'] }
		client = StubClient.new('k', retries: 2, responses: responses)
		err = assert_raises(ParseAPI::Error) { client.country('US') }
		assert_equal 'rate_limited', err.code
		assert_equal 3, client.calls.length
	end

	def test_native_response_preserves_unknown_fields_and_nulls
		body = '{"country":"zz","future":{"items":[null,false,0]},"deep":{},"unknown":null}'
		client = StubClient.new('k', retries: 0, responses: [[200, {}, body]])
		assert_equal JSON.parse(body), client.country('ZZ')
		assert_equal 1, client.calls.length
	end

	def test_invalid_timeout_and_retries_fail_at_construction
		[0, -1, Float::NAN, Float::INFINITY, '10'].each do |timeout|
			assert_raises(ArgumentError) { ParseAPI.new('k', timeout: timeout) }
		end
		[-1, 0.5, '2'].each do |retries|
			assert_raises(ArgumentError) { ParseAPI.new('k', retries: retries) }
		end
	end

	def test_zero_retries_makes_one_attempt
		client = StubClient.new('k', retries: 0, responses: [[503, {}, '{}']])
		assert_raises(ParseAPI::Error) { client.country('US') }
		assert_equal 1, client.calls.length
	end

	def test_redirect_is_an_error_without_forwarding_the_key
		client = StubClient.new('k', retries: 2, responses: [[302, { 'location' => 'https://other.example/steal' }, '']])
		error = assert_raises(ParseAPI::Error) { client.country('US') }
		assert_equal 302, error.status
		assert_equal 1, client.calls.length
		assert_equal 'https://api.parseapi.com/country/US', client.calls.first[:url]
	end

	def test_transport_does_not_add_retries_and_sets_all_timeouts
		http = Net::HTTP.new('example.test', 443)
		http.define_singleton_method(:start) { self }
		original_new = Net::HTTP.method(:new)
		Net::HTTP.define_singleton_method(:new) { |*_args| http }
		client = ParseAPI.new('k', timeout: 1.5, retries: 0)
		connection = client.send(:connection)
		assert_equal 0, connection.max_retries
		assert_equal 1.5, connection.open_timeout
		assert_equal 1.5, connection.read_timeout
		assert_equal 1.5, connection.write_timeout
	ensure
		Net::HTTP.define_singleton_method(:new, original_new) if original_new
	end

	def test_retry_after_supports_http_dates_and_wait_budget
		client = ParseAPI.new('k')
		assert_equal 0, client.send(:retry_delay, 0, 'Sun, 06 Nov 1994 08:49:37 GMT')
		assert_nil client.send(:retry_delay, 0, (Time.now + 60).httpdate)
		assert_nil client.send(:retry_delay, 0, '100')
	end

	def test_close_is_idempotent_and_releases_the_session
		client = ParseAPI.new('k')
		http = Object.new
		finishes = 0
		http.define_singleton_method(:started?) { true }
		http.define_singleton_method(:finish) { finishes += 1 }
		client.instance_variable_set(:@http, http)
		assert_nil client.close
		assert_nil client.close
		assert_nil client.instance_variable_get(:@http)
		assert_equal 1, finishes
	end

	def test_inspect_does_not_expose_credentials
		client = ParseAPI.new('do_not_log_this_key', base_url: 'https://private:password@example.test')
		refute_includes client.inspect, 'do_not_log_this_key'
		refute_includes client.inspect, 'password'
		assert_includes client.inspect, '[REDACTED]'
	end

	POLICY_CASES = {
		'country' => [->(p) { p.country('US') }, 3],
		'email core' => [->(p) { p.email('hello@example.com') }, 3],
		'email deep' => [->(p) { p.email('hello@example.com', deep: true) }, 1],
		'vat core' => [->(p) { p.vat('DE136695976') }, 3],
		'vat deep' => [->(p) { p.vat('DE136695976', deep: true) }, 1],
		'carrier' => [->(p) { p.carrier('+14155552671') }, 1],
		'caller' => [->(p) { p.caller('+14155552671') }, 1],
		'hlr' => [->(p) { p.hlr('+447712345678') }, 1],
		'address reserved deep' => [->(p) { p.address('1600 Pennsylvania Ave NW, Washington, DC 20500', deep: true) }, 1],
		'ip plan deep' => [->(p) { p.ip('8.8.8.8', deep: true) }, 3]
	}.freeze

	POLICY_CASES.each do |name, (invoke, expected)|
		define_method("test_default_retry_policy_#{name.gsub(/\W/, '_')}") do
			client = StubClient.new('k', responses: Array.new(3) { [503, { 'retry-after' => '0' }, '{}'] })
			assert_raises(ParseAPI::Error) { invoke.call(client) }
			assert_equal expected, client.calls.length
		end
	end

	def test_metered_network_failure_is_not_retried_by_default
		client = StubClient.new('k', responses: [EOFError.new('response lost')])
		assert_raises(EOFError) { client.email('hello@example.com', deep: true) }
		assert_equal 1, client.calls.length
	end

	def test_explicit_retries_override_the_metered_policy
		client = StubClient.new('k', retries: 1, responses: [[503, { 'retry-after' => '0' }, '{}'], [200, {}, '{}']])
		assert_equal({}, client.carrier('+14155552671'))
		assert_equal 2, client.calls.length
	end

	def test_custom_transport_needs_no_subclass
		calls = []
		parse = ParseAPI.new('k', transport: ->(url, headers) {
			calls << [url, headers]
			[200, {}, '{"country":"us"}']
		})
		assert_equal 'us', parse.country('US')['country']
		assert_equal 'https://api.parseapi.com/country/US', calls.first[0]
	end
end

class TestMeasure < Minitest::Test
	def test_decimal_and_ambiguity_are_plain_data
		[
			{ 'measure' => '0 m', 'valid' => true, 'type' => 'future-type', 'amount' => '0', 'unit' => 'm', 'reason' => nil, 'choices' => [], 'future' => nil },
			{ 'measure' => '1 gallon', 'valid' => false, 'type' => nil, 'amount' => nil, 'unit' => nil, 'reason' => 'ambiguous_unit', 'choices' => [{ 'unit' => 'us_gal', 'name' => 'US liquid gallon' }] }
		].each do |body|
			client = StubClient.new('test_key', retries: 0, responses: [[200, {}, JSON.generate(body)]])
			assert_equal body, client.measure(body['measure'])
		end
	end

	def test_bad_target_preserves_api_error
		client = StubClient.new('test_key', responses: [[400, {}, '{"code":"bad_request","message":"Incompatible units","request_id":"req_measure"}']])
		error = assert_raises(ParseAPI::Error) { client.measure('1 m', to: 'kg') }
		assert_equal 'bad_request', error.code
		assert_equal 1, client.calls.length
	end
end


class TestNAICSEvidence < Minitest::Test
 def test_exclusions_and_match_pass_through
  records = JSON.parse(%q([{"naics":"541511","name":"Custom Computer Programming Services","description":null,"level":6,"parent":"54151","parent_name":"Computer Systems Design and Related Services","children":[],"year":2022,"country":"US"},{"naics":"541511","name":"Custom Computer Programming Services","description":null,"level":6,"parent":"54151","parent_name":"Computer Systems Design and Related Services","children":[],"year":2022,"country":"US","exclusions":null,"match":null},{"naics":"541511","name":"Custom Computer Programming Services","description":null,"level":6,"parent":"54151","parent_name":"Computer Systems Design and Related Services","children":[],"year":2022,"country":"US","exclusions":[],"match":{"field":"future-field","text":"Future matching evidence","corrections":[],"future":true}},{"naics":"541511","name":"Custom Computer Programming Services","description":null,"level":6,"parent":"54151","parent_name":"Computer Systems Design and Related Services","children":[],"year":2022,"country":"US","exclusions":[{"description":"Designing integrated computer systems","codes":[{"naics":"541512","name":"Computer Systems Design Services"}]},{"description":"Activities classified elsewhere","codes":[]}],"match":{"field":"term","text":"Computer software programming services","corrections":[{"from":"sofware","to":"software"}]},"future":true}]))
  records.each do |record|
   body = { 'q' => 'sofware', 'year' => 2022, 'country' => 'US', 'results' => [record] }
   client = StubClient.new('test_key', retries: 0, responses: [[200, {}, JSON.generate(body)]])
   assert_equal body, client.naics_search('sofware')
   assert_equal 'https://api.parseapi.com/naics?q=sofware', client.calls[0][:url]
  end
 end
end


class TestADP < Minitest::Test
 CASES = JSON.parse('[["country", ["US"], {}], ["state", ["NC"], {"country": "US"}], ["state.districts", ["NC"], {"country": "US"}], ["district", ["37081"], {"country": "US", "state": "NC"}], ["city", ["Charlotte"], {"country": "US", "state": "NC"}], ["city.id", ["city_test"], {}], ["city.search", ["Charlotte"], {"country": "US", "state": "NC", "limit": 2}], ["city.nearest", [0, 0], {}], ["city.nearby", ["Charlotte"], {"radius": 0, "unit": "km", "country": "US", "state": "NC", "limit": 2}], ["postal", ["28202"], {"country": "US"}], ["postal.nearby", ["28202"], {"country": "US", "radius": 0, "unit": "km"}], ["postal.distance", ["28202", "10001"], {"country": "US"}], ["iban", ["DE89370400440532013000"], {"country": "DE"}], ["carrier", ["+14155552671"], {"country": "US"}], ["hlr", ["+447712345678"], {"country": "GB"}], ["naics", ["31-33"], {}], ["naics.search", ["coffee"], {"limit": 2}], ["currency", ["USD"], {}], ["language", ["ar"], {}], ["name", ["Andrea"], {"country": "IT"}], ["time", [], {"at": "2026-09-08", "to": "UTC"}], ["time.at", [0, 0], {"at": "2026-09-08", "to": "UTC"}], ["timezone", ["UTC"], {"at": "2026-09-08", "to": "UTC"}], ["timezone.at", [0, 0], {"at": "2026-09-08"}], ["date", ["03/04/2026"], {"format": "dmy", "to": "2026-09-08"}], ["date.today", [], {"to": "2026-09-08"}], ["emoji", ["fire"], {}], ["emoji.search", ["fire"], {"limit": 2}]]')
 CASES.each do |method, args, options|
  define_method("test_deep_#{method}") do
   data = { 'deep' => { 'zero' => 0, 'missing' => nil, 'empty' => [], 'future' => true } }
   client = StubClient.new('k', responses: Array.new(2) { [200, {}, JSON.generate(data)] })
   native = method.tr('.', '_')
   kwargs = options.transform_keys(&:to_sym)
   assert_equal data, client.public_send(native, *args, **kwargs)
   assert_equal data, client.public_send(native, *args, **kwargs, deep: true)
   first, last = client.calls.map { |call| URI(call[:url]) }
   assert_equal first.path, last.path
   assert_equal URI.decode_www_form(first.query || '').to_h.merge('deep' => 'true'), URI.decode_www_form(last.query || '').to_h
  end
 end
end


class TestNameLocal < Minitest::Test
 def test_preserves_native_name_and_null_in_direct_and_nested_responses
  ['München', nil].each do |name_local|
   record = { 'name' => 'Munich', 'name_local' => name_local }
   cases = [
    [->(p) { p.country('DE') }, record],
    [->(p) { p.state('BY') }, record],
    [->(p) { p.city('Munich') }, record],
    [->(p) { p.language('de') }, record],
    [->(p) { p.holiday('DE') }, { 'holidays' => [record] }],
    [->(p) { p.point(48, 11, deep: true) }, { 'deep' => { 'city' => record } }]
   ]
   cases.each do |invoke, body|
    client = StubClient.new('test_key', retries: 0, responses: [[200, {}, JSON.generate(body)]])
    assert_equal body, invoke.call(client)
   end
  end
 end
end


class TestLanguageOptions < Minitest::Test
  OPERATIONS = JSON.parse(%q@[["ip", ["8.8.8.8"], {"deep": true}], ["ip.self", [], {"deep": true}], ["continent", ["EU"], {}], ["continent.countries", ["EU"], {}], ["bloc.countries", ["EU"], {}], ["country", ["DE"], {"deep": true}], ["country.states", ["DE"], {}], ["state", ["CA"], {"country": "US"}], ["state.districts", ["CA"], {"country": "US", "deep": true}], ["district", ["37081"], {"country": "US", "state": "NC"}], ["city", ["München"], {"country": "DE"}], ["city.id", ["city_fixture"], {"deep": true}], ["city.search", ["Mün"], {"limit": 2}], ["city.nearest", [0, 0], {}], ["city.nearby", ["München"], {"radius": 0, "unit": "km"}], ["postal", ["SW1A 1AA"], {"country": "GB"}], ["postal.nearby", ["28202"], {"country": "US", "radius": 0}], ["postal.distance", ["28202", "10001"], {"country": "US"}], ["company", ["732829320"], {"country": "FR", "deep": true}], ["npi", ["1881018208"], {"deep": true}], ["asn", ["AS13335"], {}], ["currency", ["USD"], {"deep": true}], ["language", ["ja"], {}], ["time", ["America/New_York"], {"at": "2026-01-01T12:00", "to": "UTC", "deep": true}], ["time.at", [0, 0], {"at": "2026-01-01T12:00Z"}], ["timezone", ["UTC"], {"deep": true}], ["timezone.at", [0, 0], {"deep": true}], ["date", ["03/04/2026"], {"format": "dmy", "to": "2026-05-01", "deep": true}], ["date.today", [], {"to": "2026-05-01"}], ["point", [0, 0], {"deep": true}], ["emoji", ["😀"], {"deep": true}], ["emoji.search", ["visage"], {"limit": 2}], ["measure.units", [], {"query": "meter", "unit": "m"}]]@).freeze

  def test_display_language_is_per_request_and_preserves_existing_queries
    OPERATIONS.each do |name, args, options|
      client = StubClient.new('fixture', retries: 0)
      method = name.tr('.', '_')
      keywords = options.transform_keys(&:to_sym)
      client.public_send(method, *args, **keywords, lang: 'fr-CA')
      client.public_send(method, *args, **keywords)
      assert_equal 2, client.calls.length, name
      translated, original = client.calls.map { |call| URI(call[:url]) }
      assert_equal original.path, translated.path, name
      first = URI.decode_www_form(translated.query || '').to_h
      second = URI.decode_www_form(original.query || '').to_h
      assert_equal second.merge('lang' => 'fr-CA'), first, name
      refute second.key?('lang'), name
    end
  end

  def test_output_language_keeps_input_controls_and_response_data
    body = { 'name' => 'Nom traduit', 'name_local' => 'Native name', 'future' => nil }
    client = StubClient.new('fixture', responses: [[200, {}, JSON.generate(body)], [200, {}, '{}']])
    assert_equal body, client.date('03/04/2026', format: 'dmy', lang: 'en-US')
    client.measure('1,5 m', locale: 'de-DE', to: 'cm')
    assert_equal 'dmy', URI.decode_www_form(URI(client.calls[0][:url]).query).to_h['format']
    query = URI.decode_www_form(URI(client.calls[1][:url]).query).to_h
    assert_equal 'de-DE', query['locale']
    refute query.key?('lang')
    %i[bloc currency_rate measure holiday name email phone address].each do |method|
      refute ParseAPI::Client.instance_method(method).parameters.any? { |_, name| name == :lang }, method
    end
  end
end

class TestVersion < Minitest::Test
	def test_contract_pin_survives_retry_self_and_useragent
		calls = []
		client = ParseAPI.new('same-production-key', transport: lambda { |url, headers|
			calls << [url, headers]
			calls.length == 1 ? [503, { 'retry-after' => '0' }, '{"code":"unavailable"}'] : [200, {}, '{}']
		})
		client.country('US')
		client.ip_self
		client.useragent('Custom browser')
		assert_equal ['/country/US', '/country/US', '/ip', '/useragent'], calls.map { |url, _headers| URI(url).path }
		calls.each do |url, headers|
			assert_equal '2.0.0', headers['Parse-Version']
			assert_equal 'same-production-key', headers['X-API-Key']
			assert_nil URI(url).query
		end
		assert_equal 'Custom browser', calls.last[1]['User-Agent']
	ensure
		client&.close
	end
end

class TestCardDX < Minitest::Test
  def test_invalid_card_inputs_never_reach_transport
    client = StubClient.new('k')
    ['4111111111111111', '4111-1111-1111-1111', '12345', '123456789012', '１２３４５６', "001\u00a0234", "001\u200b234", '00%20234', "001\v234", ' ' * 59 + '001234', nil, 123456].each do |input|
      error = assert_raises(ArgumentError) { client.card(input) }
      assert_equal 'parseapi: Card requires a 6-11 digit prefix string.', error.message
    end
    assert_empty client.calls
    [" \t00-1234\r\n", ' ' * 58 + '001234', '12345678901'].each do |raw|
      client.card(raw)
      assert_equal raw, URI::DEFAULT_PARSER.unescape(URI(client.calls.last[:url]).path.delete_prefix('/card/'))
    end
  end

  def test_retry_after_budget_and_raw_metadata
    ['60', '9' * 400, (Time.now + 60).httpdate].each do |header|
      client = StubClient.new('k', responses: [[429, { 'retry-after' => header }, '{"code":"rate_limited","message":"Later","request_id":"receipt"}']])
      client.define_singleton_method(:sleep) { |_| flunk 'must not sleep' }
      error = assert_raises(ParseAPI::Error) { client.country('US') }
      header.nil? ? assert_nil(error.retry_after) : assert_equal(header, error.retry_after)
      assert_equal 'rate_limited', error.code
      assert_equal 'receipt', error.request_id
      assert_equal 1, client.calls.length
    end
    ['0', '0.01', 'malformed', nil].each do |header|
      client = StubClient.new('k', retries: 1, responses: [[503, { 'retry-after' => header }, '{}'], [503, { 'retry-after' => header }, '{}']])
      sleeps = []
      client.define_singleton_method(:sleep) { |delay| sleeps << delay }
      error = assert_raises(ParseAPI::Error) { client.country('US') }
      header.nil? ? assert_nil(error.retry_after) : assert_equal(header, error.retry_after)
      assert_equal 2, client.calls.length
      assert_equal 1, sleeps.length
      assert_equal header.to_f, sleeps[0] if header == '0' || header == '0.01'
      assert_operator sleeps[0], :<=, 5
    end
    assert_nil ParseAPI::Error.new(status: 400, code: 'test', message: 'test').retry_after
  end
end
