require 'minitest/autorun'
require 'json'
require_relative '../lib/parseapi'

class TestCurrency < Minitest::Test
  def client(responses = [[200, {}, '{}']], retries: 0)
    @calls = []
    ParseAPI.new('test', retries: retries, transport: lambda { |url, headers|
      @calls << { url: url, headers: headers }
      raise 'Unexpected extra request' if responses.empty?
      responses.shift
    })
  end

  def params(index)
    URI.decode_www_form(URI(@calls[index][:url]).query || '').to_h
  end

  def test_original_rate_call_and_optional_source_evidence_preserve_server_values
    body = { 'base' => 'USD', 'quote' => 'EUR', 'rate' => 1e-10, 'date' => '2024-01-05', 'amount' => 1e15, 'converted' => 1.01, 'stale' => false, 'future' => true }
    parse = client([[200, {}, '{}'], [200, {}, JSON.generate(body)]])
    assert_equal({}, parse.currency_rate('USD', 'EUR'))
    assert_equal 'https://api.parseapi.com/currency/USD/EUR', @calls[0][:url]
    assert_equal body, parse.currency_rate('USD', 'EUR', date: '2024-01-05', amount: 1e15, )
    assert_equal({ 'date' => '2024-01-05', 'amount' => '1.0e+15' }, params(1))
    assert_equal '2.0.0', @calls[1][:headers]['Parse-Version']
    assert_equal 'test', @calls[1][:headers]['X-API-Key']
  end

  def test_sources_and_batch_preserve_unknowns_order_and_partial_coverage
    sources = { 'data' => [{ 'id' => 'nbp', 'available' => false, 'date' => nil, 'currencies' => [], 'history' => { 'from' => nil, 'to' => nil, 'currencies' => nil }, 'future' => true }] }
    batch = { 'base' => 'EUR', 'amount' => 1.005, 'rates' => { 'USD' => { 'rate' => 1.005, 'date' => '2024-01-05', 'converted' => 1.01 } }, 'missing' => [{ 'quote' => 'XCG', 'reason' => 'no_rate' }] }
    parse = client([batch].map { |body| [200, {}, JSON.generate(body)] })
    assert_equal batch, parse.currency_rates('EUR', %w[USD XCG], amount: 1.005, )
    assert_equal 'USD,XCG', params(0)['quotes']
    assert_equal 1, @calls.length
  end

  def test_pair_and_multi_history_keep_their_distinct_missing_shapes
    pair = { 'base' => 'EUR', 'quote' => 'USD', 'from' => '2024-01-01', 'to' => '2024-12-31', 'data' => [], 'missing' => ['2024-01-01'] }
    multi = { 'base' => 'EUR', 'quotes' => %w[USD TRL], 'data' => [{ 'requested_date' => '2004-12-31', 'quote' => 'TRL', 'converted' => nil }], 'missing' => [{ 'requested_date' => '2005-02-01', 'quote' => 'TRL', 'reason' => 'no_rate' }] }
    parse = client([pair, multi].map { |body| [200, {}, JSON.generate(body)] })
    assert_equal pair, parse.currency_history('EUR', 'USD', from: '2024-01-01', to: '2024-12-31')
    assert_equal multi, parse.currency_rates_history('EUR', %w[USD TRL], from: '2004-12-31', to: '2005-02-01', )
    assert_equal '/currency/EUR/rates/history', URI(@calls[1][:url]).path
    assert_equal 2, @calls.length
  end

  def test_invalid_new_controls_never_dispatch_and_exact_5000_budget_works
    parse = client
    quotes = Array.new(50) { |index| "Q#{(65 + index / 26).chr}#{(65 + index % 26).chr}" }
    [
      -> { parse.currency_rates('EUR', []) }, -> { parse.currency_rates('EUR', %w[USD usd]) },
      -> { parse.currency_rates('EUR', quotes + ['ZZZ']) }, -> { parse.currency_rates('EUR', ['USD'], amount: Float::INFINITY) },
      -> { parse.currency_rates('EUR', ['USD'], amount: 1e16) },
      -> { parse.currency_rates('EUR', ['USD'], date: '2999-01-01') },
      -> { parse.currency_history('EUR', 'USD', from: '1500-02-29', to: '1500-03-01') },
      -> { parse.currency_history('EUR', 'USD', from: '0000-01-01', to: '0000-01-02') },
      -> { parse.currency_history('EUR', 'USD', from: '2024-01-02', to: '2024-01-01') },
      -> { parse.currency_history('EUR', 'USD', from: '2024-01-01', to: '2025-01-01') },
      -> { parse.currency_rates_history('EUR', quotes, from: '2024-01-01', to: '2024-04-10') },
    ].each { |call| assert_raises(ArgumentError, &call) }
    assert_empty @calls
    parse.currency_rates_history('EUR', quotes, from: '2024-01-01', to: '2024-04-09')
    assert_equal 1, @calls.length
  end



  def test_indexed_units_retain_delivery
    fixture = JSON.parse(File.read(File.join(__dir__, 'fixtures/currency-reference.json')))
    parse = client([[200, {}, JSON.generate(fixture['indexed_pair'])]])
    pair = parse.currency_rate('USD', 'MXV', amount: 1)
    assert_equal 'indexed_unit', pair['units']['quote']; assert_equal fixture['indexed_pair']['converted'], pair['converted']
    assert_equal 1, @calls.length
  end

  def test_sampled_archive_and_complete_publication_summary
    f = JSON.parse(File.read(File.join(__dir__, 'fixtures/currency-summary.json')))
    parse = client([[200, {}, JSON.generate(f['sampled_history'])], [200, {}, JSON.generate(f['sampled_history'])], [200, {}, JSON.generate(f['summary'])]])
    history = parse.currency_history('USD','JPY',from:'1999-01-01',to:'2026-10-09',interval:'month', )
    assert_equal f['sampled_history'], history
    assert_equal ['1999-01-01'], history['missing']
    parse.currency_rates_history('USD',['JPY'],from:'1999-01-01',to:'2026-10-09',interval:'week', )
    report = parse.currency_rates_summary('USD',['EUR'],from:'1999-01-01',to:'1999-01-31',interval:'month', )
    assert_equal f['summary'], report
    assert_equal 20, report['data'][0]['observation_count']; assert_equal 3, report['data'][0]['missing_day_count']
    assert_equal '/currency/USD/rates/summary', URI(@calls[2][:url]).path
    assert_equal({'quotes'=>'EUR','from'=>'1999-01-01','to'=>'1999-01-31','interval'=>'month'}, params(2))
    assert_equal %w[month week month], (0..2).map { |i| params(i)['interval'] }
    assert_raises(ArgumentError) { parse.currency_history('USD','EUR',from:'1999-01-01',to:'1999-01-31',interval:'year') }
    assert_raises(ArgumentError) { parse.currency_rates_summary('USD',['EUR'],from:'1999-01-01',to:'1999-01-31',interval:'week') }
    assert_equal 3, @calls.length
  end

end
