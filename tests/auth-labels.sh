#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM
sed '$d' "$root/bin/sandboxctl" > "$work/library.sh"
source "$work/library.sh"
PROJECT_SLUG=auth-probe
AUTH_SCHEMA_VERSION=2
validate_auth_labels codex probe true codex auth-probe 2 3.3.0
validate_auth_labels opencode probe true opencode auth-probe 2 3.3.0
validate_auth_labels claude probe true claude auth-probe 2 3.3.0
printf 'PASS: correctly labeled agent credentials are accepted\n'
for spec in \
  'codex true codex wrong 2 3.3.0' \
  'codex true opencode auth-probe 2 3.3.0' \
  'codex true missing auth-probe 2 3.3.0' \
  'codex true codex auth-probe missing 3.3.0' \
  'opencode true opencode auth-probe 99 3.3.0' \
  'opencode false opencode auth-probe 2 3.3.0' \
  'claude true codex auth-probe 2 3.3.0' \
  'claude true claude wrong 2 3.3.0' \
  'claude true claude auth-probe 99 3.3.0' \
  'claude false claude auth-probe 2 3.3.0'; do
  read -r expected managed agent project schema kit <<< "$spec"
  if [[ "$agent" == missing ]]; then agent=''; fi
  if [[ "$schema" == missing ]]; then schema=''; fi
  if validate_auth_labels "$expected" probe "$managed" "$agent" "$project" "$schema" "$kit" \
      >"$work/out" 2>"$work/err"; then exit 1; fi
  grep -q 'incompatible authentication volume' "$work/err"
  grep -q 'Expected schema: 2' "$work/err"
  grep -q 'reset-auth auth-probe --yes' "$work/err"
  ! grep -q 'docker volume rm' "$work/err"
done
printf 'PASS: missing or mismatched labels fail closed with exact, nonautomatic recovery\n'
