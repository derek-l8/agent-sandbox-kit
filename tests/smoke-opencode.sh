#!/usr/bin/env bash

# Model-free Docker integration smoke test for the OpenCode adapter.
#
# It exercises the REAL pinned image through the real launcher commands with a
# unique disposable project slug and a temporary workspace root, and verifies:
#   - doctor-opencode passes;
#   - exec-opencode runs `opencode --version` -> 1.18.21;
#   - the real task container passes its in-container boundary checks;
#   - the real authentication container passes its boundary checks without
#     requiring any login;
#   - task authentication is read-only, login authentication is writable;
#   - project/.git/outbox/scratch/tmpfs/resource/security/network/forbidden-
#     mount assertions match the launcher policy;
#   - /etc/opencode/opencode.json is actually loaded (`opencode debug config
#     --pure`) and resolves autoupdate/sharing/snapshot/MCP/server/external-
#     directory/Git/GitHub restrictions;
#   - a hostile repository opencode.json sentinel is absent because
#     OPENCODE_DISABLE_PROJECT_CONFIG=1 is active;
#   - a repository .opencode directory is shadowed when present.
#   - the real pinned OpenCode TUI initializes under a PTY and Bun extracts its
#     native OpenTUI library under the dedicated executable tmpfs.
#
# No model invocation, provider credential, external prompt, or authentication
# is used. Every probe is fail-closed: missing, malformed, or inconclusive
# output aborts the test with a nonzero status. Containers, the synthetic
# project, locks, and the OpenCode auth volume are removed on success AND
# failure.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ctl="$root/bin/sandboxctl"

slug="opencode-smoke-$(date -u +%Y%m%d-%H%M%S)-$$"
ws="$(mktemp -d)"
proj="$ws/$slug"
export CODEX_SANDBOX_WORKSPACES_ROOT="$ws"

pass() { printf 'PASS: %s\n' "$1"; }
failclosed() {
  printf 'FAIL (fail-closed): %s\n' "$1" >&2
  exit 1
}

cleanup() {
  local id volume="codex-sbx-${slug}-opencode-auth-v2"
  while IFS= read -r id; do
    [[ -n "$id" ]] && docker rm -f "$id" >/dev/null 2>&1 || true
  done < <(docker ps -aq --filter "label=io.codex-sandbox.project=$slug" 2>/dev/null || true)
  docker volume rm "$volume" >/dev/null 2>&1 || true
  case "$proj" in "$ws"/opencode-smoke-*) chmod -R u+w "$proj" 2>/dev/null || true; rm -rf -- "$proj" ;; esac
  rmdir "$ws" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# --- Preconditions: Docker daemon and the pinned image ----------------------
command -v docker >/dev/null 2>&1 || failclosed "docker CLI is missing"
docker info >/dev/null 2>&1 || failclosed "Docker daemon is unavailable"

read_lock_value() {
  sed -n "s/^$1=//p" "$root/versions.lock" | head -n1
}
KIT_VERSION_LOCK="$(read_lock_value KIT_VERSION)"
OPENCODE_VERSION_LOCK="$(read_lock_value OPENCODE_VERSION)"
OPENCODE_PKG_LOCK="$(read_lock_value OPENCODE_PACKAGE_INTEGRITY)"
OPENCODE_BIN_LOCK="$(read_lock_value OPENCODE_LINUX_X64_INTEGRITY)"
BASE_IMAGE_LOCK="$(read_lock_value BASE_IMAGE)"
[[ "$OPENCODE_VERSION_LOCK" == "1.18.21" ]] \
  || failclosed "versions.lock does not pin OpenCode 1.18.21"
IMAGE="$(read_lock_value OPENCODE_IMAGE)"
[[ -n "$IMAGE" ]] \
  || failclosed "versions.lock does not define OPENCODE_IMAGE"

docker image inspect "$IMAGE" >/dev/null 2>&1 \
  || failclosed "pinned image $IMAGE is missing; run: bin/sandboxctl build"

label() {
  docker image inspect --format "{{index .Config.Labels \"$2\"}}" "$IMAGE"
}
[[ "$(label "$IMAGE" io.codex-sandbox.kit.version)" == "$KIT_VERSION_LOCK" ]] \
  || failclosed "image kit-version label does not match versions.lock"
[[ "$(label "$IMAGE" io.codex-sandbox.opencode.version)" == "$OPENCODE_VERSION_LOCK" ]] \
  || failclosed "image OpenCode version label does not match versions.lock"
[[ "$(label "$IMAGE" io.codex-sandbox.opencode.package-integrity)" == "$OPENCODE_PKG_LOCK" ]] \
  || failclosed "image package-integrity label does not match versions.lock"
[[ "$(label "$IMAGE" io.codex-sandbox.opencode.linux-x64-integrity)" == "$OPENCODE_BIN_LOCK" ]] \
  || failclosed "image linux-x64-integrity label does not match versions.lock"
[[ "$(label "$IMAGE" io.codex-sandbox.mode)" == "networked-public" ]] \
  || failclosed "image mode label is invalid"
[[ "$(label "$IMAGE" io.codex-sandbox.base.image)" == "$BASE_IMAGE_LOCK" ]] \
  || failclosed "image base digest label does not match versions.lock"
pass "pinned image $IMAGE matches every versions.lock value"

# --- Synthetic disposable project -------------------------------------------
"$ctl" init "$slug" >/dev/null
mkdir -p "$proj/repo/.git"

# Hostile repository configuration and plugin markers: both MUST be inert.
printf '%s\n' '{ "autoupdate": true, "share": "enabled", "HOSTILE-PROJECT-CONFIG-SENTINEL": true }' \
  > "$proj/repo/opencode.json"
mkdir -p "$proj/repo/.opencode/plugin"
printf '%s\n' 'export const HOSTILE_PLUGIN = "HOSTILE-OPENCODE-PLUGIN-MARKER"' \
  > "$proj/repo/.opencode/plugin/hostile.ts"

# --- doctor-opencode ---------------------------------------------------------
doctor_out="$("$ctl" doctor-opencode "$slug")"
grep -q '^RESULT: project doctor passed (opencode)$' <<<"$doctor_out" \
  || failclosed "doctor-opencode did not print a passing result line"
pass "doctor-opencode passed"

latest_report() {
  local pattern="$1" found
  found="$(ls -t "$proj/control/logs/"*$pattern 2>/dev/null | head -n1 || true)"
  [[ -n "$found" ]] || failclosed "host-side boundary report is missing for pattern $pattern"
  printf '%s' "$found"
}

assert_report() {
  local report="$1" auth_mount="$2"
  grep -q '^Privileged: false$' "$report" || failclosed "report shows privileged container"
  grep -q '^Read-only root: true$' "$report" || failclosed "report shows writable root filesystem"
  grep -q '^Capability drop: \["ALL"\]$' "$report" || failclosed "capabilities are not fully dropped"
  grep -q '^Security options: .*no-new-privileges' "$report" \
    || failclosed "no-new-privileges is missing from the report"
  grep -q '^Network mode: bridge$' "$report" || failclosed "unexpected network mode"
  grep -q "^  /auth | volume | writable=${auth_mount}\$" "$report" \
    || failclosed "auth volume mount mode in report is not $auth_mount"
}

# --- Task session probe: boundaries, version, resources, shadowing ----------
task_probe='
set -euo pipefail
out=/agent/outbox
opencode --version >"$out/version.txt" 2>&1
grep -q 1.18.21 "$out/version.txt"

# Forbidden host surfaces.
test ! -e /mnt/c
test ! -e /var/run/docker.sock
test ! -e /home/node/.ssh
test -z "${SSH_AUTH_SOCK:-}"

# Mount policy.
findmnt -n -T /auth -o OPTIONS >"$out/auth-options.txt"
grep -qE "(^|,)ro(,|\$)" "$out/auth-options.txt"
findmnt -n -T /workspace/.git -o OPTIONS | grep -qE "(^|,)ro(,|\$)"
findmnt -n -T /agent/outbox -o OPTIONS | grep -qE "(^|,)rw(,|\$)"
findmnt -n -T /agent/scratch -o OPTIONS | grep -qE "(^|,)rw(,|\$)"
findmnt -n -T /home/node/.local/share/opencode >/dev/null
findmnt -n -T /home/node/.config >/dev/null
findmnt -n -T /home/node/.local/state >/dev/null
mountpoint -q /tmp
mountpoint -q /home/node/.cache
test "${BUN_TMPDIR:-}" = /run/opencode-bun-tmp
test "$(stat -c "%u:%g:%a" "$BUN_TMPDIR")" = "$(id -u):$(id -g):700"
findmnt -n -T /tmp -o OPTIONS | grep -qE "(^|,)noexec(,|\$)"
findmnt -n -T "$BUN_TMPDIR" -o FSTYPE | grep -qx tmpfs
! findmnt -n -T "$BUN_TMPDIR" -o OPTIONS | grep -qE "(^|,)noexec(,|\$)"
findmnt -n -T "$BUN_TMPDIR" -o OPTIONS | grep -qE "(^|,)nosuid(,|\$)"
findmnt -n -T "$BUN_TMPDIR" -o OPTIONS | grep -qE "(^|,)nodev(,|\$)"

# Security context.
awk "/^CapEff:/{exit (\$2 ~ /^0+\$/ ? 0 : 1)}" /proc/self/status
awk "/^NoNewPrivs:/{exit (\$2 == \"1\" ? 0 : 1)}" /proc/self/status

# Resource limits (cgroup v2; unreadable or missing values fail closed).
{ cat /sys/fs/cgroup/pids.max 2>/dev/null || echo unreadable; } >"$out/pids.txt"
{ cat /sys/fs/cgroup/memory.max 2>/dev/null || echo unreadable; } >"$out/memory.txt"
{ cat /sys/fs/cgroup/cpu.max 2>/dev/null || echo unreadable; } >"$out/cpu.txt"

# Repository extension surface must be shadowed (it exists in the repo).
if [[ -d /workspace/.opencode ]]; then
  [[ -z "$(ls -A /workspace/.opencode)" ]] || { echo "shadow-not-empty" >&2; exit 9; }
  printf "shadowed\n" >"$out/shadow.txt"
else
  printf "absent\n" >"$out/shadow.txt"
fi
'
"${ctl}" exec-opencode "$slug" -- bash -c "$task_probe" >/dev/null
pass "exec-opencode ran the task-session boundary probe (in-container checks included)"

grep -q '1.18.21' "$proj/outbox/version.txt" || failclosed "opencode --version did not report 1.18.21"
pass "opencode --version reports the pinned 1.18.21"

grep -qx 'ro' <(tr ',' '\n' < "$proj/outbox/auth-options.txt" | sed '/^$/d') \
  || failclosed "task-session /auth is not mounted read-only"
pass "task authentication volume is mounted read-only"

[[ "$(cat "$proj/outbox/shadow.txt")" == "shadowed" ]] \
  || failclosed "repository .opencode directory was not shadowed"
pass "repository .opencode directory is shadowed and empty"

[[ "$(cat "$proj/outbox/pids.txt")" == "512" ]] \
  || failclosed "pids limit is $(cat "$proj/outbox/pids.txt"), expected 512"
[[ "$(cat "$proj/outbox/memory.txt")" == "8589934592" ]] \
  || failclosed "memory limit is $(cat "$proj/outbox/memory.txt"), expected 8589934592 (8g)"
[[ "$(cat "$proj/outbox/cpu.txt")" == *"600000 100000"* ]] \
  || failclosed "cpu limit is '$(cat "$proj/outbox/cpu.txt")', expected '600000 100000' (6 cpus)"
pass "resource limits match the launcher policy (512 pids, 8g, 6 cpus)"

task_report="$(latest_report '-opencode-networked-host-check.txt')"
assert_report "$task_report" "false"
grep -q '^  /workspace | bind | writable=true$' "$task_report" \
  || failclosed "task report does not show the writable workspace mount"
pass "host-side task report confirms the launcher security policy"

# --- Real TUI startup under a PTY (no provider, prompt, or model) -----------
tui_probe='
set -euo pipefail
out=/agent/outbox
: >"$out/opencode-tui-libraries.txt"
(
  while :; do
    find "$BUN_TMPDIR" -maxdepth 2 -type f -name "*.so" -print \
      >>"$out/opencode-tui-libraries.txt" 2>/dev/null || true
    sleep 0.01
  done
) &
monitor=$!
set +e
TERM=xterm-256color timeout --signal=TERM 10s script -qefc "opencode --pure" \
  "$out/opencode-tui-output.txt" </dev/null
rc=$?
set -e
kill "$monitor" 2>/dev/null || true
wait "$monitor" 2>/dev/null || true
if grep -q "Failed to initialize OpenTUI render library" "$out/opencode-tui-output.txt"; then
  exit 21
fi
case "$rc" in 0|124|143) ;; *) exit "$rc" ;; esac
sort -u "$out/opencode-tui-libraries.txt" -o "$out/opencode-tui-libraries.txt"
grep -q "^/run/opencode-bun-tmp/.*\\.so$" "$out/opencode-tui-libraries.txt"
'
"${ctl}" exec-opencode "$slug" -- bash -c "$tui_probe" >/dev/null
! grep -q 'Failed to initialize OpenTUI render library' "$proj/outbox/opencode-tui-output.txt" \
  || failclosed "real pinned OpenCode TUI failed to initialize OpenTUI"
grep -q '^/run/opencode-bun-tmp/.*\.so$' "$proj/outbox/opencode-tui-libraries.txt" \
  || failclosed "OpenTUI native library was not observed in the dedicated Bun tmpfs"
pass "real pinned OpenCode TUI initialized under a PTY and extracted OpenTUI in BUN_TMPDIR"

# --- Managed configuration resolution ---------------------------------------
config_probe='
set -euo pipefail
out=/agent/outbox
if ! opencode debug config --pure >"$out/debug-config.json" 2>"$out/debug-config.err"; then
  cat "$out/debug-config.err" >&2
  exit 7
fi
test -s "$out/debug-config.json"
'
"${ctl}" exec-opencode "$slug" -- bash -c "$config_probe" >/dev/null
pass "opencode debug config --pure loaded /etc/opencode/opencode.json successfully"

python3 - "$proj/outbox/debug-config.json" <<'PY'
import json
import sys

path = sys.argv[1]
raw = open(path, encoding="utf-8").read()
try:
    cfg = json.loads(raw)
except Exception as exc:
    raise SystemExit(f"FAIL (fail-closed): debug config output is not valid JSON: {exc}")

if "HOSTILE-PROJECT-CONFIG-SENTINEL" in raw:
    raise SystemExit("FAIL (fail-closed): hostile repository opencode.json leaked into resolved config")

def values(obj, key):
    if isinstance(obj, dict):
        if key in obj:
            yield obj[key]
        for v in obj.values():
            yield from values(v, key)
    elif isinstance(obj, list):
        for v in obj:
            yield from values(v, key)

def require(label, key, predicate):
    hits = list(values(cfg, key))
    if not any(predicate(h) for h in hits):
        raise SystemExit(f"FAIL (fail-closed): managed setting not resolved: {label}")
    print(f"PASS: managed setting resolved: {label}")

require("autoupdate disabled", "autoupdate", lambda v: v is False)
require("sharing disabled", "share", lambda v: v == "disabled")
require("snapshots disabled", "snapshot", lambda v: v is False)
require("no MCP servers configured", "mcp", lambda v: v == {})
require("loopback-only server", "hostname", lambda v: v == "127.0.0.1")
require("mdns disabled", "mdns", lambda v: v is False)
require("external directories denied", "external_directory", lambda v: v == "deny")
for pattern in ["git push*", "git commit*", "git remote*", "git submodule*", "gh *"]:
    require(f"bash restriction denied: {pattern}", pattern, lambda v: v == "deny")

print("PASS: hostile repository opencode.json sentinel is absent (project config disabled)")
PY

# --- Authentication family (no login required) -------------------------------
if ! status_out="$("${ctl}" auth-status-opencode "$slug" 2>&1)"; then
  printf '%s\n' "$status_out" >&2
  failclosed "auth-status-opencode failed before completing its boundary checks"
fi
pass "authentication container passed its boundary checks without requiring login"

login_report="$(latest_report '-opencode-login-host-check.txt')"
assert_report "$login_report" "true"
! grep -q '^  /workspace' "$login_report" \
  || failclosed "authentication container unexpectedly mounted the workspace"
pass "login-family authentication volume is writable and no project mounts exist"

volume="codex-sbx-${slug}-opencode-auth-v2"
# Inspect the REAL volume, mounted read-only at /auth. Without this mount the
# check would inspect the image's empty /auth directory and falsely pass.
volume_content="$(docker run --rm --network none --read-only --cap-drop ALL \
  --security-opt no-new-privileges:true --pids-limit 64 --memory 256m --user node \
  --mount "type=volume,source=${volume},target=/auth,readonly" \
  --entrypoint /bin/bash "$IMAGE" -c 'ls -A /auth')"
[[ -z "$volume_content" ]] \
  || failclosed "auth volume is not empty although no login ever ran: $volume_content"
pass "auth volume holds no credentials (no provider, model, or authentication used)"

printf '\nRESULT: OpenCode adapter Docker smoke tests passed without a model invocation\n'
