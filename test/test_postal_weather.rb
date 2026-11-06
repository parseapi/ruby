require 'minitest/autorun'
require 'json'
require_relative '../lib/parseapi'

class PostalWeatherTest < Minitest::Test
  def test_raw_postal_and_weather_responses_remain_unchanged
    fixtures = JSON.parse(File.read(File.join(__dir__, 'fixtures', 'postal-weather.json')))
    bodies = fixtures.values
    calls = []
    client = ParseAPI::Client.new('fixture', transport: lambda { |url, headers|
      index = calls.length
      calls << [url, headers]
      [200, {}, JSON.generate(bodies[index])]
    })
    fixtures.each do |name, expected|
      actual = name.start_with?('weather') ? client.weather(0, 0, deep: true) : client.postal('10001', country: 'US', deep: true)
      assert_equal expected, actual
    end
    assert_equal fixtures.length, calls.length
    calls.each { |_url, headers| assert_equal "parseapi-ruby/#{ParseAPI::VERSION}", headers['User-Agent'] }
    assert_equal({ 'annual_median' => 0 }, fixtures['postal_compact']['property_tax'])
    assert_nil fixtures['weather_current']['forecast']
    assert_equal [], fixtures['weather_current']['alerts']
  end
end
