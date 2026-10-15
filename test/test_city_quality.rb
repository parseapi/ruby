require 'minitest/autorun'
require 'json'
require 'uri'
require_relative '../lib/parseapi'

class TestCityQuality < Minitest::Test
  def test_options_preserve_existing_calls
    calls = []
    client = ParseAPI::Client.new('fixture', retries: 0, transport: ->(url, *_args) { calls << url; [200, {}, '{}'] })
    client.city('Wien', country: 'AT', state: '9', deep: true, lang: 'de')
    client.city_id('city_pin', deep: true, lang: 'de')
    client.city_search('Wie', country: 'AT', state: '9', limit: 5, deep: true, lang: 'de')
    client.city_nearest(48, 16, deep: true, lang: 'de')
    client.city_nearby('Wien', radius: 5, unit: 'km', country: 'AT', state: '9', limit: 3, deep: true, lang: 'de')
    calls.each do |url|
      query = URI.decode_www_form(URI(url).query || '').to_h
      refute query.key?('hierarchy')
      refute query.key?('type')
      assert_equal 'true', query['deep']
      assert_equal 'de', query['lang']
    end
    opts = { type: 'city', grain: 'municipality', hierarchy: true }
    client.city('Wien', **opts, aliases: true, ambiguity: 'error')
    client.city_id('city_pin', hierarchy: true)
    client.city_search('Wie', **opts, aliases: true)
    client.city_nearest(48, 16, **opts, country: 'AT', state: '9')
    client.city_nearby('Wien', **opts, aliases: true, ambiguity: 'error')
    calls.drop(5).each_with_index do |url, index|
      query = URI.decode_www_form(URI(url).query || '').to_h
      assert_equal 'true', query['hierarchy']
      assert_equal 'city', query['type'] unless index == 1
      assert_equal 'municipality', query['grain'] unless index == 1
      assert_equal 'true', query['aliases'] if [0, 2, 4].include?(index)
      assert_equal 'error', query['ambiguity'] if [0, 4].include?(index)
    end
    nearest = URI.decode_www_form(URI(calls[8]).query).to_h
    assert_equal 'AT', nearest['country']
    assert_equal '9', nearest['state']
  end

  def test_hierarchy_and_ambiguity_preserve_nullable_data_and_errors
    body = { 'id' => 'city_child', 'grain' => 'subdivision', 'parent' => { 'id' => 'city_parent', 'name' => nil, 'name_local' => '堺市', 'country' => 'JP', 'state' => 'JP-27', 'type' => 'city', 'grain' => 'municipality', 'future' => true } }
    client = ParseAPI::Client.new('fixture', retries: 0, transport: ->(*_args) { [200, {}, JSON.generate(body)] })
    assert_equal body, client.city_id('city_child', hierarchy: true)
    error = { 'code' => 'invalid_request', 'message' => 'City name matches multiple places.', 'docs' => 'https://parseapi.com/docs/city', 'request_id' => 'req_fixture' }
    client = ParseAPI::Client.new('fixture', retries: 0, transport: ->(*_args) { [400, {}, JSON.generate(error)] })
    caught = assert_raises(ParseAPI::Error) { client.city('Sakai', ambiguity: 'error') }
    assert_equal 400, caught.status
    assert_equal 'invalid_request', caught.code
  end
end
