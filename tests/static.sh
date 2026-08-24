#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

while IFS= read -r script; do
  bash -n "$script"
done < <(find "$root" -type f -name '*.sh' -o -path "$root/bin/sandboxctl")

python3 - <<'PY' "$root/config/config.toml" "$root/config/requirements.toml"
import sys
import tomllib
for path in sys.argv[1:]:
    with open(path, "rb") as handle:
        tomllib.load(handle)
    print(f"PASS: parsed {path}")
PY

grep -Eq '^BASE_IMAGE=.+@sha256:[0-9a-f]{64}$' "$root/versions.lock"
grep -Eq '^CODEX_VERSION=[0-9]+\.[0-9]+\.[0-9]+$' "$root/versions.lock"
! grep -RIn 'REPLACE_PROJECT_SLUG\|include_apps_instructions\|/mnt/c/Users/derek/Documents/Codex/2026-' "$root" \
  --exclude=static.sh
! grep -RIn --exclude=static.sh -- '--ignore-user-config\|--ignore-rules' "$root"

printf 'RESULT: static checks passed\n'
