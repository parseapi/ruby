require 'minitest/autorun'
require 'json'
require_relative '../lib/parseapi'

class CompanyDirectoryStub < ParseAPI::Client
  attr_reader :calls
  def initialize(responses, **options)
    super('company_fixture', **options)
    @calls = []
    @responses = responses
  end
  private
  def execute(uri, headers)
    @calls << { url: uri.to_s, headers: headers }
    raise 'Unexpected request' if @responses.empty?
    status, body = @responses.shift
    [status, { 'retry-after' => '0' }, JSON.generate(body)]
  end
end

class TestCompanyDirectory < Minitest::Test
  BASE = { 'id' => 'co_caczn6wf36hj', 'name' => 'GitLab', 'country' => 'US', 'website' => nil, 'listings' => [], 'address' => nil, 'future' => { 'unknown' => nil } }.freeze
  RICH = { 'description' => nil, 'logo' => 'https://example.com/logo.svg', 'socials' => [], 'founded' => { 'value' => '2011', 'precision' => 'future_precision' }, 'sources' => [{ 'type' => 'future_source', 'url' => 'https://example.com/', 'fields' => ['logo'], 'observed_at' => nil, 'updated_at' => nil, 'future' => true }], 'parent' => nil, 'future' => [nil, {}] }.freeze

  def params(client, index)
    URI.decode_www_form(URI(client.calls[index][:url]).query || '').to_h
  end

  def test_selector_encoding_filters_and_coverage
    cases = [
      [->(p) { p.company_id('co_/é?+', deep: true) }, '/company/id/co_%2F%C3%A9%3F%2B', { 'deep' => 'true' }],
      [->(p) { p.company_id('co_caczn6wf36hj') }, '/company/id/co_caczn6wf36hj', {}],
      [->(p) { p.company_search(query: 'Café & Co', country: 'us', limit: 2, cursor: 'a+/=?&', deep: true) }, '/company', { 'q' => 'Café & Co', 'country' => 'us', 'limit' => '2', 'cursor' => 'a+/=?&', 'deep' => 'true' }],
      [->(p) { p.company_search(domain: 'WWW.Example.COM.') }, '/company', { 'domain' => 'WWW.Example.COM.' }],
      [->(p) { p.company_search(ticker: 'BRK/B', exchange: 'X/Y') }, '/company', { 'ticker' => 'BRK/B', 'exchange' => 'X/Y' }],
      [->(p) { p.company_search(identifier: '0000/123', authority: 'US/SEC', country: 'US') }, '/company', { 'identifier' => '0000/123', 'authority' => 'US/SEC', 'country' => 'US' }],
      [->(p) { p.company_search(query: '', limit: 0, cursor: '') }, '/company', { 'q' => '', 'limit' => '0', 'cursor' => '' }],
      [->(p) { p.company_search(country: 'US') }, '/company', { 'country' => 'US' }],
      [->(p) { p.company_search(industry: '0700', industry_type: 'sic') }, '/company', { 'industry' => '0700', 'industry_type' => 'sic' }],
      [->(p) { p.company_search(country: 'US', industry: '0700', industry_type: 'sic', cursor: 'opaque+/=', limit: 2, deep: true) }, '/company', { 'country' => 'US', 'industry' => '0700', 'industry_type' => 'sic', 'cursor' => 'opaque+/=', 'limit' => '2', 'deep' => 'true' }],
      [->(p) { p.company_search(query: 'Example', industry: '0700', industry_type: 'sic', deep: false) }, '/company', { 'q' => 'Example', 'industry' => '0700', 'industry_type' => 'sic' }],
      [->(p) { p.company_search(registration_authority: 'ra000599') }, '/company', { 'registration_authority' => 'ra000599' }],
      [->(p) { p.company_search(country: 'US', industry: '0700', industry_type: 'sic', registration_authority: 'RA000599', registration_form: 'DPC', registration_status: ' Good Standing ', limit: 2, cursor: 'opaque+/=', deep: true) }, '/company', { 'country' => 'US', 'industry' => '0700', 'industry_type' => 'sic', 'registration_authority' => 'RA000599', 'registration_form' => 'DPC', 'registration_status' => ' Good Standing ', 'limit' => '2', 'cursor' => 'opaque+/=', 'deep' => 'true' }],
      [->(p) { p.company_search(identifier: '00001', authority: 'SEC', registration_authority: 'RA000599', registration_form: 'future/Form', registration_status: 'future+& status', deep: false) }, '/company', { 'identifier' => '00001', 'authority' => 'SEC', 'registration_authority' => 'RA000599', 'registration_form' => 'future/Form', 'registration_status' => 'future+& status' }],
      [->(p) { p.company_coverage }, '/company/directory/coverage', {}]
    ]
    cases.each do |call, path, expected|
      body = { 'companies' => [], 'next' => nil, 'future' => nil }
      client = CompanyDirectoryStub.new([[200, body]])
      assert_equal body, call.call(client)
      assert_equal 1, client.calls.length
      assert_equal path, URI(client.calls[0][:url]).path
      assert_equal expected, params(client, 0)
      assert_equal '2.0.0', client.calls[0][:headers]['Parse-Version']
      assert_equal 'company_fixture', client.calls[0][:headers]['X-API-Key']
    end
  end

  def test_deep_triad_unknown_null_fields_pagination_and_coverage
    profiles = [BASE, BASE.merge('deep' => {}), BASE.merge('deep' => RICH), BASE.merge('deep' => { 'description' => nil, 'logo' => nil, 'socials' => nil, 'founded' => nil, 'sources' => nil })]
    page = { 'companies' => profiles.map { |p| p.merge('match' => { 'field' => 'future_field', 'value' => nil }) }, 'next' => 'opaque+/=', 'future' => nil }
    empty = { 'companies' => [], 'next' => nil }
    coverage = { 'scope' => 'future_scope', 'companies' => 0, 'countries' => [], 'future' => nil }
    client = CompanyDirectoryStub.new((profiles + [page, empty, coverage]).map { |body| [200, body] })
    profiles.each_with_index { |profile, i| assert_equal profile, client.company_id(BASE['id'], deep: i > 0) }
    assert_equal page, client.company_search(query: 'GitLab', limit: 4, deep: true)
    assert_equal empty, client.company_search(query: 'GitLab', limit: 4, cursor: page['next'], deep: true)
    assert_equal coverage, client.company_coverage
    assert_equal 7, client.calls.length
    assert_equal({ 'q' => 'GitLab', 'limit' => '4', 'cursor' => 'opaque+/=', 'deep' => 'true' }, params(client, 5))
  end

  def test_api_validation_and_not_found_errors
    [[400, ->(p) { p.company_search(query: 'A', domain: 'B') }], [400, ->(p) { p.company_search }], [404, ->(p) { p.company_id('co_unknown') }]].each do |status, call|
      code = status == 400 ? 'invalid_request' : 'not_found'
      client = CompanyDirectoryStub.new([[status, { 'code' => code, 'message' => 'source error', 'request_id' => 'r1', 'docs' => nil }]])
      error = assert_raises(ParseAPI::Error) { call.call(client) }
      assert_equal [status, code, 'r1'], [error.status, error.code, error.request_id]
      assert_equal 1, client.calls.length
    end
  end

  def test_national_number_and_retry_controls_remain_unchanged
    body = { 'valid' => true, 'company' => '51824753556', 'deep' => { 'activity' => nil } }
    client = CompanyDirectoryStub.new([[200, body]])
    assert_equal body, client.company('51 824 753 556', country: 'AU', deep: true, lang: 'fr')
    assert_equal '/company/51%20824%20753%20556', URI(client.calls[0][:url]).path
    assert_equal({ 'country' => 'AU', 'deep' => 'true', 'lang' => 'fr' }, params(client, 0))
    client = CompanyDirectoryStub.new([[503, {}], [503, {}], [200, BASE]])
    assert_equal BASE, client.company_id(BASE['id'], deep: true)
    assert_equal 3, client.calls.length
    client = CompanyDirectoryStub.new([[503, {}]], retries: 0)
    assert_raises(ParseAPI::Error) { client.company_coverage }
    assert_equal 1, client.calls.length
  end

  def test_directory_does_not_accept_lang
    client = CompanyDirectoryStub.new([])
    assert_raises(ArgumentError) { client.company_id(BASE['id'], lang: 'fr') }
    assert_raises(ArgumentError) { client.company_search(query: 'A', lang: 'fr') }
    assert_empty client.calls
  end

  def test_readme_recipe_uses_explicit_selection_and_returned_cursor
    section = File.read(File.join(__dir__, '../README.md')).split("## Company directory\n", 2)[1]
    code = section.match(/```ruby\n(.*?)```/m)[1]
    parse = CompanyDirectoryStub.new([[200, { 'companies' => [BASE], 'next' => 'opaque+/=' }], [200, BASE.merge('deep' => RICH)], [200, { 'companies' => [], 'next' => nil }], [200, { 'scope' => 'sample' }]])
    eval(code, binding, 'README.md')
    assert_equal 4, parse.calls.length
    assert_equal '/company/id/co_caczn6wf36hj', URI(parse.calls[1][:url]).path
    assert_equal 'opaque+/=', params(parse, 2)['cursor']
  end
  def test_employee_observations_preserve_zero_false_dates_and_future_codes
    values = [
      {}, { 'employees' => nil },
      { 'employees' => { 'count' => 0, 'as_of' => '2025-12-31', 'scope' => 'legal_entity', 'method' => 'reported', 'approximate' => false } },
      { 'employees' => { 'count' => 12500, 'as_of' => '2026-06-30', 'scope' => 'consolidated_group', 'method' => 'reported', 'approximate' => true } },
      { 'employees' => { 'count' => 7, 'as_of' => '2026-01-15', 'scope' => 'future_scope', 'method' => 'future_method', 'approximate' => false, 'future' => nil } }
    ]
    values.each do |deep|
      profile = BASE.merge('deep' => deep)
      page = { 'companies' => [profile.merge('match' => { 'field' => 'name', 'value' => BASE['name'] })], 'next' => nil }
      client = CompanyDirectoryStub.new([[200, profile], [200, page]])
      result = client.company_id(BASE['id'], deep: true)
      assert_equal profile, result
      assert_equal deep.key?('employees'), result['deep'].key?('employees')
      assert_equal page, client.company_search(query: BASE['name'], deep: true)
      assert_equal 2, client.calls.length
    end
  end

  def test_registrations_preserve_source_roles_nulls_and_leading_zeros
    registration = JSON.parse('{"authority":"RA000599","number":"0001234567","jurisdiction":{"country":"US","state":"CO"},"role":"domestic","legal_form":{"code":"DNC","name":"Domestic Non-profit Corporation"},"status":"Good Standing","formation_date":"2004-02-29","address":{"kind":"principal","line1":"12 Main St.","line2":"Suite 2","city":"Example","state":"CO","postal":"00123-0001","country_raw":"US"},"future":"retained"}')
    [{}, { 'registrations' => nil }, { 'registrations' => [] }, { 'registrations' => [registration] }, { 'registrations' => [registration.merge('role' => 'future_role', 'formation_date' => nil, 'address' => nil)] }].each do |deep|
      profile = BASE.merge('deep' => deep)
      page = { 'companies' => [profile.merge('match' => { 'field' => 'identifier', 'value' => registration['number'] })], 'next' => nil }
      client = CompanyDirectoryStub.new([[200, profile], [200, page]])
      assert_equal profile, client.company_id(BASE['id'], deep: true)
      assert_equal page, client.company_search(identifier: registration['number'], authority: registration['authority'], deep: true)
      assert_equal 2, client.calls.length
    end
  end

end
