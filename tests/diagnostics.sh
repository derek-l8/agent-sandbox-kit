#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM
HOME="$work/home" XDG_DATA_HOME="$work/data" CODEX_SANDBOX_WORKSPACES_ROOT="$work/ws" "$root/bin/sandboxctl" version > "$work/version"
grep -q '^Kit version: 2.0.2$' "$work/version"
grep -q "^Runtime root: $root$" "$work/version"
grep -q '^Runtime kind: source$' "$work/version"
grep -q "^Workspace root: $work/ws$" "$work/version"
grep -q '^Network image: local/codex-sandbox-networked:2.0.2$' "$work/version"
printf 'PASS: version reports source root, launcher inputs, workspace, and images\n'
mkdir -p "$work/data/agent-sandbox-kit"
printf 'KIT_VERSION=2.0.1\n' > "$work/data/agent-sandbox-kit/versions.lock"
HOME="$work/home" XDG_DATA_HOME="$work/data" "$root/bin/sandboxctl" version > "$work/mismatch"
grep -q 'source=2.0.2, installed=2.0.1' "$work/mismatch"
grep -q 'run ./install.sh from this source checkout' "$work/mismatch"
printf 'PASS: source/installed mismatch gives both versions and reinstall action\n'
sed '$d' "$root/bin/sandboxctl" > "$work/library.sh"
source "$work/library.sh"
KIT_VERSION=2.0.2 NETWORK_IMAGE=local/codex-sandbox-networked:2.0.2 OFFLINE_IMAGE=local/codex-sandbox-offline:2.0.2 OPENCODE_IMAGE=local/codex-sandbox-opencode:2.0.2
PROJECT_SLUG=stale-probe PROJECT_NETWORK_IMAGE=local/codex-sandbox-networked:2.0.1 PROJECT_OFFLINE_IMAGE=local/codex-sandbox-offline:2.0.1 PROJECT_OPENCODE_IMAGE=local/codex-sandbox-opencode:2.0.1
if check_image_label "$PROJECT_NETWORK_IMAGE" io.codex-sandbox.kit.version 2.0.2 2.0.1 2>"$work/image"; then exit 1; fi
for expected in 'Image: local/codex-sandbox-networked:2.0.1' 'Label: io.codex-sandbox.kit.version' 'Expected: 2.0.2' 'Actual: 2.0.1' 'sbx upgrade stale-probe' 'Safe remediation: sbx build'; do grep -q "$expected" "$work/image"; done
printf 'PASS: stale image diagnostics identify image/label/values and exact recovery\n'
