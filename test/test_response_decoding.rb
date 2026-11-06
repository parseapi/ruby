require 'minitest/autorun'
require 'json'
require_relative '../lib/parseapi'
class ResponseDecodingTest < Minitest::Test
 def test_default_response_and_retry
  calls=[]; body=File.read(File.join(__dir__,'fixtures/response-fixtures','clean-timezones.json'))
  client=ParseAPI::Client.new('fixture',retries:1,transport:lambda {|url,headers|calls << [url,headers];calls.size==1 ? [503,{'retry-after'=>'0'},'{"code":"unavailable"}'] : [200,{},body]})
  assert_equal JSON.parse(body),client.time_zones
  assert_equal 2,calls.size
  calls.each {|url,headers|refute headers.key?('Parse-Response');assert_equal '2.1.0',headers['X-API-Version'];assert_nil URI(url).query}
 end

 def test_seven_numeric_fields_pass_through
  country='{"country":"US","deep":{"gdp_usd":30769700000000,"gdp_per_capita_usd":90026.5163005744,"population_growth_percent":-0.25,"urban_population_percent":0,"internet_users_percent":null}}'
  weather='{"deep":{"minutes":[{"at":"2026-10-27T12:00:00Z","precipitation_rate":1.8,"precipitation_rate_in":0.071,"type":"rain"},{"at":"2026-10-27T12:01:00Z","precipitation_rate":0,"precipitation_rate_in":0},{"at":"2026-10-27T12:02:00Z","precipitation_rate":null,"precipitation_rate_in":null}],"history":{"precipitation":12.3,"precipitation_in":0.484}}}'
  client=ParseAPI::Client.new('fixture',transport:lambda {|url,headers| [200,{},url.to_s.include?('/country/') ? country : weather]})
  assert_equal JSON.parse(country),client.country('US',deep:true)
  assert_equal JSON.parse(weather),client.weather(0,0,deep:true)
 end
end
