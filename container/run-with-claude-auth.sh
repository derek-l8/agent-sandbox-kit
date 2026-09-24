#!/usr/bin/env bash

set -euo pipefail

# Claude subscription authentication wrapper. Persist only
# $CLAUDE_CONFIG_DIR/.credentials.json. Task sessions mount /auth read-only; authentication
# containers mount it read-write and may synchronize the refreshed credential.
auth_store=/auth/.credentials.json
runtime_auth="${CLAUDE_CONFIG_DIR}/.credentials.json"

mkdir -p "$CLAUDE_CONFIG_DIR"
# Onboarding is ephemeral; do not persist project trust, settings, or history.
printf '{"hasCompletedOnboarding":true}\n' > "$CLAUDE_CONFIG_DIR/.claude.json"
if [[ -f "$auth_store" ]]; then
  install -m 0600 "$auth_store" "$runtime_auth"
fi

sync_auth() {
  [[ -w /auth ]] || return 0
  if [[ -f "$runtime_auth" ]]; then
    install -m 0600 "$runtime_auth" "$auth_store"
  else
    rm -f "$auth_store"
  fi
}
trap sync_auth EXIT

"$@"
