#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <binary-path> [identity]" >&2
  exit 1
fi

BINARY_PATH="$1"
IDENTITY="${2:-${DEVELOPER_ID_APPLICATION:-}}"

if [[ ! -f "$BINARY_PATH" ]]; then
  echo "binary not found: $BINARY_PATH" >&2
  exit 1
fi

if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning | grep 'Developer ID Application:' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')"
fi

if [[ -z "$IDENTITY" ]]; then
  echo "no Developer ID Application identity found; set DEVELOPER_ID_APPLICATION explicitly" >&2
  exit 1
fi

echo "Signing $BINARY_PATH"
codesign \
  --force \
  --sign "$IDENTITY" \
  --options runtime \
  --timestamp \
  "$BINARY_PATH"

echo "Verifying signature"
codesign --verify --verbose=4 "$BINARY_PATH"
if ! spctl -a -t exec -vv "$BINARY_PATH"; then
  echo "spctl rejected $BINARY_PATH before notarization; continuing" >&2
fi
