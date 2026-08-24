#!/usr/bin/env bash

set -euo pipefail

auth_store=/auth/auth.json
runtime_auth="${CODEX_HOME}/auth.json"

mkdir -p "$CODEX_HOME"
if [[ -f "$auth_store" ]]; then
  install -m 0600 "$auth_store" "$runtime_auth"
fi

sync_auth() {
  if [[ -f "$runtime_auth" ]]; then
    install -m 0600 "$runtime_auth" "$auth_store"
  else
    rm -f "$auth_store"
  fi
}
trap sync_auth EXIT

"$@"
