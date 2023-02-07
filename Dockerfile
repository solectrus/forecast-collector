FROM ruby:3.2.0-alpine AS Builder
RUN apk add --no-cache build-base

WORKDIR /forecast-collector
COPY Gemfile* /forecast-collector/
RUN bundle config --local frozen 1 && \
    bundle config --local without 'development test' && \
    bundle install -j4 --retry 3 && \
    bundle clean --force

FROM ruby:3.2.0-alpine
LABEL maintainer="georg@ledermann.dev"

# Decrease memory usage
ENV MALLOC_ARENA_MAX 2


WORKDIR /forecast-collector

COPY --from=Builder /usr/local/bundle/ /usr/local/bundle/
COPY . /forecast-collector/

ENTRYPOINT bundle exec src/main.rb
