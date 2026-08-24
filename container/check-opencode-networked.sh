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
expect_mount_mode /home/node/.local/state rw "disposable XDG state is writable tmpfs"
expect_mount_mode /home/node/.local/share/opencode rw "ephemeral OpenCode state is writable"
expect_mount_mode /auth ro "project authentication store is mounted read-only in sessions"
expect_absent /agent/inbox "private inbox is absent"

if [[ -r /etc/opencode/opencode.json && ! -w /etc/opencode/opencode.json ]]; then
  pass "managed OpenCode configuration is root-owned/read-only"
else
  fail "managed OpenCode configuration is missing or writable"
fi

if [[ -d /workspace/.opencode ]]; then
  # The project extension directory must be a shadow mount without repo content.
  expect_mount_mode /workspace/.opencode rw "project .opencode surface is shadowed"
  if [[ -n "$(ls -A /workspace/.opencode 2>/dev/null)" ]]; then
    fail "shadowed .opencode directory is not empty"
  else
    pass "shadowed .opencode directory is empty"
  fi
else
  pass "project .opencode surface is absent or shadowed"
fi

if command -v opencode >/dev/null 2>&1; then
  pass "OpenCode CLI is installed"
else
  fail "OpenCode CLI is absent"
fi

finish_boundary_check opencode-networked
