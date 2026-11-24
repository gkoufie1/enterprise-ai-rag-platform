#!/usr/bin/env bash
# Print a Cognito ID token for the API.
# Usage: export RAG_TOKEN="$(RAG_PASSWORD='...' scripts/get_token.sh user@example.com)"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMAIL="${1:?usage: RAG_PASSWORD=... $0 <email>}"
: "${RAG_PASSWORD:?set RAG_PASSWORD in the environment}"
CLIENT_ID="$(terraform -chdir="$ROOT/terraform/environments/dev" output -raw user_pool_client_id)"

aws cognito-idp initiate-auth --client-id "$CLIENT_ID" --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters "USERNAME=$EMAIL,PASSWORD=$RAG_PASSWORD" \
  --query 'AuthenticationResult.IdToken' --output text
