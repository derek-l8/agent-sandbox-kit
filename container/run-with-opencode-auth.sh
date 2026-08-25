#!/usr/bin/env bash

# Root-owned wrapper. Only the minimum provider credential file
# (~/.local/share/opencode/auth.json) is copied in from the project auth
# volume. In task sessions the volume is mounted READ-ONLY, so nothing can
# persist through it; only authentication containers (which mount it
# read-write) synchronize the credential back on exit.

set -euo pipefail

# Defense in depth: repository opencode.json must never override the managed
# configuration. The image ENV and the launcher set this too; this guard
# covers any remaining execution path.
: "${OPENCODE_DISABLE_PROJECT_CONFIG:=1}"
export OPENCODE_DISABLE_PROJECT_CONFIG
: "${BUN_TMPDIR:=/run/opencode-bun-tmp}"
export BUN_TMPDIR

auth_store=/auth/auth.json
data_home="${XDG_DATA_HOME:-${HOME}/.local/share}"
runtime_dir="${data_home}/opencode"
runtime_auth="${runtime_dir}/auth.json"

mkdir -p "$runtime_dir"
chmod 0700 "$runtime_dir" 2>/dev/null || true
if [[ -f "$auth_store" ]]; then
  install -m 0600 "$auth_store" "$runtime_auth"
fi

sync_auth() {
  # Read-only session mounts cannot (and must not) persist anything.
  [[ -w /auth ]] || return 0
  if [[ -f "$runtime_auth" ]]; then
    install -m 0600 "$runtime_auth" "$auth_store"
  else
    rm -f "$auth_store"
  fi
}
trap sync_auth EXIT

"$@"
