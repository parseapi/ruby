require 'minitest/autorun'
require 'json'
require_relative '../lib/parseapi'
class CountyTest < Minitest::Test
 def test_canonical_and_deprecated_calls_keep_county_fields
  calls=[]; county={'county'=>'E09000033','iso_code'=>'GB-WSM','type'=>'district','population'=>0,'county_name_local'=>nil}
  listing={'state'=>'ENG','country'=>'GB','counties'=>[county]}
  client=ParseAPI::Client.new('fixture',transport:lambda {|url,headers|
   calls << URI(url).path; assert_equal '2.2.0',headers['X-API-Version']
   [200,{},JSON.generate(URI(url).path.end_with?('/counties') ? listing : county)]
  })
  assert_equal county,client.county('Westminster',country:'GB')
  assert_equal county,client.district('Westminster',country:'GB')
  assert_equal listing,client.state_counties('ENG',country:'GB')
  assert_equal listing,client.state_districts('ENG',country:'GB')
  assert_equal ['/county/Westminster','/county/Westminster','/state/ENG/counties','/state/ENG/counties'],calls
 end
end
