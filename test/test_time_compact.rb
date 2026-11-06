require 'minitest/autorun'
require 'json'
require_relative '../lib/parseapi'

class TimeCompactTest < Minitest::Test
 def test_approved_compact_time_bodies_pass_through
  rows=JSON.parse(File.read(File.join(__dir__,'fixtures/time-compact.json')))
  pending=rows.dup
  client=ParseAPI::Client.new('fixture',retries:0,transport:lambda {|_url,headers|
   assert_equal '2.1.0',headers['X-API-Version']
   [200,{},JSON.generate(pending.shift.fetch('body'))]
  })
  rows.each {|row| assert_equal row.fetch('body'),client.time,row.fetch('id')}
  assert_empty pending
 end
end
