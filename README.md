# Forecast collector

Collect solar forecast data from https://forecast.solar and push it to InfluxDB.


## Usage

1. Make sure your InfluxDB database is ready (not subject of this README)

2. Prepare an `.env` file (see `.env.example`) with your InfluxDB credentials and some details about your PV plant (Geo location, azimuth, declination etc.)

3. Run the Docker container on your Linux box:

   ```bash
   docker run -it --rm \
              --env-file .env \
              ghcr.io/solectrus/forecast-collector
   ```

It's recommended to integrate the `forecast-collector` into your Solectrus hosting. See more here:
https://github.com/solectrus/hosting


## License

Copyright (c) 2020,2022 Georg Ledermann, released under the MIT License
