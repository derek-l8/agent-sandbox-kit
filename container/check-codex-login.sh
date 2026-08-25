#!/usr/bin/env bash

set -u
source /usr/local/lib/codex-sandbox/check-common.sh

check_common_container_boundary
expect_file_value /etc/agent-mode networked-public "root-owned mode is networked-public"
expect_mount_mode /home/node/.codex rw "ephemeral Codex home is writable"
if [[ "${AUTH_VOLUME_READONLY:-0}" == "1" ]]; then
  expect_mount_mode /auth ro "project authentication store is read-only"
else
  expect_mount_mode /auth rw "project authentication store is writable"
fi
expect_not_mountpoint /workspace "project workspace is not mounted during authentication"
expect_absent /agent "agent data mounts are absent during authentication"

if command -v codex >/dev/null 2>&1; then
  pass "Codex CLI is installed"
else
  fail "Codex CLI is absent"
fi

finish_boundary_check codex-login
