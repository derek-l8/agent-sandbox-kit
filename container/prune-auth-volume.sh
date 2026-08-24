#!/usr/bin/env bash

# Root-owned authentication-volume pruning script (baked into the pinned
# OpenCode image at /usr/local/lib/codex-sandbox/prune-auth-volume).
#
# Guarantees the mounted volume contains at most the single minimum provider
# credential file (auth.json), and fails closed: any deletion failure,
# verification failure, or real chmod failure produces a nonzero exit.

set -euo pipefail

auth_dir="${1:-/auth}"

if [[ ! -d "$auth_dir" ]]; then
  printf 'ERROR: authentication volume directory is missing: %s\n' "$auth_dir" >&2
  exit 1
fi

# Normalize the credential permission when it exists; a real chmod error
# aborts through set -e.
if [[ -e "$auth_dir/auth.json" ]]; then
  chmod 0600 "$auth_dir/auth.json"
fi

# Delete every direct child except auth.json. A deletion failure aborts
# through set -e instead of being reported as success.
find "$auth_dir" -mindepth 1 -maxdepth 1 ! -name auth.json -exec rm -rf -- {} +

# Postcondition: nothing except auth.json may remain.
unexpected="$(find "$auth_dir" -mindepth 1 -maxdepth 1 ! -name auth.json -print -quit)"
if [[ -n "$unexpected" ]]; then
  printf 'ERROR: unexpected content remains in the authentication volume: %s\n' \
    "$unexpected" >&2
  exit 1
fi
