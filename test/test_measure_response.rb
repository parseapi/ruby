require 'minitest/autorun'
require 'json'
require_relative '../lib/parseapi'

class TestMeasureResponse < Minitest::Test
  def test_clean_and_legacy_measure_responses
    JSON.parse(File.read(File.join(__dir__, 'fixtures/measure-response.json'))).each do |body|
      client = ParseAPI::Client.new('fixture', transport: ->(*_) { [200, {}, JSON.generate(body)] })
      assert_equal body, client.measure(body['measure'])
    ensure
      client&.close
    end
  end
end
