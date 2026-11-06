require 'minitest/autorun'
require 'json'
require 'parseapi'
class CountryCorrectedTest < Minitest::Test
  def test_corrected_country_is_returned_without_extra_lookup
    full=JSON.parse(File.read(File.join(__dir__,'fixtures/country-corrected.json')))
    calls=0
    client=ParseAPI::Client.new('fixture',transport:lambda { |url,headers| calls+=1; [200,{},JSON.generate(full)] })
    assert_equal full,client.country('US',deep:true)
    assert_equal 1,calls
    assert_equal 'United States of America',full['name_full']
    refute full.key?('full_name')
    assert full.key?('population')
    assert full.key?('area')
    assert_equal 'American',full['demonym']
    assert_equal '🇺🇸',full['flag']
    refute full.key?('emoji')
    assert_equal({'name'=>'Washington, D.C.','lat'=>38.89,'lon'=>-77.05},full['capital'])
    assert_equal({'name'=>nil,'rate'=>nil},full['tax'])
    assert_empty full.keys & %w[capital_lat capital_lon]
    refute full.key?('deep')
    assert_equal 'Americas',full['region']
    assert_equal 'Northern America',full['subregion']
    assert_equal 760,full['elevation_average']
    refute full.key?('deep')
  end
  def test_actual_antarctica_null_languages
    aq=JSON.parse(File.read(File.join(__dir__,'fixtures/country-aq.json')))
    client=ParseAPI::Client.new('fixture',transport:lambda { |url,headers| [200,{},JSON.generate(aq)] })
    value=client.country('AQ',deep:true)
    assert_equal aq,value
    assert_nil value['languages']
    %w[currency currency_name currency_symbol].each { |key| assert_nil value[key] }
    assert_equal 0,value['population']
  end

  def test_tax_reference_zeroes_and_deep_modes
    de=JSON.parse(File.read(File.join(__dir__,'fixtures/country-de.json')))
    assert_equal({'name'=>'VAT','rate'=>19},de['tax'])
    zero=Marshal.load(Marshal.dump(de));zero['capital']={'name'=>nil,'lat'=>0,'lon'=>0};zero['tax']={'name'=>nil,'rate'=>0}
    core=de.reject{|k,_|k=='deep'};locked=core.merge('deep'=>{});bodies=[de,zero,core,locked];calls=0
    client=ParseAPI::Client.new('fixture',transport:lambda{|_,_|calls+=1;[200,{},JSON.generate(bodies.shift)]})
    assert_equal de,client.country('DE',deep:true)
    assert_equal zero,client.country('DE',deep:true)
    assert_equal core,client.country('DE')
    assert_equal locked,client.country('DE',deep:true)
    assert_equal 4,calls
  end

end
