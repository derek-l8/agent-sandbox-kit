#!/usr/bin/env bash

# Docker-free control-flow tests for OpenCode command lifecycle handling.
# Uses an instrumented docker stub to prove:
#   1. finish_opencode (post-command auth-volume prune) runs after SUCCESS;
#   2. finish_opencode runs after a FAILED container command;
#   3. the original container failure status is preserved;
#   4. a failed pre-command prune prevents the command from starting;
#   5. a failed post-command prune is a visible failure, never silent success.
# Model-free; no Docker daemon is contacted.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

sed '$d' "$root/bin/sandboxctl" > "$work/sandboxctl-lib.sh"

slug="control-flow-probe"
ws="$work/workspaces"
mkdir -p "$ws/$slug"/{repo/.git,inbox,outbox,scratch,control/logs}
printf 'PROJECT_SLUG=%s\nPROJECT_CPUS=4\nPROJECT_MEMORY=8g\n' "$slug" \
  > "$ws/$slug/control/project.env"

cat > "$work/harness.sh" <<'HARNESS'
set -euo pipefail
: > "$CALLLOG"
echo 0 > "$RUNCOUNT"
echo no > "$STARTED"

docker() {
  printf '%s\n' "$*" >> "$CALLLOG"
  local sub="${1:-}"
  case "$sub" in
    info|rm|stop)
      return 0 ;;
    ps)
      if [[ -n "${PS_LIST_FILE:-}" && -s "$PS_LIST_FILE" ]]; then
        cat "$PS_LIST_FILE"
      fi
      return 0 ;;
    create)
      echo "fake-container-id"
      return 0 ;;
    start)
      echo yes > "$STARTED"
      return "${START_RC:-0}" ;;
    rm)
      return "${RM_RC:-0}" ;;
    run)
      local n
      n="$(cat "$RUNCOUNT")"
      n=$((n + 1))
      echo "$n" > "$RUNCOUNT"
      if [[ "$n" == 1 && -n "${PRE_PRUNE_RC:-}" ]]; then return "$PRE_PRUNE_RC"; fi
      if [[ "$n" -ge 2 && -n "${POST_PRUNE_RC:-}" ]]; then return "$POST_PRUNE_RC"; fi
      return 0 ;;
    volume)
      case "${2:-}" in
        inspect)
          if [[ "${3:-}" == "--format" ]]; then
            case "$4" in
              *managed*) echo "true" ;;
              *agent*) echo "opencode" ;;
              *project*) echo "$SLUG" ;;
              *kit.version*) echo "$KIT_VERSION" ;;
              *) echo "" ;;
            esac
          fi
          return 0 ;;
        *)       return 0 ;;
      esac ;;
    image)
      if [[ "${3:-}" == "--format" ]]; then
        local img="${5:-}"
        case "$4" in
          *kit.version*) echo "$KIT_VERSION" ;;
          *adapter-version*) echo "$OPENCODE_ADAPTER_VERSION" ;;
          *opencode.version*) echo "$OPENCODE_VERSION" ;;
          *opencode.package-integrity*) echo "$OPENCODE_PACKAGE_INTEGRITY" ;;
          *opencode.linux-x64-integrity*) echo "$OPENCODE_LINUX_X64_INTEGRITY" ;;
          *base.image*) echo "$BASE_IMAGE" ;;
          *codex.version*) echo "$CODEX_VERSION" ;;
          *codex.package-integrity*) echo "$CODEX_PACKAGE_INTEGRITY" ;;
          *codex.linux-x64-integrity*) echo "$CODEX_LINUX_X64_INTEGRITY" ;;
          *mode*)
            if [[ "$img" == *offline* ]]; then
              echo "offline-private-test"
            else
              echo "networked-public"
            fi ;;
          *) echo "" ;;
        esac
      fi
      return 0 ;;
    inspect)
      case "${3:-}" in
        '{{.HostConfig.Privileged}}') echo "false" ;;
        '{{.HostConfig.ReadonlyRootfs}}') echo "true" ;;
        '{{.HostConfig.NetworkMode}}') echo "bridge" ;;
        '{{json .HostConfig.CapDrop}}') echo '["ALL"]' ;;
        '{{json .HostConfig.SecurityOpt}}') echo '["no-new-privileges:true"]' ;;
        '{{json .HostConfig.Devices}}'|'{{json .HostConfig.PortBindings}}') echo "null" ;;
        '{{range .Mounts}}{{printf "%s|%s|%t\n" .Destination .Type .RW}}{{end}}')
          printf '%s\n' \
            '/agent/outbox|bind|true' \
            '/agent/scratch|bind|true' \
            '/auth|volume|false' \
            '/workspace|bind|true' \
            '/workspace/.git|bind|false' ;;
        *Tmpfs*)
          printf '%s\n' /home/node/.cache /home/node/.config \
            /home/node/.local/share/opencode /home/node/.local/state /tmp ;;
        '{{.State.Status}}') echo "exited" ;;
        '{{.State.ExitCode}}') echo "${START_RC:-0}" ;;
        *) echo "stub" ;;
      esac
      return 0 ;;
    *) return 0 ;;
  esac
}

export CODEX_SANDBOX_WORKSPACES_ROOT="$WS"
source "$LIB"
KIT_ROOT="$ROOT"
VERSIONS_FILE="$KIT_ROOT/versions.lock"
read_versions

cmd_exec_opencode "$SLUG" -- true
HARNESS

run_scenario() {
  local name="$1" expect_rc="$2" stderr_pattern="${3:-}"
  shift 3
  : > "$work/calls.txt"
  set +e
  START_RC="$START_RC" PRE_PRUNE_RC="$PRE_PRUNE_RC" POST_PRUNE_RC="$POST_PRUNE_RC" \
    CALLLOG="$work/calls.txt" RUNCOUNT="$work/runcount" STARTED="$work/started" \
    WS="$ws" LIB="$work/sandboxctl-lib.sh" ROOT="$root" SLUG="$slug" \
    bash "$work/harness.sh" > /dev/null 2> "$work/stderr.txt"
  local rc=$?
  set -e
  [[ "$rc" == "$expect_rc" ]] || {
    echo "FAIL [$name]: exit status $rc, expected $expect_rc" >&2
    return 1
  }
  if [[ -n "$stderr_pattern" ]]; then
    grep -q "$stderr_pattern" "$work/stderr.txt" || {
      echo "FAIL [$name]: stderr missing pattern '$stderr_pattern'" >&2
      cat "$work/stderr.txt" >&2
      return 1
    }
  fi
  cp "$work/calls.txt" "$work/calls-last.txt"
  echo "PASS [$name]"
}

assert_log() {
  local pattern="$1" label="$2"
  grep -Eq "$pattern" "$work/calls-last.txt" || {
    echo "FAIL: call log missing $label" >&2
    cat "$work/calls-last.txt" >&2
    return 1
  }
}

# 1. Success: pre-prune and post-prune both run, around the container start.
START_RC=0 PRE_PRUNE_RC= POST_PRUNE_RC= \
  run_scenario "finish-prune-runs-on-success" 0 ""
assert_log '^create ' "container creation"
assert_log '^start ' "container start"
[[ "$(grep -c '^run ' "$work/calls-last.txt")" == 2 ]] || {
  echo "FAIL: expected exactly two prune invocations (before and after)" >&2; exit 1;
}
[[ "$(grep -n '^run ' "$work/calls-last.txt" | tail -n1 | cut -d: -f1)" > \
   "$(grep -n '^start ' "$work/calls-last.txt" | cut -d: -f1)" ]] || {
  echo "FAIL: post-command prune did not run after the container" >&2; exit 1;
}

# 2+3. Failed container command: prune still runs, original status preserved.
START_RC=35 PRE_PRUNE_RC= POST_PRUNE_RC= \
  run_scenario "finish-prune-runs-on-failure-status-preserved" 35 ""
[[ "$(grep -c '^run ' "$work/calls-last.txt")" == 2 ]] || {
  echo "FAIL: post-failure prune did not run" >&2; exit 1;
}

# 4. Failed pre-command prune blocks execution entirely (fail closed).
START_RC=0 PRE_PRUNE_RC=7 POST_PRUNE_RC= \
  run_scenario "failed-pre-prune-prevents-start" 7 ""
if grep -q '^create ' "$work/calls-last.txt"; then
  echo "FAIL: container was created despite failed pre-command prune" >&2; exit 1;
fi

# 5. Failed post-command prune: visible nonzero result with explicit error,
#    even though the container command itself succeeded.
START_RC=0 PRE_PRUNE_RC= POST_PRUNE_RC=9 \
  run_scenario "failed-post-prune-not-silent" 1 'authentication-volume prune failed'

# Original failure status still wins over the prune failure status, but the
# prune failure remains loudly visible on stderr.
START_RC=35 PRE_PRUNE_RC= POST_PRUNE_RC=9 \
  run_scenario "original-status-and-visible-prune-failure" 35 'authentication-volume prune failed'

# 6. Simulated stale-container removal failure blocks container creation:
#    docker ps keeps reporting a matching container, docker rm fails, and the
#    sweep re-query must fail closed before anything is created.
printf 'leftover-id-1\nleftover-id-2\n' > "$work/ps-list.txt"
START_RC=0 PRE_PRUNE_RC= POST_PRUNE_RC= RM_RC=1 PS_LIST_FILE="$work/ps-list.txt" \
  run_scenario "stale-container-removal-failure-blocks-start" 1 'could not be removed'
if grep -q '^create ' "$work/calls-last.txt"; then
  echo "FAIL: container was created despite unremovable stale containers" >&2; exit 1;
fi

printf 'RESULT: control-flow checks passed\n'
