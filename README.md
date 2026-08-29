# parseapi

Official parseAPI client for Ruby.

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
parse.phone('+14155552671')
parse.carrier('+14155552671')
parse.caller('+14155552671')
parse.hlr('+14155552671')
parse.postal('28202', country: 'US')
parse.postal_nearby('28202', country: 'US', radius: 40)
parse.postal_distance('28202', '10001', country: 'US')
parse.city('charlotte', country: 'US')
parse.city_id('city_mb8mbqrkz8zb')
parse.city_search('char', country: 'US', limit: 10)
parse.city_nearest(35.2271, -80.8431)
parse.country('US')
parse.country_states('US')
parse.state('NC', country: 'US')
parse.state_districts('NC', country: 'US')
parse.district('37081')
parse.continent('NA')
parse.continent_countries('NA')
parse.currency('USD')
parse.currency_rate('USD', 'EUR')
parse.language('en')
parse.name('BILLY OSHALL')
parse.timezone('America/New_York')
parse.holiday('US', year: 2026)
parse.holiday_date('US', '2026-12-25')
parse.elevation(35.2271, -80.8431)
parse.point(36.0726, -79.792)
parse.weather(40.7128, -74.006)
parse.domain('example.com')
parse.mx('example.com')
parse.useragent(ua_string)
parse.emoji('rocket')
parse.emoji_search('fire')
```

Responses are plain hashes, exactly the JSON the API returns.

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
  timeout: 10, # per-attempt timeout in seconds
  retries: 2   # automatic retries on network errors, 429, and 5xx
)
```

Requires Ruby 3.0 or later. Standard library only, zero dependencies.

## Docs

Full field reference for every endpoint: [parseapi.com/docs](https://parseapi.com/docs)
