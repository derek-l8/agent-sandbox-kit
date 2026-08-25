#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM
sed '$d' "$root/bin/sandboxctl" > "$work/library.sh"
source "$work/library.sh"
PROJECT_SLUG=auth-probe
AUTH_SCHEMA_VERSION=2
for kit in 2.0.0 2.0.1; do
  validate_auth_labels codex codex-sbx-auth-probe-auth-v2 true '' auth-probe '' "$kit"
  validate_auth_labels opencode codex-sbx-auth-probe-opencode-auth-v2 true opencode auth-probe '' "$kit"
done
validate_auth_labels codex probe true codex auth-probe 2 2.0.2
validate_auth_labels opencode probe true opencode auth-probe 2 2.0.2
printf 'PASS: compatible legacy and current auth schemas are accepted without mutation\n'
for spec in \
  'codex true codex wrong 2 2.0.2' \
  'codex true opencode auth-probe 2 2.0.2' \
  'opencode true opencode auth-probe 99 2.0.2' \
  'opencode false opencode auth-probe 2 2.0.2'; do
  read -r expected managed agent project schema kit <<< "$spec"
  if validate_auth_labels "$expected" probe "$managed" "$agent" "$project" "$schema" "$kit" \
      >"$work/out" 2>"$work/err"; then exit 1; fi
  grep -q 'incompatible authentication volume' "$work/err"
  grep -q 'Expected schema: 2' "$work/err"
  grep -q 'reset-auth auth-probe --yes' "$work/err"
  ! grep -q 'docker volume rm' "$work/err"
done
printf 'PASS: incompatible labels fail closed with exact, nonautomatic recovery\n'
