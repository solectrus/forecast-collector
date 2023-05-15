[![Continuous integration](https://github.com/solectrus/forecast-collector/actions/workflows/push.yml/badge.svg)](https://github.com/solectrus/forecast-collector/actions/workflows/push.yml)
[![wakatime](https://wakatime.com/badge/user/697af4f5-617a-446d-ba58-407e7f3e0243/project/40d80ef4-7f52-4e68-a361-ed42d887c5e2.svg)](https://wakatime.com/badge/user/697af4f5-617a-446d-ba58-407e7f3e0243/project/40d80ef4-7f52-4e68-a361-ed42d887c5e2)

# Forecast collector

Collect solar forecast data from https://forecast.solar and push it to InfluxDB.

## Usage

1. Make sure your InfluxDB database is ready (not subject of this README)

2. Prepare an `.env` file (see `.env.example`) with your InfluxDB credentials and some details about your PV plant (Geo location, azimuth, declination etc.)

   You find details about the params on the [forecast.solar API documentation](https://doc.forecast.solar/api:estimate).

3. Run the Docker container on your Linux box:

   ```bash
   docker run -it --rm \
              --env-file .env \
              ghcr.io/solectrus/forecast-collector
   ```

It's recommended to integrate the `forecast-collector` into your SOLECTRUS hosting. See more here:
https://github.com/solectrus/hosting

## License

Copyright (c) 2020,2023 Georg Ledermann, released under the MIT License
