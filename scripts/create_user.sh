#!/usr/bin/env bash
# Create a Cognito user with a permanent password (self sign-up is disabled).
# Usage:
#   RAG_PASSWORD='...' scripts/create_user.sh user@example.com          # regular user
#   RAG_PASSWORD='...' scripts/create_user.sh demo@example.com demo     # public demo account
# Demo accounts join the "demo" group and get the demo_daily_limit question quota.
# The password needs 12+ characters with upper, lower, number and symbol.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMAIL="${1:?usage: RAG_PASSWORD=... $0 <email> [demo]}"
ROLE="${2:-}"
: "${RAG_PASSWORD:?set RAG_PASSWORD in the environment so it stays out of shell history}"
POOL_ID="$(terraform -chdir="$ROOT/terraform/environments/dev" output -raw user_pool_id)"

aws cognito-idp admin-create-user --user-pool-id "$POOL_ID" --username "$EMAIL" \
  --user-attributes Name=email,Value="$EMAIL" Name=email_verified,Value=true \
  --message-action SUPPRESS >/dev/null
aws cognito-idp admin-set-user-password --user-pool-id "$POOL_ID" --username "$EMAIL" \
  --password "$RAG_PASSWORD" --permanent

if [ "$ROLE" = "demo" ]; then
  aws cognito-idp admin-add-user-to-group --user-pool-id "$POOL_ID" --username "$EMAIL" --group-name demo
  echo "Created demo account $EMAIL in $POOL_ID (daily question limit applies)"
else
  echo "Created $EMAIL in $POOL_ID"
fi
