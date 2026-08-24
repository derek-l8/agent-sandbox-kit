#!/usr/bin/env bash

set -u
source /usr/local/lib/codex-sandbox/check-common.sh

check_common_container_boundary
expect_file_value /etc/agent-mode networked-public "root-owned mode is networked-public"
expect_mount_mode /home/node/.local/state rw "disposable XDG state is writable tmpfs"
expect_mount_mode /home/node/.local/share/opencode rw "ephemeral OpenCode state is writable"
expect_mount_mode /auth rw "project authentication store is writable"
expect_not_mountpoint /workspace "project workspace is not mounted during authentication"
expect_absent /agent "agent data mounts are absent during authentication"

if [[ -r /etc/opencode/opencode.json && ! -w /etc/opencode/opencode.json ]]; then
  pass "managed OpenCode configuration is root-owned/read-only"
else
  fail "managed OpenCode configuration is missing or writable"
fi

if command -v opencode >/dev/null 2>&1; then
  pass "OpenCode CLI is installed"
else
  fail "OpenCode CLI is absent"
fi

finish_boundary_check opencode-login
