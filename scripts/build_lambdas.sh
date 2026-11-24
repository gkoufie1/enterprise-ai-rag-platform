#!/usr/bin/env bash
# Build the Lambda packages into build/<function>/ for Terraform to zip.
# Dependencies are fetched as Linux arm64 / Python 3.13 wheels, so this works on any OS.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="${PYTHON:-python3}"
command -v "$PYTHON" >/dev/null 2>&1 || PYTHON=python

for fn in query ingestion; do
  out="$ROOT/build/$fn"
  rm -rf "$out"
  mkdir -p "$out"
  "$PYTHON" -m pip install --quiet --disable-pip-version-check \
    --requirement "$ROOT/app/$fn/requirements.txt" \
    --target "$out" \
    --platform manylinux2014_aarch64 \
    --implementation cp \
    --python-version 3.13 \
    --only-binary=:all:
  cp "$ROOT/app/$fn/handler.py" "$out/"
  cp -r "$ROOT/app/rag_core" "$out/"
  find "$out" -type d -name "__pycache__" -prune -exec rm -rf {} +
  echo "built $fn -> build/$fn ($(du -sh "$out" | cut -f1))"
done
