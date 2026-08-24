#!/usr/bin/env bash

# Docker-free, model-free launcher boundary tests for the OpenCode adapter.
# An instrumented docker stub records every `docker create` invocation so the
# real command code paths run end to end against a synthetic project, and the
# recorded container definitions are asserted against:
#   - correct OpenCode image selection;
#   - project-only mount boundaries (workspace, read-only .git, outbox, scratch);
#   - absence of Windows, WSL-home, credential, inbox, and Docker-socket mounts;
#   - read-only auth volume in task sessions, writable only in login sessions;
#   - resource limits (cpus/memory/pids), read-only rootfs, cap-drop ALL,
#     no-new-privileges, and the disposable tmpfs set;
#   - OPENCODE_DISABLE_PROJECT_CONFIG=1 on OpenCode paths and `opencode --pure`
#     as the task-session command;
#   - same-project Codex/OpenCode concurrency locking;
#   - backward compatibility with existing project.env files.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

sed '$d' "$root/bin/sandboxctl" > "$work/sandboxctl-lib.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

slug="boundary-probe"
ws="$work/workspaces"
proj="$ws/$slug"
mkdir -p "$proj"/{repo/.git,inbox,outbox,scratch,control/logs}
printf 'PROJECT_SLUG=%s\nPROJECT_CPUS=3\nPROJECT_MEMORY=5g\nPROJECT_NETWORK_IMAGE=local/codex-sandbox-networked:2.0.0\nPROJECT_OFFLINE_IMAGE=local/codex-sandbox-offline:2.0.0\n' "$slug" \
  > "$proj/control/project.env"
touch "$proj/repo/AGENTS.md"

cat > "$work/harness.sh" <<'HARNESS'
set -euo pipefail
: > "$CALLLOG"

docker() {
  local sub="${1:-}"
  if [[ "$sub" == "create" ]]; then
    { printf 'CREATE '; printf '%s ' "$@"; printf '\n'; } >> "$CALLLOG"
    echo "fake-container-id"
    return 0
  fi
  printf '%s\n' "$*" >> "$CALLLOG"
  case "$sub" in
    info|ps|rm|start|stop)
      return 0 ;;
    volume)
      case "${2:-}" in
        inspect) return "${VOLUME_EXISTS_RC:-1}" ;;
        *)       return 0 ;;
      esac ;;
    image)
      if [[ "${3:-}" == "--format" ]]; then
        case "$4" in
          *kit.version*) echo "$KIT_VERSION" ;;
          *opencode.version*) echo "$OPENCODE_VERSION" ;;
          *opencode.package-integrity*) echo "$OPENCODE_PACKAGE_INTEGRITY" ;;
          *opencode.linux-x64-integrity*) echo "$OPENCODE_LINUX_X64_INTEGRITY" ;;
          *codex.package-integrity*) echo "$CODEX_PACKAGE_INTEGRITY" ;;
          *codex.linux-x64-integrity*) echo "$CODEX_LINUX_X64_INTEGRITY" ;;
          *codex.version*) echo "$CODEX_VERSION" ;;
          *base.image*) echo "$BASE_IMAGE" ;;
          *mode*)
            if [[ "${5:-}" == *offline* ]]; then
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
        *Mounts*)
          if [[ "${MOUNTS_MODE:-task}" == "login" ]]; then
            printf '/auth|volume|true\n'
          else
            printf '%s\n' \
              '/agent/outbox|bind|true' \
              '/agent/scratch|bind|true' \
              '/auth|volume|false' \
              '/workspace|bind|true' \
              '/workspace/.git|bind|false'
          fi ;;
        *Tmpfs*)
          printf '%s\n' /home/node/.cache /home/node/.config \
            /home/node/.local/share/opencode /home/node/.local/state /tmp ;;
        '{{.State.Status}}') echo "exited" ;;
        '{{.State.ExitCode}}') echo "0" ;;
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

"$@"
HARNESS

record_command() {
  local label="$1" mode="${2:-task}"
  shift 2
  rm -f "$work/calls.txt"
  local rc=0
  CALLLOG="$work/calls.txt" WS="$ws" LIB="$work/sandboxctl-lib.sh" ROOT="$root" \
    MOUNTS_MODE="$mode" \
    bash "$work/harness.sh" "$@" > /dev/null 2> "$work/stderr.txt" || rc=$?
  [[ "$rc" -eq 0 ]] || fail "$label exited with status $rc: $(cat "$work/stderr.txt")"
  [[ "$(grep -c '^CREATE ' "$work/calls.txt")" == 1 ]] \
    || fail "$label did not create exactly one container"
  grep '^CREATE ' "$work/calls.txt" | sed 's/^CREATE //; s/ $//' > "$work/create-args.txt"

  # Docker's image ENTRYPOINT is only replaced by --entrypoint placed before
  # the image name; anything after the image name is an ordinary argument.
  local entrypoint_count
  entrypoint_count="$(grep -o -- '--entrypoint' "$work/create-args.txt" | wc -l)"
  [[ "$entrypoint_count" == 1 ]] \
    || fail "$label must pass exactly one --entrypoint (found $entrypoint_count)"
  if grep -Eq -- " $opencode_image .*(/usr/local/bin/start-opencode|--entrypoint)" "$work/create-args.txt"; then
    fail "$label passes an entrypoint selection as a post-image command"
  fi
}

assert_create() {
  local pattern="$1" label="$2" invert="${3:-}"
  if [[ "$invert" == "absent" ]]; then
    if grep -Eq -- "$pattern" "$work/create-args.txt"; then
      fail "$label: forbidden create argument found ($pattern)"
    fi
  else
    grep -Eq -- "$pattern" "$work/create-args.txt" \
      || fail "$label: missing expected create argument ($pattern)"
  fi
  printf 'PASS: %s\n' "$label"
}

opencode_image="local/codex-sandbox-opencode:2.0.0"

# --- Task session: run-opencode -------------------------------------------
record_command "run-opencode" task cmd_run_opencode "$slug"

assert_create "--cap-drop ALL" "task session drops all capabilities"
assert_create --read-only "task session uses a read-only root filesystem"
assert_create "no-new-privileges:true" "task session enables no-new-privileges"
assert_create --pids-limit "task session sets a process limit"
assert_create '--memory 5g' "task session honors PROJECT_MEMORY from project.env"
assert_create '--cpus 3' "task session honors PROJECT_CPUS from project.env"
assert_create "type=volume,source=codex-sbx-${slug}-opencode-auth-v2,target=/auth,readonly" \
  "task session mounts a separate OpenCode auth volume read-only"
assert_create "type=bind,source=$proj/repo,target=/workspace" "task session mounts only the project repo"
assert_create "type=bind,source=$proj/repo/.git,target=/workspace/.git,readonly" "Git metadata is read-only"
assert_create "source=$proj/outbox,target=/agent/outbox" "review outbox is mounted"
assert_create "source=$proj/scratch,target=/agent/scratch" "scratch space is mounted"
assert_create "/mnt/c" "no Windows drive is mounted" absent
assert_create "docker.sock" "no Docker socket is mounted" absent
assert_create "\.ssh" "no SSH material is mounted" absent
assert_create "target=$HOME" "no WSL home directory is mounted" absent
assert_create "inbox" "private inbox is never mounted in task sessions" absent
assert_create "OPENCODE_DISABLE_PROJECT_CONFIG=1" "project config override is disabled"
assert_create "--entrypoint /usr/local/bin/start-opencode-session $opencode_image opencode --pure" \
  "task session replaces the image entrypoint once and runs opencode --pure"
assert_create "start-opencode-auth-session" \
  "task session never selects the authentication entrypoint" absent

for tmpfs_target in \
  'tmpfs /tmp:' \
  'tmpfs /home/node/.cache' \
  'tmpfs /home/node/.config' \
  'tmpfs /home/node/.local/state' \
  'tmpfs /home/node/.local/share/opencode'; do
  grep -q "$tmpfs_target" "$work/create-args.txt" \
    || fail "disposable tmpfs target is missing: $tmpfs_target"
done
echo "PASS: writable disposable tmpfs locations are present"

[[ ! -e "$proj/control/.session-lock" ]] || fail "session lock was not released after run-opencode"
echo "PASS: session lock is released when the command exits"

# --- Shell and exec sessions ------------------------------------------------
record_command "shell-opencode" task cmd_shell_opencode "$slug"
assert_create "--entrypoint /usr/local/bin/start-opencode-session $opencode_image bash" \
  "shell session opens bash in the pinned image"
assert_create "target=/auth,readonly" "shell session keeps authentication read-only"

record_command "exec-opencode" task cmd_exec_opencode "$slug" -- git status
assert_create "--entrypoint /usr/local/bin/start-opencode-session $opencode_image git status" \
  "exec session forwards the requested command"

# --- Login family: auth writable, workspace absent --------------------------
record_command "login-opencode" login cmd_login_opencode "$slug"
assert_create "type=volume,source=codex-sbx-${slug}-opencode-auth-v2,target=/auth " \
  "login container mounts the dedicated OpenCode auth volume without readonly"
assert_create "target=/workspace" "login container never mounts the project workspace" absent
assert_create "--entrypoint /usr/local/bin/start-opencode-auth-session $opencode_image opencode auth login" \
  "login container runs opencode auth login"
assert_create "OPENCODE_DISABLE_PROJECT_CONFIG=1" "login container disables project config"
assert_create "--entrypoint /usr/local/bin/start-opencode-session" \
  "login container never selects the task-session entrypoint" absent

record_command "logout-opencode" login cmd_logout_opencode "$slug"
assert_create "--entrypoint /usr/local/bin/start-opencode-auth-session $opencode_image opencode auth logout" \
  "logout container runs opencode auth logout"

record_command "auth-status-opencode" login cmd_auth_status_opencode "$slug"
assert_create "--entrypoint /usr/local/bin/start-opencode-auth-session $opencode_image opencode auth list" \
  "auth-status container lists providers"

# --- Backward compatibility: legacy project.env without OpenCode keys -------
legacy_slug="legacy-probe"
mkdir -p "$ws/$legacy_slug"/{repo/.git,inbox,outbox,scratch,control/logs}
printf 'PROJECT_SLUG=%s\nPROJECT_CPUS=2\nPROJECT_MEMORY=4g\n' "$legacy_slug" \
  > "$ws/$legacy_slug/control/project.env"
record_command "legacy project.env exec-opencode" task cmd_exec_opencode "$legacy_slug" -- true
assert_create "--entrypoint /usr/local/bin/start-opencode-session $opencode_image true" \
  "existing project.env without PROJECT_OPENCODE_IMAGE works with the default image"

# --- Concurrency locking ----------------------------------------------------
mkdir -p "$proj/control/.session-lock"
printf 'agent=codex\npid=%d\nstarted=x\n' "$$" > "$proj/control/.session-lock/owner.txt"

rc=0
CALLLOG="$work/calls.txt" WS="$ws" LIB="$work/sandboxctl-lib.sh" ROOT="$root" \
  bash "$work/harness.sh" cmd_run_opencode "$slug" >/dev/null 2> "$work/lock-stderr.txt" || rc=$?
if [[ "$rc" -eq 0 ]] || ! grep -q "a session is already active" "$work/lock-stderr.txt"; then
  fail "run-opencode did not respect an active same-project Codex lock"
fi
echo "PASS: run-opencode refuses to start while a Codex session holds the lock"

rc=0
CALLLOG="$work/calls.txt" WS="$ws" LIB="$work/sandboxctl-lib.sh" ROOT="$root" \
  bash "$work/harness.sh" cmd_run "$slug" >/dev/null 2>> "$work/lock-stderr.txt" || rc=$?
if [[ "$rc" -eq 0 ]] || ! grep -q "a session is already active" "$work/lock-stderr.txt"; then
  fail "codex run did not respect an active same-project lock"
fi
rm -rf "$proj/control/.session-lock"
echo "PASS: codex run refuses to start while the same-project lock is held"

printf 'RESULT: launcher boundary checks passed\n'
