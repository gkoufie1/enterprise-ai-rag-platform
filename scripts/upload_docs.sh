#!/usr/bin/env bash
# Sync sample-docs/ to the document bucket. Each upload triggers ingestion automatically,
# and files deleted locally are deleted from the bucket (and from the vector index).
# Usage: scripts/upload_docs.sh [source-dir]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:-$ROOT/sample-docs}"
BUCKET="$(terraform -chdir="$ROOT/terraform/environments/dev" output -raw document_bucket_name)"

aws s3 sync "$SRC" "s3://$BUCKET/" --delete --exclude "*" --include "*.md" --include "*.txt"
echo "Synced $SRC to s3://$BUCKET. Ingestion runs in the background; watch the ingestion logs with:"
echo "  aws logs tail /aws/lambda/$(terraform -chdir="$ROOT/terraform/environments/dev" output -raw ingestion_function_name) --follow"
