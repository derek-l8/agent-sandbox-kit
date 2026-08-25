#!/usr/bin/env bash

# Root-owned authentication-volume pruning script, baked into the Codex and
# OpenCode networked images at
# /usr/local/lib/codex-sandbox/prune-auth-volume.
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

# Only a regular, non-symlink, syntactically valid JSON credential is accepted.
if [[ -e "$auth_dir/auth.json" || -L "$auth_dir/auth.json" ]]; then
  if [[ -f "$auth_dir/auth.json" && ! -L "$auth_dir/auth.json" ]]; then
    if ! node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' \
        "$auth_dir/auth.json" >/dev/null 2>&1; then
      printf 'ERROR: authentication credential is malformed JSON: %s\n' "$auth_dir/auth.json" >&2
      exit 1
    fi
    chmod 0600 "$auth_dir/auth.json"
  else
    rm -rf -- "$auth_dir/auth.json"
    printf 'ERROR: authentication credential was not a regular file and was removed: %s\n' \
      "$auth_dir/auth.json" >&2
    exit 1
  fi
fi

# Delete every direct child except auth.json. A deletion failure aborts
# through set -e instead of being reported as success.
unexpected="$(find "$auth_dir" -mindepth 1 -maxdepth 1 ! -name auth.json -print -quit)"
find "$auth_dir" -mindepth 1 -maxdepth 1 ! -name auth.json -exec rm -rf -- {} +
if [[ -n "$unexpected" ]]; then
  printf 'ERROR: unexpected authentication content was removed; refusing to continue: %s\n' \
    "$unexpected" >&2
  exit 1
fi

# Postcondition: nothing except auth.json may remain.
unexpected="$(find "$auth_dir" -mindepth 1 -maxdepth 1 ! -name auth.json -print -quit)"
if [[ -n "$unexpected" ]]; then
  printf 'ERROR: unexpected content remains in the authentication volume: %s\n' \
    "$unexpected" >&2
  exit 1
fi

if [[ -e "$auth_dir/auth.json" || -L "$auth_dir/auth.json" ]]; then
  if [[ ! -f "$auth_dir/auth.json" || -L "$auth_dir/auth.json" ]]; then
    printf 'ERROR: authentication credential is not a regular file: %s\n' \
      "$auth_dir/auth.json" >&2
    exit 1
  fi
  mode="$(stat -c '%a' "$auth_dir/auth.json")"
  if [[ "$mode" != "600" ]]; then
    printf 'ERROR: authentication credential mode is %s, expected 600\n' "$mode" >&2
    exit 1
  fi
fi
