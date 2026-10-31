require 'minitest/autorun'
require 'json'
require_relative '../lib/parseapi'
class IsoContractTest < Minitest::Test
 def test_both_iso_contracts_use_existing_methods_and_preserve_raw_values
  samples=JSON.parse(File.read(File.join(__dir__,'fixtures','iso-contract.json')))
  samples.each do |sample|
   calls=[]
   client=ParseAPI::Client.new('fixture',retries:0,transport:lambda{|url,headers|calls << url;[200,{},JSON.generate(sample['body'])]})
   options={deep:sample['deep']}
   options[:country]=sample['country'] if sample.key?('country')
   result=client.public_send(sample['operation'],sample['code'],**options)
   assert_equal sample['body'],result
   assert_equal 1,calls.size
   assert_equal "/#{sample['operation']}/#{sample['code']}",URI(calls[0]).path
   depth=URI.decode_www_form(URI(calls[0]).query||'').to_h['deep']
   sample['deep'] ? assert_equal('true',depth) : assert_nil(depth)
  end
 end
end
