FROM ruby:3.1.3-alpine
LABEL maintainer="georg@ledermann.dev"

WORKDIR /forecast-collector

COPY Gemfile* /forecast-collector/
RUN bundle config --local frozen 1 && \
    bundle config --local without 'development test' && \
    bundle install -j4 --retry 3 && \
    bundle clean --force

COPY . /forecast-collector/

ENTRYPOINT bundle exec src/main.rb
