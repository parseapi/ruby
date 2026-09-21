```bash
gem install parseapi
```

```ruby
require 'parseapi'

parse = ParseAPI.new('your-api-key')
country = parse.country('US')
```

Get a key at [parseapi.com](https://parseapi.com). The client also reads `PARSEAPI_KEY` from the environment.

## API versions

Version 1.1.0 explicitly selects the API contract supported by this SDK. It sends `Parse-Version: 2.0.0` on every lookup so responses match the API contract supported by the package. Your key and the team's saved default stay the same.

Upgrade the dependency in staging, review the [release notes](https://parseapi.com/docs/releases), and test the application before deploying the same code and dependency version to production. Commit your dependency lockfile so the tested package travels with your deployment. Future major SDK upgrades can select a newer API contract.

Previously published SDKs keep their existing behavior and use the team's default. Requests without `Parse-Version` also use that default, managed in [Dashboard API version](https://parseapi.com/dashboard/versions). Keep it unchanged while older applications depend on it. Rolling back to an SDK without a version header restores the team default, so rollback only restores the old contract when that default has stayed unchanged.

The package owns its supported API version. For direct HTTP integrations, an explicit `Parse-Version` header selects a supported contract. See [API versions and migration](https://parseapi.com/docs/versioning).

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

Use `parse.postal('28202', country: 'US', deep: true)` for US ZIP tax references. `deep.tax` names the levy and `deep.tax_rate` is a percentage, so `7.9` means 7.9%. The state, county, city and special components explain that combined rate. An exact address can differ. Country and state lookups provide their own geographic reference rates, which should not be added to the ZIP rate. `nil` means unknown and `0` means known zero. Country `deep.tax_id_format` and `deep.tax_id_regex` describe registration-number format only. Use `vat` for a metered registration check with `deep` explicitly enabled.

## Calls

One method per endpoint, named after the route.

```ruby
parse.ip('8.8.8.8')
parse.ip_self
parse.email('hello@gmail.com')
parse.vat('DE136695976')
parse.iban('DE89370400440532013000')
parse.bin('424242')
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
parse.name('Andrea', country: 'IT', deep: true)
parse.name('Robert James Smith', deep: true, name_locale: 'en')
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

NAICS paid deep records include classification `deep.exclusions`, each with a description and linked codes. Generic exclusions can have no linked codes. Omitted or null exclusions in older responses remain unknown. Search results also include `match`: the matched `field` (`name`, `term` or `naics`) and `text`, plus `corrections` with `from` and `to` tokens for typo fallback. Corrections are empty for exact, plural and prefix matches. Direct code lookups omit `match`. Older responses may omit it.

Each lookup returns a plain hash with string keys. Related lookups are separate calls, such as `country_states('US')`. Reading the result makes no further requests. New response fields and `nil` values are preserved.

DNS uses pooled requests on every plan. Omit `type` to check A, AAAA, CNAME, MX, NS, TXT, SOA, CAA, SRV and PTR. Records contain `name`, `type`, `ttl` in seconds and a DNS presentation `value`. TXT values retain quoting and chunk boundaries. A selected question can include its CNAME chain. Empty records mean no records. Lookup failures remain errors.

Name paid deep includes flat `short`, `directory`, and `initials` fields beside `gender` and `salutation`. `name_locale` selects CLDR formatting rules and defaults to `en`. It changes formatting only. Country remains gender context, and unavailable formatting is null. Older responses may omit these fields.

## Display language

Choose display names for one request:

```ruby
parse.country('DE', lang: 'fr')
```

`lang` is optional on geography lookups and their lists/searches, Currency lookup, Language, Date, Time/Timezone, Emoji lookup/search, and unit discovery. IP, ASN, Company and NPI also accept it for their geographic labels. Codes, native names, quantities and response structure retain their meanings. Source coverage determines which labels are translated; unavailable labels use the API's documented fallback.

The next call keeps its usual default unless it also supplies `lang`. Existing `deep` rules still apply. Date `format` and measurement `locale` remain explicit input-parsing controls.

## Time

`time` returns local ISO `at` with its UTC offset and integer Unix seconds in `unix`. The core `offset` preserves exact precision. Optional `deep.offset_seconds` gives the numeric offset, while `deep.offset_minutes` gives whole minutes. Historical offsets and ISO times can include offset seconds. Omitted `at` means now. With `to`, an offsetless `at` is source wall time. Otherwise it is UTC. Include an offset for repeated local times around a clock change. Current time and conversion use pooled requests on every plan. Coordinate clock fields can be null when the timezone is unknown. Existing `timezone` methods remain supported.

## Measurements

```ruby
result = parse.measure('5 ft 11 in', to: 'cm')
units = parse.measure_units(unit: 'm')
```

`amount` is a decimal string, such as `"180.34"`. Without `to`, the API returns the canonical unit for the measurement type. Pass `locale` for number formatting and `system` (`us` or `imperial`) when a customary unit needs context. Ambiguous input returns `valid: false`, a `reason`, and available `choices`. Invalid or incompatible target units use the normal API error.

Unit discovery accepts optional `query`, `type`, and `unit` filters. `unit` selects compatible targets. Omit the filters for the reviewed catalog. Both operations use pooled requests.

## Place statistics and optional detail

Postal and District paid profiles include `deep.property_tax` where supported. It contains `annual_median`, `currency` and `period`: median annual property tax payable on owner-occupied homes in the statistical area. The amount is adjusted to the final year of the reporting period (`YYYY-YYYY`). This is an area statistic, not a rate or an individual property bill. Unsupported, missing and censored estimates are null.

```ruby
place = parse.postal('28202', country: 'US', deep: true)
property_tax = place.dig('deep', 'property_tax')
```

Read `population_period` alongside `population`: a reporting year (`YYYY`) or period (`YYYY-YYYY`), null when unknown or unverifiable. Keep missing or null values unknown and preserve a known zero. These fields belong to full place profiles. State district lists include each district's population and period. Postal nearby and distance detail remains metropolitan associations only. Continent population stays in core.

Country deep includes `land_area` and `water_area` in km2, `coastline` in km, and mean `elevation` in metres. `lowest_point` and `highest_point` contain a nullable `name` and an `elevation` in metres. Values below sea level are negative. Missing or null values stay unknown, and zero stays zero.

Point returns the timezone ID with the core location. Its optional deep detail adds terrain and compact nearest-city context on every plan. A nearest city is null when none is within 200 km.

Weather returns current conditions by default. Paid deep adds specialist current measurements, forecasts and related detail. A past `date` is a UTC day and requires deep: it adds `deep.history` alongside current conditions. Date alone does not request history.

```ruby
parse.weather(40.7128, -74.006, deep: true, date: '2026-08-15')
```

Tariff starts with the general schedule line. Paid deep adds units and the special and other schedule columns. An optional origin then resolves country-specific measures. The three calls below show those successive choices. Without origin, schedule detail is still returned and origin-dependent fields are null. A null effective rate is not a zero rate.

```ruby
parse.tariff('8471.30.01.00')
parse.tariff('8471.30.01.00', deep: true)
parse.tariff('8471.30.01.00', deep: true, origin: 'CN')
```

Address search uses context from the form: prefer postal, or city and state. An optional end-user `ip` is a locality hint for server-side calls. An empty result explains itself with `reason`: `more_input`, `missing_context` or `no_matches`. With suggestions, reason is null. Older responses may omit it, and future reasons remain strings. Catalog and lookup failures use the existing API errors.

HLR reports status at the last check. `live` means assigned and `connected` means reachable at that check. Cached results may be returned. Null means unconfirmed. Deep diagnostics stay within the same metered lookup.

## Deep

Choose enrichment for the question you need answered.

| Operation | What `deep` requests |
|---|---|
| IP | Richer IP fields included with a paid plan. No separate check meter. |
| Domain | Registration dates, registrar, status and DNSSEC, included with a paid plan. Use `dns` for DNS records and `mx` for mail routing. |
| Email | A metered mailbox check with deliverability, catch-all, status, reason and address hints, using included email checks or enabled on-demand usage. |
| VAT | A metered registry check where supported, using included VAT checks or enabled on-demand usage. |
| Phone, Time, Date, Currency, Language, Emoji, IBAN, Point | Optional detail in the same pooled request on every plan. |
| Country, State, District, City, Postal | The place profile on paid plans, including demographic and tax facts where held. |
| Name, NAICS | Name evidence or the industry definition profile on paid plans. |
| VIN, NPI, Tariff, Company | The complete product detail bag on paid plans. |
| Weather | Specialist current measurements and the existing forecast, alert, air and history bag on paid plans. |
| Carrier, HLR | Optional diagnostic detail within the same metered core unit, including Free allowance units. No second gate or additional check. |

Email deep includes mailbox status and the reason for the result, plus a suggested first name, no-reply flag, plus-address tag and mail service. The suggested name is not a verified identity. Unavailable details are null.

Reasons include `accepted`, `invalid_format`, `invalid_domain`, `no_mail_server`, `mailbox_not_found`, `mailbox_disabled`, `mailbox_full`, `catchall`, `disposable`, `temporary_failure`, `rejected` and `unconfirmed`.

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


## Optional detail

The default response answers the common task. Ask for `deep` when you need more detail about that same result. Core fields stay equal. City, NAICS and Emoji searches put detail inside each result. Postal nearby and distance put metropolitan detail beside the entity it describes. Time conversion keeps target detail in `to.deep`; only the source has `deep.next_dst`.

```ruby
basic = parse.time('America/New_York')
detail = parse.time('America/New_York', deep: true)
puts basic['at'], detail.dig('deep', 'next_dst')
```

## Stack API

```ruby
result = parse.stack("example.com")
```

Pass a public hostname without a scheme, path, port or IP address. Stack returns the checked URL and `checked_at` time, followed by `scope`, `pages` and `partial`. `scope` is `homepage` or `site`; `pages` counts successfully checked HTML pages. `partial` is true for homepage-only or incomplete bounded site checks. False means the known in-scope candidates were completed, not that every page on a website was visited. A homepage result has `scope: "homepage"`, `pages: 1` and `partial: true`.

`cms`, `servers`, `frameworks`, `ecommerce`, `analytics`, `chat`, `payments` and `hosting` are arrays because a site can use several technologies in each category. Each entry contains `technology`, `name` and nullable `version`. Technology codes are open strings. A successful check uses empty arrays for categories with no matches. When no HTML page could be checked, `checked_at` and all categories are null, `pages` is 0 and `partial` is null. Unknown or conflicting versions are null. Missing detections do not prove absence.

Successful checks may be reused for up to 24 hours. `pretty` optionally formats the wire JSON. Stack uses your plan's request allowance and API version 2.0.0 selected by this client.

Stack defaults to a 35-second transport timeout so a first scan has time to finish. Other lookups retain their 10-second default. An explicit client timeout takes precedence.
