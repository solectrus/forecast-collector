FROM ruby:3.0.0-alpine
LABEL maintainer="georg@ledermann.dev"

WORKDIR /forecast-collector

COPY Gemfile* /forecast-collector/
RUN bundle config --local frozen 1 && \
    bundle install -j4 --retry 3

COPY . /forecast-collector/
