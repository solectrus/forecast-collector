# Forecast collector

Collect solar forecast data from https://forecast.solar and push it to InfluxDB 2.

## Build image

```bash
docker build -t forecast-collector .
```

## Run container

Prepare an `.env` file (see `.env.example`). Then:

```bash
docker run --env-file .env forecast-collector src/main.rb
```

Copyright (c) 2020-2021 Georg Ledermann, released under the MIT License
