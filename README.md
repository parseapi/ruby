```bash
gem install parseapi
```

```ruby
require 'parseapi'

parse = ParseAPI.new('your-api-key')
country = parse.country('US')
```

Get a key at [parseapi.com](https://parseapi.com). The client also reads `PARSEAPI_KEY` from the environment.

## Calls

One method per endpoint, named after the route.

```ruby
parse.ip('8.8.8.8')
parse.ip_self
parse.email('hello@gmail.com')
parse.vat('DE136695976')
parse.iban('DE89370400440532013000')
parse.npi('1881018208')
parse.phone('+14155552671')
parse.carrier('+14155552671')
parse.caller('+14155552671')
parse.hlr('+14155552671')
parse.postal('SW1A 1AA')
parse.postal('28202', country: 'US')
parse.postal_nearby('28202', country: 'US', radius: 40)
parse.postal_distance('28202', '10001', country: 'US')
parse.address('1600 Pennsylvania Ave NW, Washington, DC 20500', country: 'US')
parse.address_search('123 main', country: 'US', postal: '27401')
parse.company('732829320', country: 'FR')
parse.city('charlotte', country: 'US')
parse.city_id('city_mb8mbqrkz8zb')
parse.city_search('char', country: 'US', limit: 10)
parse.city_nearest(35.2271, -80.8431)
parse.city_nearby('denver', radius: 8, unit: 'mi')
parse.country('US')
parse.country_states('US')
parse.state('colorado')
parse.state('NC', country: 'US')
parse.state_districts('NC', country: 'US')
parse.district('37081')
parse.continent('NA')
parse.continent_countries('NA')
parse.bloc('EU')
parse.bloc_countries('SCHENGEN')
parse.currency('USD')
parse.currency_rate('USD', 'EUR')
parse.language('en')
parse.name('BILLY OSHALL')
parse.timezone('America/New_York')
parse.timezone('America/New_York', at: '2026-09-05T15:00', to: 'Europe/London')
parse.timezone_at(35.2271, -80.8431)
parse.date('03/04/2026', format: 'mdy')
parse.date_today(to: '2026-12-25')
parse.holiday('US', year: 2026)
parse.holiday_date('US', '2026-12-25')
parse.elevation(35.2271, -80.8431)
parse.point(36.0726, -79.792)
parse.weather(40.7128, -74.006)
parse.weather(40.7128, -74.006, deep: true, date: '2026-09-01')
parse.domain('example.com')
parse.asn('AS13335')
parse.mac('00:1B:63:84:45:E6')
parse.mx('example.com')
parse.useragent(ua_string)
parse.vin('1HGCM82633A004352')
parse.tariff('8471.30.01.00', origin: 'CN', deep: true)
parse.tariff_search('sunglasses')
parse.emoji('rocket')
parse.emoji_search('fire')
```

Each lookup returns a plain hash with string keys. Related lookups are separate calls, such as `country_states('US')`. Reading the result makes no further requests. New response fields and `nil` values are preserved.

## Deep

Pass `deep: true` to include the nested `deep` object with richer fields.

```ruby
ip = parse.ip('52.94.76.10', deep: true)
ip['deep']['datacenter'] # true
```

## Errors

Every non-2xx response raises `ParseAPI::Error` with `status`, `code`, `docs`, and `request_id`. Branch on `code`.

```ruby
begin
  parse.city('atlantis')
rescue ParseAPI::Error => e
  if e.code == 'not_found'
    # no such city
  end
end
```

## Options

```ruby
parse = ParseAPI.new(
  'your-api-key',
  timeout: 10 # connect, read, and write timeout in seconds
)
```

Ordinary lookups retry network errors and HTTP 429, 500, 502, 503, and 504 up to twice. Carrier, caller, and HLR lookups, plus email and VAT with `deep: true`, make one attempt by default because repeating them can repeat paid usage. Address with `deep: true` also uses one attempt, reserving that behavior for future verification. This does not mean address deep currently has a separate charge.

Pass `retries: 0` to make every lookup a single attempt. An explicit count such as `retries: 2` applies to every lookup, including paid ones. A retried request can count toward usage even when the first response was lost. Omit `retries` or pass `nil` to use the defaults above.

Reuse one client for successive lookups. Call `parse.close` to release its connection when finished. A later lookup opens a new connection. Use a separate client in each concurrent thread.

Network failures raise native Ruby exceptions. An invalid JSON response raises `JSON::ParserError`.

For testing or instrumentation, pass a callable as `transport:`. It receives the URL and request-header hash and returns `[status, lowercase_response_headers, body]`. Custom transports should use the supplied headers and keep redirect following disabled.

Requires Ruby 3.0 or later. Standard library only, zero dependencies.

## Docs

Full field reference for every endpoint: [parseapi.com/docs](https://parseapi.com/docs)
