require 'minitest/autorun'
require 'json'
require_relative '../lib/parseapi'

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

		@responses.shift
	end
end

class TestUrlMapping < Minitest::Test
	def stub_client(**kwargs)
		StubClient.new('test_key_123', retries: 0, **kwargs)
	end

	TABLE = {
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
		'mx' => [->(p) { p.mx('example.com') }, 'https://api.parseapi.com/mx/example.com'],
		'useragent' => [->(p) { p.useragent('TestUA/1.0') }, 'https://api.parseapi.com/useragent'],
		'vin' => [->(p) { p.vin('1HGCM82633A004352') }, 'https://api.parseapi.com/vin/1HGCM82633A004352'],
		'vin deep' => [->(p) { p.vin('1HGCM82633A004352', deep: true) }, 'https://api.parseapi.com/vin/1HGCM82633A004352?deep=true'],
		'currency' => [->(p) { p.currency('USD') }, 'https://api.parseapi.com/currency/USD'],
		'currency_rate' => [->(p) { p.currency_rate('USD', 'EUR') }, 'https://api.parseapi.com/currency/USD/EUR'],
		'currency_rate date amount' => [->(p) { p.currency_rate('USD', 'JPY', date: '2026-08-28', amount: 100) }, 'https://api.parseapi.com/currency/USD/JPY?date=2026-08-28&amount=100'],
		'language' => [->(p) { p.language('en') }, 'https://api.parseapi.com/language/en'],
		'name encodes spaces' => [->(p) { p.name('Smith, John') }, 'https://api.parseapi.com/name/Smith%2C%20John'],
		'timezone encodes slash' => [->(p) { p.timezone('America/New_York') }, 'https://api.parseapi.com/timezone/America%2FNew_York'],
		'holiday' => [->(p) { p.holiday('US', year: 1955) }, 'https://api.parseapi.com/holiday/US?year=1955'],
		'holiday_date' => [->(p) { p.holiday_date('US', '2026-12-25') }, 'https://api.parseapi.com/holiday/US/2026-12-25'],
		'elevation' => [->(p) { p.elevation(35.2, -80.8) }, 'https://api.parseapi.com/elevation?lat=35.2&lon=-80.8'],
		'point deep' => [->(p) { p.point(36.0726, -79.792, deep: true) }, 'https://api.parseapi.com/point?lat=36.0726&lon=-79.792&deep=true'],
		'weather' => [->(p) { p.weather(40.7128, -74.006, deep: true) }, 'https://api.parseapi.com/weather?lat=40.7128&lon=-74.006&deep=true'],
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
end
