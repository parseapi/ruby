require 'minitest/autorun'
require 'json'
require_relative '../lib/parseapi'
class ResponseDecodingTest < Minitest::Test
 def test_default_response_and_retry
  calls=[]; body=File.read(File.join(__dir__,'fixtures/response-fixtures','clean-timezones.json'))
  client=ParseAPI::Client.new('fixture',retries:1,transport:lambda {|url,headers|calls << [url,headers];calls.size==1 ? [503,{'retry-after'=>'0'},'{"code":"unavailable"}'] : [200,{},body]})
  assert_equal JSON.parse(body),client.time_zones
  assert_equal 2,calls.size
  calls.each {|url,headers|refute headers.key?('Parse-Response');assert_equal '2.0.0',headers['Parse-Version'];assert_nil URI(url).query}
 end
end
