# Forecast collector

Collect solar forecast data from https://forecast.solar and push it to InfluxDB 2.

## Getting started

1. Make sure your InfluxDB2 database is ready (not subject of this README)

2. Prepare an `.env` file (see `.env.example`)

3. Run the Docker container on your Linux box:

   ```bash
   docker-commpose up
   ```

## Build Docker image by yourself

```bash
docker build -t forecast-collector .
```

## License

Copyright (c) 2020,2022 Georg Ledermann, released under the MIT License
