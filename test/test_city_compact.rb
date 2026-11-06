require 'minitest/autorun'
require 'json'
require_relative '../lib/parseapi'

class CityCompactTest < Minitest::Test
 def test_compact_matches_keep_city_facts_and_cursor
  rows=JSON.parse(File.read(File.join(__dir__,'fixtures/noise-approved.json'))).select {|row| row.fetch('id').start_with?('city-')}
  pending=rows.dup
  client=ParseAPI::Client.new('fixture',retries:0,transport:lambda {|_url,headers|
   assert_equal '2.1.0',headers['X-API-Version']
   [200,{},JSON.generate(pending.shift.fetch('body'))]
  })
  rows.each do |row|
   body=row.fetch('body'); result=client.city_search(body.fetch('q'),match:body.fetch('match'))
   assert_equal body.fetch('data'),result.fetch('cities')
   assert_equal body.fetch('next_cursor'),result.fetch('next_cursor')
  end
  assert_empty pending
 end
end
