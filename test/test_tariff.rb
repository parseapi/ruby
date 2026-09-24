require 'minitest/autorun'
require 'json'
require_relative '../lib/parseapi'

class TariffFixtureClient < ParseAPI::Client
  attr_reader :url
  def initialize(body)
    super('test')
    @body = body
  end
  private
  def execute(uri, _headers)
    @url = uri
    [200, {}, JSON.generate(@body)]
  end
end

class TestTariff < Minitest::Test
  def test_search_preserves_parent_context_and_older_results
    [{}, { 'lineage' => nil }, { 'lineage' => [] }, { 'lineage' => ['Live horses', 'Other horses'] }].each do |extra|
      body = { 'q' => 'horses & ponies', 'revision' => 'fixture', 'lines' => [{ 'hts' => '0101.29.00.90', 'description' => 'Other', 'general' => nil, 'future' => true }.merge(extra)] }
      client = TariffFixtureClient.new(body)
      assert_equal body, client.tariff_search('horses & ponies')
      assert_equal '/tariff', client.url.path
      assert_equal({ 'q' => 'horses & ponies' }, URI.decode_www_form(client.url.query).to_h)
    end
  end
end

class TestTariff < Minitest::Test
  def test_edition_date_roundtrip
    edition = 'a' * 64
    body = { 'hts' => '0101', 'edition' => edition, 'date' => '2026-09-15', 'deep' => { 'effective_rate' => nil, 'reason' => 'future_reason', 'measures' => [] } }
    client = TariffFixtureClient.new(body)
    assert_equal body, client.tariff('0101', deep: true, origin: 'CA', edition: edition, date: '2026-09-15')
    assert_equal({ 'deep' => 'true', 'origin' => 'CA', 'edition' => edition, 'date' => '2026-09-15' }, URI.decode_www_form(client.url.query).to_h)
    assert_equal body, client.tariff_search('horses', edition: edition, date: '2026-09-15')
    assert_equal({ 'q' => 'horses', 'edition' => edition, 'date' => '2026-09-15' }, URI.decode_www_form(client.url.query).to_h)
    client = TariffFixtureClient.new(body.merge('date' => nil))
    client.tariff('0101', edition: edition)
    assert_equal({ 'edition' => edition }, URI.decode_www_form(client.url.query).to_h)
  end
end

class TestTariff < Minitest::Test
  def test_ignored_selection_is_rejected
    client = TariffFixtureClient.new({ 'revision' => 'old' })
    assert_equal 'tariff_selection_mismatch', assert_raises(ParseAPI::Error) { client.tariff('0101', edition: 'a' * 64) }.code
    assert_equal 'tariff_selection_mismatch', assert_raises(ParseAPI::Error) { client.tariff_search('horses', date: '2026-09-15') }.code
  end

  def test_date_selection_rejects_invalid_returned_edition
    ['legacy', '', 'A' * 64, 'a' * 64 + "\n"].each do |edition|
      client = TariffFixtureClient.new({ 'edition' => edition, 'date' => '2026-09-15' })
      [proc { client.tariff('0101', date: '2026-09-15') }, proc { client.tariff_search('horses', date: '2026-09-15') }].each do |call|
        error = assert_raises(ParseAPI::Error, &call)
        assert_equal 'tariff_selection_mismatch', error.code
        assert_equal 0, error.status
      end
    end
  end
end
