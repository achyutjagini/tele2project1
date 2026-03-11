#!/bin/sh
set -e

# Substitute environment variables in config
sed -e "s/\${COUCHBASE_SERVER}/$COUCHBASE_SERVER/g" \
    -e "s/\${COUCHBASE_USERNAME}/$COUCHBASE_USERNAME/g" \
    -e "s/\${COUCHBASE_PASSWORD}/$COUCHBASE_PASSWORD/g" \
    /etc/sync_gateway/sync-gateway-config.json > /tmp/sync-gateway-config.json

# Start Sync Gateway in the background
/entrypoint.sh /tmp/sync-gateway-config.json &
PID=$!

AUTH="${COUCHBASE_USERNAME}:${COUCHBASE_PASSWORD}"
ADMIN="http://127.0.0.1:4985"

# Wait for Admin API to be available
echo "Waiting for Sync Gateway Admin API..."
until curl -s -u "$AUTH" "$ADMIN/" > /dev/null 2>&1; do
  sleep 2
done

echo "Sync Gateway is up. Configuring database..."

# Try to create the database first
HTTP_CODE=$(curl -s -o /tmp/sg-response.txt -w "%{http_code}" \
  -X PUT "$ADMIN/main/" \
  -u "$AUTH" \
  -H "Content-Type: application/json" \
  -d @/etc/sync_gateway/database.json)

if [ "$HTTP_CODE" = "412" ]; then
  echo "Database exists but may have outdated config. Checking for technician scope..."

  HAS_TECHNICIAN=$(curl -s -u "$AUTH" "$ADMIN/main/_config" | grep -c '"technician"' || true)

  if [ "$HAS_TECHNICIAN" = "0" ]; then
    echo "Technician scope missing. Deleting and recreating database..."

    # Delete existing database
    curl -s -X DELETE "$ADMIN/main/" -u "$AUTH"
    sleep 2

    # Recreate with correct config
    curl -s -X PUT "$ADMIN/main/" \
      -u "$AUTH" \
      -H "Content-Type: application/json" \
      -d @/etc/sync_gateway/database.json
    echo ""
    echo "Database recreated with technician scope."
  else
    echo "Database already has technician scope. No changes needed."
  fi
elif [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "200" ]; then
  echo "Database created successfully."
else
  echo "Unexpected response ($HTTP_CODE):"
  cat /tmp/sg-response.txt
  echo ""
fi

# Verify
echo "Verifying collection configuration..."
curl -s -u "$AUTH" "$ADMIN/main/_config" | grep -o '"technician"' && \
  echo "Technician scope confirmed." || \
  echo "WARNING: Technician scope not found!"

# Wait for the Sync Gateway process
wait $PID
