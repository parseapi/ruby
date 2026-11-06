require 'minitest/autorun'
require 'json'
require_relative '../lib/parseapi'

class DomainNullabilityTest < Minitest::Test
  def test_ordinary_domain_preserves_unknown_and_known_states
    [nil, false, true].each do |available|
      [{}, { 'dnssec' => nil }, { 'dnssec' => false }, { 'dnssec' => true }].each do |signing|
        body = { 'domain' => 'example.com', 'available' => available, 'deep' => available.nil? ? {} : { 'registration' => available ? { 'registered' => false } : { 'registered' => true }.merge(signing) } }
        calls = []
        client = ParseAPI::Client.new('fixture', transport: lambda { |url, headers| calls << [url, headers]; [200, {}, JSON.generate(body)] })
        assert_equal body, client.domain('example.com', deep: true)
        assert_equal 1, calls.size
        assert_equal 'https://api.parseapi.com/domain/example.com?deep=true', calls[0][0].to_s
        assert_equal '2.1.0', calls[0][1]['X-API-Version']
      end
    end
  end
end
