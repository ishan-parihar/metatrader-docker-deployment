#!/bin/sh
# Write credentials from env vars to a file nginx can read
echo -n "${AUTH_USER:-admin}" > /tmp/auth_user
echo -n "${AUTH_PASS:-changeme}" > /tmp/auth_pass

# Execute the main command
exec "$@"
