#!/usr/bin/env bash

set -euo pipefail

# Official Codex file-based credential storage uses only
# $CODEX_HOME/auth.json. Task sessions mount /auth read-only; authentication
# containers mount it read-write and may synchronize the refreshed credential.
auth_store=/auth/auth.json
runtime_auth="${CODEX_HOME}/auth.json"

mkdir -p "$CODEX_HOME"
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
