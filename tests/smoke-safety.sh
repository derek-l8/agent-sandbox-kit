#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for smoke in "$root/tests/smoke-codex.sh" "$root/tests/smoke-opencode.sh"; do
  grep -q 'ws="$(mktemp -d)"' "$smoke"
  grep -q 'export CODEX_SANDBOX_WORKSPACES_ROOT="$ws"' "$smoke"
  grep -Eq 'slug="(codex|opencode)-smoke-.*\$\$"' "$smoke"
  grep -q 'trap cleanup EXIT INT TERM' "$smoke"
  ! grep -q 'sandbox-v2-test' "$smoke"
  ! grep -q '\$HOME/agent-workspaces' "$smoke"
  grep -q 'docker volume rm "$volume"' "$smoke"
  grep -q 'docker ps -aq --filter "label=io.codex-sandbox.project=\$slug"' "$smoke"
done
grep -q 'case "$project_root" in "$ws"/codex-smoke-\*)' "$root/tests/smoke-codex.sh"
grep -q 'case "$proj" in "$ws"/opencode-smoke-\*)' "$root/tests/smoke-opencode.sh"
printf 'PASS: smoke tests use unique temporary roots and cleanup only exact self-created state\n'
