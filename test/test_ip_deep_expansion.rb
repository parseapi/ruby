require 'minitest/autorun'
require 'json'
require_relative '../lib/parseapi'
class IPDeepExpansionTest < Minitest::Test
 def test_all_new_fields_pass_through_one_request
  body=JSON.parse(File.read(File.join(__dir__,'fixtures','ip-deep-expansion.json')));calls=[]
  client=ParseAPI::Client.new('fixture',retries:0,transport:lambda{|url,headers|calls << url;[200,{},JSON.generate(body)]})
  assert_equal body,client.ip(body['ip'],deep:true);assert_equal 1,calls.length;assert_includes URI(calls[0]).query,'deep=true'
  assert_equal 0,body['deep']['latitude'];assert_equal false,body['deep']['proxy'];assert_equal '00123',body['deep']['postal']
 end
end
