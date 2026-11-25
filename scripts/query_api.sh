#!/usr/bin/env bash
# Ask the knowledge base a question.
# Usage: RAG_TOKEN=... scripts/query_api.sh "What is the remote work policy?"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUESTION="${1:-What do I need to work remotely?}"
: "${RAG_TOKEN:?set RAG_TOKEN (see scripts/get_token.sh)}"
URL="${RAG_API_URL:-$(terraform -chdir="$ROOT/terraform/environments/dev" output -raw query_api_url)}"
PYTHON="${PYTHON:-python3}"
command -v "$PYTHON" >/dev/null 2>&1 || PYTHON=python

# Python builds the JSON body, so quotes in the question cannot break the request.
"$PYTHON" -c 'import json, sys; print(json.dumps({"question": sys.argv[1]}))' "$QUESTION" |
  curl -sS -X POST "$URL" \
    -H "Authorization: Bearer $RAG_TOKEN" \
    -H "Content-Type: application/json" \
    --data-binary @- |
  "$PYTHON" -m json.tool
