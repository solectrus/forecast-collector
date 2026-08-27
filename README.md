[![Continuous integration](https://github.com/solectrus/forecast-collector/actions/workflows/push.yml/badge.svg)](https://github.com/solectrus/forecast-collector/actions/workflows/push.yml)
[![Maintainability](https://qlty.sh/gh/solectrus/projects/forecast-collector/maintainability.svg)](https://qlty.sh/gh/solectrus/projects/forecast-collector)
[![wakatime](https://wakatime.com/badge/user/697af4f5-617a-446d-ba58-407e7f3e0243/project/40d80ef4-7f52-4e68-a361-ed42d887c5e2.svg)](https://wakatime.com/badge/user/697af4f5-617a-446d-ba58-407e7f3e0243/project/40d80ef4-7f52-4e68-a361-ed42d887c5e2)
[![Code Coverage](https://qlty.sh/gh/solectrus/projects/forecast-collector/coverage.svg)](https://qlty.sh/gh/solectrus/projects/forecast-collector)

# Forecast collector

Collect solar forecast data from various providers and store them into an InfluxDB database. Supported providers are:

- Forecast.Solar (https://forecast.solar)
- Solcast (https://solcast.com)
- Pvnode (https://pvnode.com) — API v2, and API v1 until pvnode shuts it down on 2026-12-31

## Usage

1. Depending on the provider you want to use, you need to sign up for their services and get an API key:

   - [Forecast.Solar API documentation](https://doc.forecast.solar/api:estimate) (no API key required)
   - [Solcast API documentation](https://docs.solcast.com.au/) in the Legacy/Hobbyist section (API key required)
   - [Pvnode API documentation](https://pvnode.com/docs/) (API key required)

   For pvnode, the API key is enough if your account has exactly one site. The
   collector reads the sites of your account and follows the update schedule
   that the pvnode API recommends. If the account has more than one site, the
   collector lists them and asks you to set `PVNODE_SITE_ID`. It also reports
   how many requests your plan has left this month.

   The collector remembers when the next forecast is due, so a restart of the
   container costs no request. If your API key or your site is wrong, the
   collector stops and reports what you must change.

2. Make sure your InfluxDB database is ready (not subject of this README)

3. Prepare an `.env` file (see `.env.example`) with your InfluxDB credentials and the provider-specific settings, e.g., API key.

4. Run the Docker container on your Linux box:

   ```bash
   docker run -it --rm \
              --env-file .env \
              ghcr.io/solectrus/forecast-collector
   ```

It's recommended to integrate the `forecast-collector` into your SOLECTRUS hosting. See more here:
https://github.com/solectrus/hosting

## License

Copyright (c) 2020-2026 Georg Ledermann, released under the MIT License
