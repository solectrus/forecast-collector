FROM ruby:3.3.0-alpine AS Builder
RUN apk add --no-cache build-base

WORKDIR /forecast-collector
COPY Gemfile* /forecast-collector/
RUN bundle config --local frozen 1 && \
    bundle config --local without 'development test' && \
    bundle install -j4 --retry 3 && \
    bundle clean --force

FROM ruby:3.3.0-alpine
LABEL maintainer="georg@ledermann.dev"

# Decrease memory usage
ENV MALLOC_ARENA_MAX 2

# Move build arguments to environment variables
ARG BUILDTIME
ENV BUILDTIME ${BUILDTIME}

ARG VERSION
ENV VERSION ${VERSION}

ARG REVISION
ENV REVISION ${REVISION}

WORKDIR /forecast-collector

# The heartbeat is written at least every 60 seconds, so the container
# is considered healthy if the last heartbeat was less than 70 seconds ago.
HEALTHCHECK CMD test $(expr $(date +%s) - $(cat /tmp/heartbeat.txt)) -lt 70 || exit 1

COPY --from=Builder /usr/local/bundle/ /usr/local/bundle/
COPY . /forecast-collector/

ENTRYPOINT bundle exec app/main.rb
