```bash
gem install parseapi
```

```ruby
require 'parseapi'

parse = ParseAPI.new('your-api-key')
country = parse.country('US')
```

Get a key at [parseapi.com](https://parseapi.com). The client also reads `PARSEAPI_KEY` from the environment.

## Weather from a postal code

Start with the postal code, then pass its coordinates to weather. Reuse the client from the example above.

```ruby
place = parse.postal('28202', country: 'US')
lat, lon = place.values_at('latitude', 'longitude')
unless lat.nil? || lon.nil?
  weather = parse.weather(lat, lon)
  puts weather
end
```

The coordinates represent the postal area. Weather is for that point. Missing coordinates skip the weather lookup. This composition performs two ordinary lookups when coordinates are available, with the retry policy below.

## Supply the context you know

Pass `country` when a postal code or national phone number needs disambiguation. A complete international phone number already carries its country context. For a numeric date such as `03/04/2026`, supply the intended `format`. Defaults resolve what the input establishes. Ambiguous input needs your context.

Results are plain data. Pass a returned code or coordinate to another operation when the task needs it. Check nullable values before composing the next call.

## Calls

One method per endpoint, named after the route.

```ruby
parse.ip('8.8.8.8')
parse.ip_self
parse.email('hello@gmail.com')
parse.vat('DE136695976')
parse.iban('DE89370400440532013000')
parse.bin('424242')
parse.swift('CHASUS33')
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
parse.name('Andrea', country: 'IT')
parse.time # UTC now
parse.time('America/New_York')
parse.time('America/New_York', at: '2026-09-05T15:00', to: 'Europe/London')
parse.time_at(35.2271, -80.8431)
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
parse.dns('example.com')
parse.dns('_dmarc.example.com', type: 'TXT')
parse.useragent(ua_string)
parse.vin('1HGCM82633A004352')
parse.naics('541511')
parse.naics_search('coffee shop', limit: 5)
parse.tariff('8471.30.01.00', origin: 'CN', deep: true)
parse.tariff_search('sunglasses')
parse.emoji('rocket')
parse.emoji_search('fire')
```

NAICS records include classification `exclusions`, each with a description and linked codes. Generic exclusions can have no linked codes. Omitted or null exclusions in older responses remain unknown. Search results also include `match`: the matched `field` (`name`, `term` or `naics`) and `text`, plus `corrections` with `from` and `to` tokens for typo fallback. Corrections are empty for exact, plural and prefix matches. Direct code lookups omit `match`. Older responses may omit it.

Each lookup returns a plain hash with string keys. Related lookups are separate calls, such as `country_states('US')`. Reading the result makes no further requests. New response fields and `nil` values are preserved.

DNS uses pooled requests on every plan. Omit `type` to check A, AAAA, CNAME, MX, NS, TXT, SOA, CAA, SRV and PTR. Records contain `name`, `type`, `ttl` in seconds and a DNS presentation `value`. TXT values retain quoting and chunk boundaries. A selected question can include its CNAME chain. Empty records mean no records. Lookup failures remain errors.

## Time

`time` returns local ISO `at` with its UTC offset and integer Unix seconds in `unix`. `offset_seconds` is the exact offset, while `offset_minutes` is whole minutes. Historical offsets and ISO times can include offset seconds. Omitted `at` means now. With `to`, an offsetless `at` is source wall time. Otherwise it is UTC. Include an offset for repeated local times around a clock change. Current time and conversion use pooled requests on every plan. Coordinate clock fields can be null when the timezone is unknown. Existing `timezone` methods remain supported.

## Measurements

```ruby
result = parse.measure('5 ft 11 in', to: 'cm')
units = parse.measure_units(unit: 'm')
```

`amount` is a decimal string, such as `"180.34"`. Without `to`, the API returns the canonical unit for the measurement type. Pass `locale` for number formatting and `system` (`us` or `imperial`) when a customary unit needs context. Ambiguous input returns `valid: false`, a `reason`, and available `choices`. Invalid or incompatible target units use the normal API error.

Unit discovery accepts optional `query`, `type`, and `unit` filters. `unit` selects compatible targets. Omit the filters for the reviewed catalog. Both operations use pooled requests.

## Deep

Choose enrichment for the question you need answered.

| Operation | What `deep` requests |
|---|---|
| IP | Richer IP fields included with a paid plan. No separate check meter. |
| Email | A metered deliverability check, using included email checks or enabled on-demand usage. |
| VAT | A metered registry check where supported, using included VAT checks or enabled on-demand usage. |
| Phone | An empty object. Number parsing and formats are already in the core response. |

Carrier, caller, and HLR are separate metered operations. Choose them explicitly when you need their answers. Ordinary lookups retry twice by default. Metered checks use one attempt by default. Setting retries explicitly can repeat paid usage.

Without `deep`, the response omits that key. When requested, it is an empty object if access is locked or the operation has no deep fields. Otherwise it contains the available fields. A missing or null field means unknown.

```ruby
ip = parse.ip('52.94.76.10', deep: true)
ip.dig('deep', 'datacenter') # true, false, or nil
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

BIN lookup accepts 6-11 digits as a string, including leading zeros. Spaces and hyphens are accepted. `prefix` is the actual longest match and can be shorter than the input. Unknown reference fields are null. `deep` adds an empty object on every plan.
