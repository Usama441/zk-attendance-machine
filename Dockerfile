FROM ruby:3.3-slim

ENV RAILS_ENV=development \
    BUNDLE_PATH=/usr/local/bundle

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends build-essential libpq-dev postgresql-client && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile ./
RUN bundle install

COPY . .

EXPOSE 3000

# Clear stale pid (left by unclean shutdowns), create+migrate, then boot.
CMD ["bash", "-c", "rm -f tmp/pids/server.pid && bin/rails db:prepare && bin/rails server -b 0.0.0.0 -p 3000"]
