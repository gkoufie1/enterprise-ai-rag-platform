#!/usr/bin/env bash
# Create a Cognito user with a permanent password (self sign-up is disabled).
# Usage: RAG_PASSWORD='...' scripts/create_user.sh user@example.com
# The password needs 12+ characters with upper, lower, number and symbol.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMAIL="${1:?usage: RAG_PASSWORD=... $0 <email>}"
: "${RAG_PASSWORD:?set RAG_PASSWORD in the environment so it stays out of shell history}"
POOL_ID="$(terraform -chdir="$ROOT/terraform/environments/dev" output -raw user_pool_id)"

aws cognito-idp admin-create-user --user-pool-id "$POOL_ID" --username "$EMAIL" \
  --user-attributes Name=email,Value="$EMAIL" Name=email_verified,Value=true \
  --message-action SUPPRESS >/dev/null
aws cognito-idp admin-set-user-password --user-pool-id "$POOL_ID" --username "$EMAIL" \
  --password "$RAG_PASSWORD" --permanent
echo "Created $EMAIL in $POOL_ID"
