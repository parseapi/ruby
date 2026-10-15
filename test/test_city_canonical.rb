require 'minitest/autorun'
require_relative '../lib/parseapi'

class TestCityCanonical < Minitest::Test
  def test_sparse_lists_filters_relations_and_zero_unknown_distance
    calls = []; id = 'city_7aj899nvwyku'
    payload = {'object'=>'list','data'=>[{'id'=>id,'object'=>'city','name'=>'Vienna'}],'has_more'=>true,'url'=>'/city','next_cursor'=>'opaque+/='}
    client = ParseAPI::Client.new('fixture', retries: 0, transport: ->(url, *_args) { calls << url; [200, {}, JSON.generate(payload)] })
    assert_equal payload, client.city_list(countries: ['AT','CH'], exclude_countries: ['JP'], timezones: ['Europe/Vienna'], min_elevation: -10, max_elevation: 0, min_population: 0, sort: '-population,+name', cursor: 'opaque+/=')
    query = URI.decode_www_form(URI(calls.last).query).to_h
    {'format'=>'list','countries'=>'AT,CH','exclude_countries'=>'JP','timezones'=>'Europe/Vienna','min_elevation'=>'-10','max_elevation'=>'0','min_population'=>'0','sort'=>'-population,+name','cursor'=>'opaque+/='}.each { |k,v| assert_equal v,query[k] }
    %w[children ancestors siblings].each do |relation|
      payload = {'object'=>'list','data'=>[],'has_more'=>false,'url'=>"/city/id/#{id}/#{relation}",'next_cursor'=>nil,'city_id'=>id,'relationship'=>relation,'coverage'=>'partial'}
      assert_equal payload,client.public_send("city_#{relation}",id,)
      assert_equal "/city/id/#{id}/#{relation}",URI(calls.last).path
    end
    [0,nil].each do |value|
      payload = {'object'=>'city_distance','from'=>id,'to'=>id,'distance'=>value,'distance_mi'=>value,'method'=>'great_circle'}
      assert_equal payload,client.city_distance(id,id); assert_nil URI(calls.last).query
    end
    client.city('Vienna',format: 'resource'); assert_equal 'resource',URI.decode_www_form(URI(calls.last).query).to_h['format']
    client.city('Vienna'); assert_nil URI(calls.last).query
  end

  def test_explicit_matching_retains_suggestion_evidence
    url=nil;body={'object'=>'list','data'=>[{'id'=>'city_7aj899nvwyku','object'=>'city','match'=>{'type'=>'fuzzy','source'=>'name','value'=>'Vienna','language'=>nil,'edit_distance'=>1}}],'has_more'=>false,'url'=>'/city','next_cursor'=>nil}
    c=ParseAPI::Client.new('fixture',transport:->(value,*args){url=value;[200,{},JSON.generate(body)]})
    assert_equal body,c.city_search('Viena',format:'list',match:'fuzzy',max_distance:1);assert_equal({'q'=>'Viena','format'=>'list','match'=>'fuzzy','max_distance'=>'1'},URI.decode_www_form(URI(url).query).to_h);c.city_search('Vi');assert_equal({'q'=>'Vi'},URI.decode_www_form(URI(url).query).to_h)
  end

  def test_bounded_choices_only_on_matching409_and_ordinary_errors_unchanged
    safe = {'id'=>'city_7aj899nvwyku','object'=>'city','name'=>'Vienna','state'=>nil}
    [[409,'ambiguous_city',true],[400,'ambiguous_city',false],[409,'invalid_request',false],[429,'rate_limited',false]].each do |status,code,present|
      calls=0; client = ParseAPI::Client.new('fixture',retries: 0,transport: ->(*) { calls+=1; [status,{'retry-after'=>'60'},JSON.generate({'code'=>code,'message'=>'Choose','candidates'=>[safe.merge('deep'=>{}),safe,safe]})] })
      error=assert_raises(ParseAPI::Error) { client.city('Vienna',ambiguity: 'error') }
      assert_equal status,error.status; assert_equal code,error.code; assert_equal '60',error.retry_after
      assert_equal present,error.instance_variable_defined?(:@candidates); assert_equal [safe,safe],error.candidates if present
      assert_equal 1,calls
    end
  end

  def test_reviewed_romanized_optin_and_null
    url=nil;payload={'id'=>'city_7aj899nvwyku','object'=>'city','name_romanized'=>'Kitakyūshū','romanization_language'=>'ja-Latn'};c=ParseAPI::Client.new('fixture',transport:->(value,*){url=value;[200,{},JSON.generate(payload)]})
    assert_equal payload,c.city_id('city_7aj899nvwyku',format:'resource',romanized:true);assert_equal({'format'=>'resource','romanized'=>'true'},URI.decode_www_form(URI(url).query).to_h);payload['name_romanized']=nil;payload['romanization_language']=nil;assert_equal payload,c.city_id('city_7aj899nvwyku',format:'resource',romanized:true)
  end

  def test_explicit_spelling_route_and_classic_adapter
    calls=[];row={'id'=>'city_7aj899nvwyku','object'=>'city','name'=>'Vienna'}
    c=ParseAPI::Client.new('fixture',retries:0,transport:->(url,*_args){path=URI(url).path;calls<<path;[200,{},JSON.generate(path=='/city/search'?{'object'=>'list','data'=>[row],'q'=>'Viena','has_more'=>false,'url'=>'/city/search','next_cursor'=>nil}:{'q'=>'Vi','cities'=>[row]})]})
    assert_equal [row],c.city_search('Viena',match:'fuzzy',max_distance:1)['cities']
    assert_equal [row],c.city_search('Viena',match:'fuzzy',format:'list')['data']
    assert_equal [row],c.city_search('Vi')['cities'];assert_equal ['/city/search','/city/search','/city'],calls
  end

end
