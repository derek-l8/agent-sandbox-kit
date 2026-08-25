#!/usr/bin/env bash

# Docker-free control-flow tests for Codex authentication-volume cleanup.
# Exercises the real launcher lifecycle functions with instrumented helpers.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

sed '$d' "$root/bin/sandboxctl" > "$work/sandboxctl-lib.sh"

cat > "$work/harness.sh" <<'HARNESS'
set -euo pipefail
source "$LIB"

count=0
ensure_codex_auth_volume() {
  printf 'ensure\n' >> "$CALLLOG"
}
prune_codex_auth_volume() {
  count=$((count + 1))
  printf 'prune %s\n' "$count" >> "$CALLLOG"
  if [[ "$count" -eq 1 && -n "${PRE_PRUNE_RC:-}" ]]; then
    return "$PRE_PRUNE_RC"
  fi
  if [[ "$count" -ge 2 && -n "${POST_PRUNE_RC:-}" ]]; then
    return "$POST_PRUNE_RC"
  fi
}
create_probe() {
  printf 'create\n' >> "$CALLLOG"
  printf 'fake-container'
}
run_created_container() {
  printf 'start\n' >> "$CALLLOG"
  return "${START_RC:-0}"
}

PROJECT_SLUG=control-flow-probe
prepare_codex_command
run_codex_command create_probe false true
HARNESS

run_scenario() {
  local name="$1" expected="$2" stderr_pattern="${3:-}"
  : > "$work/calls.txt"
  local rc=0
  START_RC="${START_RC:-}" PRE_PRUNE_RC="${PRE_PRUNE_RC:-}" \
    POST_PRUNE_RC="${POST_PRUNE_RC:-}" \
    CALLLOG="$work/calls.txt" LIB="$work/sandboxctl-lib.sh" \
    bash "$work/harness.sh" > /dev/null 2> "$work/stderr.txt" || rc=$?
  [[ "$rc" -eq "$expected" ]] || {
    printf 'FAIL [%s]: exit status %s, expected %s\n' "$name" "$rc" "$expected" >&2
    exit 1
  }
  if [[ -n "$stderr_pattern" ]]; then
    grep -q "$stderr_pattern" "$work/stderr.txt" || {
      printf 'FAIL [%s]: missing stderr pattern: %s\n' "$name" "$stderr_pattern" >&2
      exit 1
    }
  fi
  printf 'PASS [%s]\n' "$name"
}

START_RC=0 PRE_PRUNE_RC= POST_PRUNE_RC= run_scenario success 0
[[ "$(grep -c '^prune ' "$work/calls.txt")" -eq 2 ]]

START_RC=37 PRE_PRUNE_RC= POST_PRUNE_RC= \
  run_scenario failure_preserves_status 37
[[ "$(grep -c '^prune ' "$work/calls.txt")" -eq 2 ]]

# Exit status 130 represents an interrupted container command. The launcher
# must still attempt post-command cleanup once control returns.
START_RC=130 PRE_PRUNE_RC= POST_PRUNE_RC= \
  run_scenario interrupted_command_cleanup 130
[[ "$(grep -c '^prune ' "$work/calls.txt")" -eq 2 ]]

START_RC=0 PRE_PRUNE_RC=9 POST_PRUNE_RC= \
  run_scenario pre_cleanup_fails_closed 9
! grep -q '^create$' "$work/calls.txt"

START_RC=0 PRE_PRUNE_RC= POST_PRUNE_RC=8 \
  run_scenario post_cleanup_failure_visible 1 'Codex authentication-volume cleanup failed'

START_RC=37 PRE_PRUNE_RC= POST_PRUNE_RC=8 \
  run_scenario command_failure_wins 37 'Codex authentication-volume cleanup failed'

printf 'RESULT: Codex authentication control-flow checks passed\n'
