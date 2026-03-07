#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <archive-path>" >&2
  exit 1
fi

ARCHIVE_PATH="$1"
PROFILE_NAME="${NOTARY_PROFILE:-osx-query-notary}"
TEAM_ID="${APPLE_TEAM_ID:-${NOTARY_TEAM_ID:-}}"
APPLE_ID="${APPLE_ID:-}"
APP_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-${APPLE_APP_PASSWORD:-}}"

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  echo "archive not found: $ARCHIVE_PATH" >&2
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "$PROFILE_NAME" >/dev/null 2>&1; then
  if [[ -z "$APPLE_ID" || -z "$APP_PASSWORD" || -z "$TEAM_ID" ]]; then
    cat >&2 <<EOF
notary profile '$PROFILE_NAME' not found in keychain, and APPLE_ID / APPLE_APP_SPECIFIC_PASSWORD / APPLE_TEAM_ID are not all set.
Either:
  1. export APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, APPLE_TEAM_ID and re-run, or
  2. create a keychain profile first:
     xcrun notarytool store-credentials "$PROFILE_NAME" --apple-id "<apple-id>" --password "<app-password>" --team-id "<team-id>"
EOF
    exit 1
  fi

  echo "Creating notarytool keychain profile '$PROFILE_NAME'"
  xcrun notarytool store-credentials "$PROFILE_NAME" \
    --apple-id "$APPLE_ID" \
    --password "$APP_PASSWORD" \
    --team-id "$TEAM_ID"
fi

echo "Submitting $ARCHIVE_PATH for notarization"
xcrun notarytool submit "$ARCHIVE_PATH" \
  --keychain-profile "$PROFILE_NAME" \
  --wait
