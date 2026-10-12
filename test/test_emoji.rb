require 'minitest/autorun'
require 'json'
require_relative '../lib/parseapi'

class EmojiStub < ParseAPI::Client
  attr_reader :calls
  def initialize(payload)
    super('test', retries: 0)
    @payload = payload
    @calls = []
  end
  private
  def execute(uri, headers, method = 'GET', body = nil)
    @calls << {url: uri.to_s, headers: headers, method: method, body: body}
    [200, {}, JSON.generate(@payload)]
  end
end

class TestEmoji < Minitest::Test
  def test_catalog_and_private_text_body
    payload = {'total'=>2, 'emojis'=>[{'emoji'=>'👍🏿','name'=>'thumbs up','shortcodes'=>[],'category'=>nil,'occurrences'=>2,'positions'=>[{'start'=>2,'end'=>6},{'start'=>7,'end'=>11}],'deep'=>{'base'=>'👍','variants'=>[{'emoji'=>'👍🏿','tones'=>['dark']} ]}} ],'future'=>true}
    client = EmojiStub.new(payload)
    client.emoji(':cat:', shortcode_source: 'github')
    client.emoji_search('face', category: 'Smileys & Emotion', version:'17.0', max_version:'18.0', include_skin_tones:false, offset:0)
    client.emoji_browse(include_skin_tones:false, offset:2)
    client.emoji_categories
    assert_equal payload, client.emoji_parse('x 👍🏿 👍🏿', deep:true, lang:'fr')
    params = client.calls.map { |call| URI.decode_www_form(URI(call[:url]).query || '').to_h }
    assert_equal({'shortcode_source'=>'github'},params[0])
    assert_equal({'q'=>'face','category'=>'Smileys & Emotion','version'=>'17.0','max_version'=>'18.0','include_skin_tones'=>'false','offset'=>'0'},params[1])
    assert_equal({'include_skin_tones'=>'false','offset'=>'2'},params[2])
    assert_equal 'https://api.parseapi.com/emoji/categories',client.calls[3][:url]
    assert_equal 'POST',client.calls[4][:method]
    assert_equal({'text'=>'x 👍🏿 👍🏿'},JSON.parse(client.calls[4][:body]))
    assert_equal({'deep'=>'true','lang'=>'fr'},params[4])
    assert_equal '2.0.0',client.calls[4][:headers]['Parse-Version']
    assert_equal 5,client.calls.length
  end
  def test_full_download_metadata_and_artwork
    bundle = JSON.parse(File.read(File.join(__dir__, 'fixtures/emoji-catalog.json')))
    client = EmojiStub.new(bundle)
    result = client.emoji_catalog
    assert_equal 'https://api.parseapi.com/emoji/catalog?deep=true', client.calls[0][:url]
    assert_equal '❤️', result['forms']['❤']
    assert_equal({}, result['emojis'][0]['deep']['artwork'])
    client.emoji_catalog(deep:false, max_version:'17.0', include_skin_tones:false)
    assert_equal 'https://api.parseapi.com/emoji/catalog?deep=false&max_version=17.0&include_skin_tones=false', client.calls[1][:url]
    metadata = EmojiStub.new(bundle['metadata'])
    assert_equal 'Full source notice', metadata.emoji_metadata['notices'][0]['notice']
    assert_equal 'https://api.parseapi.com/emoji/metadata', metadata.calls[0][:url]
  end

  def test_private_conversion
    client=EmojiStub.new({'text'=>'🚀','unresolved'=>[]})
    assert_equal '🚀',client.emoji_convert(':rocket:',direction:'to_emoji',shortcode_source:'github')['text']
    assert_equal 1,client.calls.length
    assert_equal 'POST',client.calls[0][:method]
    assert_equal({'text'=>':rocket:'},JSON.parse(client.calls[0][:body]))
  end

end

class TestEmojiArtwork < Minitest::Test
  def test_keyed_svg_and_png_urls
    fixture = JSON.parse(File.read(File.join(__dir__, 'fixtures/emoji-artwork.json')))
    result = EmojiStub.new(fixture['emoji']).emoji('rocket', deep: true)
    artwork = result['deep']['artwork']
    assert_equal ['noto','twemoji','openmoji'], artwork.keys
    assert_equal 'https://cdn.parseapi.com/emoji/openmoji/17.0.0/1f680.svg', artwork['openmoji']['svg']
    assert_equal 'https://cdn.parseapi.com/emoji/openmoji/17.0.0/72/1f680.png', artwork['openmoji']['png']['72']
  end
end
