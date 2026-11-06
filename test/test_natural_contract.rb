require 'minitest/autorun'
require 'json'
require 'parseapi'

class NaturalContractTest < Minitest::Test
  def test_explicit_email_verification_uses_private_post_and_root_result
    calls = []
    result = { 'email' => 'a+b@example.com', 'valid' => true, 'deliverable' => false, 'catchall' => nil, 'future' => 0 }
    client = ParseAPI::Client.new('fixture', transport: lambda { |url, headers, method = 'GET', body = nil|
      calls << [URI(url), headers, method, body]
      [200, {}, JSON.generate(result)]
    })
    assert_equal result, client.email(result['email'])
    assert_equal result, client.email_verify(result['email'])
    assert_equal result, client.email(result['email'], deep: true)
    assert_equal 'GET', calls[0][2]
    calls.drop(1).each do |url, headers, method, body|
      assert_equal '/email/verify', url.path
      assert_nil url.query
      assert_equal '2.1.0', headers['X-API-Version']
      assert_equal 'POST', method
      assert_equal({ 'email' => result['email'] }, JSON.parse(body))
    end
    refute result.key?('deep')
  end

  def test_verification_has_no_automatic_retry
    calls = 0
    client = ParseAPI::Client.new('fixture', transport: lambda { |*_args|
      calls += 1
      [503, { 'retry-after' => '0' }, '{"code":"unavailable","message":"Unavailable"}']
    })
    assert_raises(ParseAPI::Error) { client.email_verify('person@example.com') }
    assert_equal 1, calls
  end
end
