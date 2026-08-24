#!/usr/bin/env bash

set -u
source /usr/local/lib/codex-sandbox/check-common.sh

check_common_container_boundary
expect_file_value /etc/agent-mode networked-public "root-owned mode is networked-public"

if [[ "$(pwd)" == "/workspace" ]]; then
  pass "workspace is /workspace"
else
  fail "workspace is not /workspace"
fi

expect_mount_mode /workspace rw "project workspace is writable"
expect_mount_mode /workspace/.git ro "Git metadata is read-only"
expect_mount_mode /agent/outbox rw "review outbox is writable"
expect_mount_mode /agent/scratch rw "public scratch is writable"
expect_mount_mode /home/node/.codex rw "ephemeral Codex home is writable"
expect_mount_mode /auth ro "project authentication store is read-only"
expect_absent /agent/inbox "private inbox is absent"

if [[ -r /etc/codex/config.toml && ! -w /etc/codex/config.toml ]]; then
  pass "system Codex config is root-owned/read-only"
else
  fail "system Codex config is missing or writable"
fi

if [[ -r /etc/codex/requirements.toml && ! -w /etc/codex/requirements.toml ]]; then
  pass "Codex requirements are root-owned/read-only"
else
  fail "Codex requirements are missing or writable"
fi

if command -v codex >/dev/null 2>&1; then
  pass "Codex CLI is installed"
else
  fail "Codex CLI is absent"
fi

finish_boundary_check networked
