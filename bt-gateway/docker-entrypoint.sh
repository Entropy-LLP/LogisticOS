#!/bin/sh
# Explicit variable list required — envsubst without it would replace nginx's own $host, $remote_addr, etc.
set -e

# Extract hostnames from service URLs for proxy_set_header Host
# e.g. https://bt-auth-service-752385541585.asia-south1.run.app -> bt-auth-service-752385541585.asia-south1.run.app
export AUTH_SERVICE_HOST=$(echo "$AUTH_SERVICE_URL" | sed 's|https\?://||' | sed 's|/.*||')
export BOOKING_SERVICE_HOST=$(echo "$BOOKING_SERVICE_URL" | sed 's|https\?://||' | sed 's|/.*||')
export PRICING_SERVICE_HOST=$(echo "$PRICING_SERVICE_URL" | sed 's|https\?://||' | sed 's|/.*||')
export PAYMENT_SERVICE_HOST=$(echo "$PAYMENT_SERVICE_URL" | sed 's|https\?://||' | sed 's|/.*||')
export CARGO_SERVICE_HOST=$(echo "$CARGO_SERVICE_URL" | sed 's|https\?://||' | sed 's|/.*||')
export TRACKING_SERVICE_HOST=$(echo "$TRACKING_SERVICE_URL" | sed 's|https\?://||' | sed 's|/.*||')

envsubst '${DNS_RESOLVER} ${AUTH_SERVICE_URL} ${BOOKING_SERVICE_URL} ${PRICING_SERVICE_URL} ${PAYMENT_SERVICE_URL} ${CARGO_SERVICE_URL} ${TRACKING_SERVICE_URL} ${AUTH_SERVICE_HOST} ${BOOKING_SERVICE_HOST} ${PRICING_SERVICE_HOST} ${PAYMENT_SERVICE_HOST} ${CARGO_SERVICE_HOST} ${TRACKING_SERVICE_HOST} ${CORS_ALLOWED_ORIGINS}' \
  < /etc/nginx/nginx.conf.template \
  > /etc/nginx/nginx.conf

exec nginx -g 'daemon off;'
