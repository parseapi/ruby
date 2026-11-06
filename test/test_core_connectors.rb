require 'minitest/autorun'
require 'json'
require_relative '../lib/parseapi'
class CoreConnectorsTest < Minitest::Test
 def test_dynamic_references_and_deep_stay_unchanged
  fixtures=JSON.parse(File.read(File.join(__dir__,'fixtures','core-connectors.json')))
  fixtures.each_value do |body|
   calls=[]
   client=ParseAPI::Client.new('fixture',retries:0,transport:lambda{|url,headers|calls << url;[200,{},JSON.generate(body)]})
   assert_equal body,client.country('US')
   assert_equal 1,calls.size
   assert_nil URI(calls[0]).query
  end
  assert_equal fixtures['point']['city_id'],fixtures['point']['deep']['city']['id']
  assert_equal 'US',fixtures['postal']['country']
  assert_equal ['00544'],fixtures['postal']['deep']['neighbors']
  refute fixtures['postal'].key?('neighbors')
  refute fixtures['postal'].key?('currency')
  assert_equal '0000320193',fixtures['company']['identifiers'][0]['value']
  assert_equal 0,fixtures['country']['capital_lat']
  assert_equal ['👍🏽'],fixtures['emoji']['variants']
  assert_equal '👍🏽',fixtures['emoji']['deep']['variants'][0]['emoji']
 end
end
