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
expect_mount_mode /data rw "persistent data is writable"
expect_mount_mode /context ro "supplied context is read-only"
expect_mount_mode /home/node/.claude rw "ephemeral Claude Code home is writable"
expect_mount_mode /auth ro "project authentication store is read-only"

if [[ -r /etc/claude-code/managed-settings.json && ! -w /etc/claude-code/managed-settings.json ]]; then
  pass "managed Claude settings are read-only"
else
  fail "managed Claude settings are missing or writable"
fi

if command -v claude >/dev/null 2>&1; then
  pass "Claude Code CLI is installed"
else
  fail "Claude Code CLI is absent"
fi

finish_boundary_check claude-networked
