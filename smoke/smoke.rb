# Live smoke against the edge. Canary-ready: env-driven, clean exit codes.
#   PARSEAPI_KEY       required
#   PARSEAPI_BASE_URL  optional override
# Run: ruby smoke/smoke.rb
require_relative '../lib/parseapi'

$failures = 0
$total = 0

def check(name, ok, detail = '')
	$total += 1
	$failures += 1 unless ok
	puts "#{ok ? 'ok  ' : 'FAIL'} #{name}#{detail.empty? ? '' : " (#{detail})"}"
end

def expect(name, assert = nil)
	result = yield
	problem = assert ? assert.call(result) : nil
	check(name, problem.nil?, problem || '')
rescue ParseAPI::Error => e
	check(name, false, "#{e.status} #{e.code}")
rescue StandardError => e
	check(name, false, e.message)
end

def expect_error(name, code)
	yield
	check(name, false, 'expected error, got 200')
rescue ParseAPI::Error => e
	check(name, e.code == code, "got #{e.code}")
rescue StandardError => e
	check(name, false, e.message)
end

UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'.freeze

parse = ParseAPI.new

expect('ip', ->(r) { r['ip'] == '8.8.8.8' ? nil : 'wrong ip' }) { parse.ip('8.8.8.8') }
expect('ip_self', ->(r) { r['ip'] ? nil : 'no ip' }) { parse.ip_self }
expect('continent', ->(r) { r['name'] == 'North America' ? nil : 'wrong name' }) { parse.continent('NA') }
expect('continent_countries', ->(r) { r['countries'].any? ? nil : 'empty' }) { parse.continent_countries('NA') }
expect('bloc', ->(r) { r['name'] == 'European Union' && r['members'] == 27 ? nil : 'wrong bloc' }) { parse.bloc('EU') }
expect('bloc_countries', ->(r) { r['countries']&.length == 29 ? nil : 'wrong members' }) { parse.bloc_countries('SCHENGEN') }
expect('country', ->(r) { r['iso3'] == 'USA' ? nil : 'wrong iso3' }) { parse.country('US') }
expect('country_states', ->(r) { r['states'].length >= 50 ? nil : 'too few' }) { parse.country_states('US') }
expect('state', ->(r) { r['name'] == 'North Carolina' ? nil : 'wrong' }) { parse.state('NC', country: 'US') }
expect('state_districts', ->(r) { r['districts'].any? ? nil : 'empty' }) { parse.state_districts('NC', country: 'US') }
expect('district', ->(r) { r['name'].include?('Guilford') ? nil : 'wrong district' }) { parse.district('37081') }
expect('city', ->(r) { r['name'] == 'Charlotte' && r['id'].to_s.start_with?('city_') ? nil : 'wrong city' }) { parse.city('charlotte', country: 'US') }
expect('city_id', ->(r) { r['name'] == 'Charlotte' ? nil : 'wrong city' }) { parse.city_id(parse.city('charlotte', country: 'US')['id']) }
expect('city_search', ->(r) { r['cities'].any? ? nil : 'empty' }) { parse.city_search('char', country: 'US', limit: 5) }
expect('city_nearest', ->(r) { r.key?('distance') ? nil : 'no distance' }) { parse.city_nearest(35.2271, -80.8431) }
expect('postal', ->(r) { r['city'] == 'Charlotte' ? nil : 'wrong city' }) { parse.postal('28202', country: 'US') }
expect('postal_nearby', ->(r) { r['nearby'].any? ? nil : 'empty' }) { parse.postal_nearby('28202', country: 'US', radius: 40) }
expect('postal_distance', ->(r) { r['distance'].between?(800, 1000) ? nil : "distance #{r['distance']}" }) { parse.postal_distance('28202', '10001', country: 'US') }
expect('email', ->(r) { r['valid'] == true ? nil : 'not valid' }) { parse.email('hello@gmail.com') }
expect('vat', ->(r) { r['valid'] == true && r['country'] == 'DE' ? nil : 'not valid DE' }) { parse.vat('DE136695976') }
expect('iban', ->(r) { r['valid'] == true && r['country'] == 'DE' && r['bank'] == '37040044' ? nil : 'not valid DE' }) { parse.iban('DE89370400440532013000') }
expect('iban junk', ->(r) { r['valid'] == false ? nil : 'expected invalid' }) { parse.iban('hello') }
expect('npi', ->(r) { r['valid'] == true && r['registered'] == true ? nil : 'not registered' }) { parse.npi('1881018208') }
expect('npi junk', ->(r) { r['valid'] == false ? nil : 'expected invalid' }) { parse.npi('hello') }
expect('phone', ->(r) { r['phone'] == '+14155552671' ? nil : 'wrong phone' }) { parse.phone('+14155552671') }
# Metered core siblings: junk numbers answer 200 valid false, free, no vendor dip.
expect('carrier junk free', ->(r) { r['valid'] == false ? nil : 'expected invalid' }) { parse.carrier('555-0100') }
expect('caller junk free', ->(r) { r['valid'] == false ? nil : 'expected invalid' }) { parse.caller('555-0100') }
expect('hlr junk free', ->(r) { r['valid'] == false ? nil : 'expected invalid' }) { parse.hlr('555-0100') }
expect('domain', ->(r) { r['available'] == false ? nil : 'gmail available?' }) { parse.domain('gmail.com') }
expect('mx', ->(r) { r['mx'].any? ? nil : 'no mx' }) { parse.mx('gmail.com') }
expect('useragent', ->(r) { r['browser'] == 'Chrome' ? nil : "browser #{r['browser']}" }) { parse.useragent(UA) }
expect('vin', ->(r) { r['valid'] == true && r['make'] == 'Honda' && r['year'] == 2003 ? nil : 'wrong decode' }) { parse.vin('1HGCM82633A004352') }
expect('vin junk', ->(r) { r['valid'] == false ? nil : 'expected invalid' }) { parse.vin('1HGCM82613A004352') }
expect('currency', ->(r) { r['symbol'] == '$' ? nil : 'wrong symbol' }) { parse.currency('USD') }
expect('currency_rate', ->(r) { r['rate'].positive? && r['rate'] < 10 ? nil : 'bad rate' }) { parse.currency_rate('USD', 'EUR') }
expect('language', ->(r) { r['language'] == 'en' && r['name'] == 'English' ? nil : 'wrong language' }) { parse.language('en') }
expect('name', ->(r) { r['name'] == "Billy O'Shall" && r['valid'] == true && r['gender'] == 'male' ? nil : 'wrong name' }) { parse.name("BILLY O'SHALL") }
expect('timezone', ->(r) { [-240, -300].include?(r['offset_minutes']) ? nil : "offset #{r['offset_minutes']}" }) { parse.timezone('America/New_York') }
expect('holiday', ->(r) { r['holidays'].length > 5 ? nil : 'too few' }) { parse.holiday('US') }
expect('holiday_date', ->(r) { r.dig('holiday', 'name') == 'Christmas Day' ? nil : 'not christmas' }) { parse.holiday_date('US', '2026-12-25') }
expect('holiday null', ->(r) { r['holiday'].nil? ? nil : 'expected null' }) { parse.holiday_date('US', '2026-08-12') }
expect('elevation', ->(r) { r['elevation'].is_a?(Numeric) ? nil : 'no elevation' }) { parse.elevation(35.2271, -80.8431) }
expect('point', ->(r) { r['country'] == 'US' ? nil : "country #{r['country']}" }) { parse.point(36.0726, -79.792) }
expect('weather', ->(r) { r.dig('station', 'id') ? nil : 'no station' }) { parse.weather(40.7128, -74.006) }
expect('emoji', ->(r) { r['emoji'] == [0x1F680].pack('U') ? nil : 'wrong emoji' }) { parse.emoji('rocket') }
expect('emoji_search', ->(r) { r['emojis'].any? ? nil : 'empty' }) { parse.emoji_search('fire', limit: 5) }
expect('point deep triad', ->(r) { r['deep'].is_a?(Hash) ? nil : 'deep missing' }) { parse.point(36.0726, -79.792, deep: true) }

expect_error('honest 404', 'not_found') { parse.city('notarealcityxyz') }
expect_error('bogus key 401', 'invalid_api_key') { ParseAPI.new('bogus_key_123', retries: 0).country('US') }

puts "\n#{$total - $failures}/#{$total} passed"
exit($failures.zero? ? 0 : 1)
