require 'minitest/autorun'
require 'json'
require 'uri'
require_relative '../lib/parseapi'

class TestCityQueries < Minitest::Test
  def test_filters_encode_zero_dateline_and_opaque_cursor
    calls = []
    client = ParseAPI::Client.new('fixture', retries: 0, transport: ->(url, *_args) { calls << url; [200, {}, '{}'] })
    filters = { min_population: 0, max_population: 5000000, timezone: 'Asia/Tokyo', bbox: '170,-20,-170,20', sort: 'population', order: 'desc', cursor: 'opaque+/=cursor?&' }
    client.city_list(country: 'JP', limit: 5, hierarchy: true, **filters)
    client.city_nearby_coords(0, 0, radius: 20, unit: 'mi', country: 'JP', state: '27', **filters)
    client.city_search('Sak', page: true, **filters)
    client.city_nearby('Sakai', page: true, **filters)
    calls.each_with_index do |url, index|
      uri = URI(url)
      assert_equal(index == 3 ? '/city/Sakai/nearby' : '/city', uri.path)
      query = URI.decode_www_form(uri.query).to_h
      filters.each { |name, value| assert_equal value.to_s, query[name.to_s] }
      index < 2 ? (refute query.key?('page')) : (assert_equal 'true', query['page'])
    end
    browse = URI.decode_www_form(URI(calls[0]).query).to_h
    assert_equal 'true', browse['browse']
    coords = URI.decode_www_form(URI(calls[1]).query).to_h
    assert_equal 'true', coords['nearby']; assert_equal '0', coords['lat']; assert_equal '0', coords['lon']
  end

  def test_new_defaults_and_cursor_only_omit_other_options
    calls = []
    client = ParseAPI::Client.new('fixture', retries: 0, transport: ->(url, *_args) { calls << url; [200, {}, '{}'] })
    client.city_list; client.city_nearby_coords(0, 0); client.city_search('Sak', cursor: 'opaque')
    ['browse=true&format=list', 'lat=0&lon=0&nearby=true&format=list', 'q=Sak&cursor=opaque'].each_with_index do |expected, index|
      assert_equal URI.decode_www_form(expected).to_h, URI.decode_www_form(URI(calls[index]).query).to_h
    end
  end

  def test_pagination_passes_through_and_cursor_errors_keep_existing_type
    body = { 'cities' => [{ 'id' => 'city_one', 'name' => 'One' }], 'next_cursor' => nil, 'future' => true }
    client = ParseAPI::Client.new('fixture', retries: 0, transport: ->(*_args) { [200, {}, JSON.generate(body)] })
    assert_equal body, client.city_list
    error = { 'code' => 'invalid_request', 'message' => 'Cursor does not match this query.', 'docs' => 'https://parseapi.com/docs/city', 'request_id' => 'req_fixture' }
    client = ParseAPI::Client.new('fixture', retries: 0, transport: ->(*_args) { [400, {}, JSON.generate(error)] })
    caught = assert_raises(ParseAPI::Error) { client.city_search('Sak', cursor: 'bad') }
    assert_equal 400, caught.status; assert_equal 'invalid_request', caught.code
  end
end
