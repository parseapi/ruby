require 'minitest/autorun'
require 'json'
require_relative '../lib/parseapi'
class TimeGapsFixture < ParseAPI::Client
 attr_reader :calls
 def initialize
  super('fixture'); @calls=[]
 end
 private
 def execute(uri,_headers)
  @calls << URI.decode_www_form(uri.query || '').to_h
  [200,{},JSON.generate({'timezone'=>nil,'targets'=>nil,'location'=>{'status'=>'ambiguous','candidates'=>[]},'deep'=>{'dst_offset_seconds'=>-3600,'season'=>nil}})]
 end
end
class TestTimeGaps < Minitest::Test
 def test_source_selection_false_catalog_filters_and_unchanged_observations
  client=TimeGapsFixture.new
  result=client.time_zones(nil,country:'US',area:'America',offset:'+00:00',abbreviation:'UTC',dst:false,observes_dst:false,at:'1970-01-01T00:00:00Z',details:true,sort:'offset')
  assert_equal({'country'=>'US','area'=>'America','offset'=>'+00:00','abbreviation'=>'UTC','dst'=>'false','observes_dst'=>'false','at'=>'1970-01-01T00:00:00Z','details'=>'true','sort'=>'offset'},client.calls.last)
  [{ip:'2001:db8::1'},{city:'Springfield',country:'US',state:'IL'},{country:'US'},{iata:'JFK'},{icao:'KJFK'},{unlocode:'US NYC'},{address:'1 Main Street',country:'US',state:'NY'}].each do |source|
   assert_equal result,client.time(**source)
   assert_equal source.transform_keys(&:to_s),client.calls.last
  end
  count=client.calls.length
  [{ip:'8.8.8.8',city:'Paris'},{ip:'8.8.8.8',country:'US'},{state:'NY'},{city:'Paris',state:'IDF'},{address:'a'},{ip:''}].each {|source| assert_raises(ArgumentError){client.time(**source)}}
  assert_raises(ArgumentError){client.time('UTC',city:'Paris')}
  assert_equal count,client.calls.length
 end
end
