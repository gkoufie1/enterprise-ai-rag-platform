#!/usr/bin/env bash
# Re-run ingestion for one document by hand (for example after a DLQ alarm).
# Usage: scripts/reingest.sh remote-work-policy.md
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY="${1:?usage: $0 <s3-key>}"
FUNCTION="$(terraform -chdir="$ROOT/terraform/environments/dev" output -raw ingestion_function_name)"
OUT="$(mktemp)"

aws lambda invoke --function-name "$FUNCTION" \
  --cli-binary-format raw-in-base64-out \
  --payload "$(jq -cn --arg k "$KEY" '{key: $k}')" \
  "$OUT" >/dev/null
jq . "$OUT"
rm -f "$OUT"
