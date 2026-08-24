#!/usr/bin/env bash

set -u
source /usr/local/lib/codex-sandbox/check-common.sh

check_common_container_boundary
expect_file_value /etc/agent-mode offline-private-test "root-owned mode is offline-private-test"
expect_mount_mode /source ro "source snapshot is read-only"
expect_mount_mode /agent/inbox ro "private inbox is read-only"
expect_mount_mode /agent/outbox rw "review outbox is writable"
expect_mount_mode /workspace rw "disposable workspace is writable"

if command -v codex >/dev/null 2>&1; then
  fail "Codex CLI is installed in the offline runner"
else
  pass "Codex CLI is absent from the offline runner"
fi

if curl --max-time 3 --silent --show-error https://example.com >/dev/null 2>&1; then
  fail "external network request succeeded"
else
  pass "external network request was blocked"
fi

finish_boundary_check offline

