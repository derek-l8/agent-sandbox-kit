#!/usr/bin/env bash

# Proves that login-opencode, auth-status-opencode, and logout-opencode can
# reach ensure_opencode_auth_volume as a top-level function without another
# command (such as one that calls load_protected_mounts) defining it first.
#
# Model-free and Docker-free: the docker CLI is replaced by an instrumented
# stub, so the real command code paths run end to end against a synthetic
# project in a temporary directory. Calls are recorded to a file because the
# container-creation functions execute inside command substitutions.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Static guard: the function must be defined at top level (column 0).
grep -q '^ensure_opencode_auth_volume()' "$root/bin/sandboxctl" || {
  echo "FAIL: ensure_opencode_auth_volume is not defined at top level" >&2
  exit 1
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Drop the final "main $@" invocation so the file can be sourced as a library.
sed '$d' "$root/bin/sandboxctl" > "$work/sandboxctl-lib.sh"

slug="reachability-probe"
ws="$work/workspaces"
mkdir -p "$ws/$slug"/{repo/.git,inbox,outbox,scratch,control/logs}
printf 'PROJECT_SLUG=%s\nPROJECT_CPUS=4\nPROJECT_MEMORY=8g\n' "$slug" \
  > "$ws/$slug/control/project.env"

cat > "$work/harness.sh" <<'HARNESS'
set -euo pipefail
: > "$CALLLOG"

docker() {
  printf '%s\n' "$*" >> "$CALLLOG"
  local sub="${1:-}"
  case "$sub" in
    info|ps|rm|run|start|stop|create)
      return 0 ;;
    volume)
      case "${2:-}" in
        inspect) return 1 ;;
        *)       return 0 ;;
      esac ;;
    image)
      if [[ "${3:-}" == "--format" ]]; then
        case "$4" in
          *kit.version*) echo "$KIT_VERSION" ;;
          *opencode.version*) echo "$OPENCODE_VERSION" ;;
          *opencode.package-integrity*) echo "$OPENCODE_PACKAGE_INTEGRITY" ;;
          *opencode.linux-x64-integrity*) echo "$OPENCODE_LINUX_X64_INTEGRITY" ;;
          *codex.version*) echo "$CODEX_VERSION" ;;
          *codex.package-integrity*) echo "$CODEX_PACKAGE_INTEGRITY" ;;
          *codex.linux-x64-integrity*) echo "$CODEX_LINUX_X64_INTEGRITY" ;;
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
        '{{range .Mounts}}{{printf "%s|%s|%t\n" .Destination .Type .RW}}{{end}}')
          printf '/auth|volume|true\n' ;;
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

for command_name in cmd_login_opencode cmd_auth_status_opencode cmd_logout_opencode; do
  marker=$(wc -l < "$CALLLOG")
  "$command_name" "$SLUG" >/dev/null 2>&1
  if tail -n "+$((marker + 1))" "$CALLLOG" \
      | grep -Eq "^volume create .*codex-sbx-${SLUG}-opencode-auth-v2$"; then
    printf 'PASS: %s reached ensure_opencode_auth_volume\n' "$command_name"
  else
    printf 'FAIL: %s did not reach ensure_opencode_auth_volume\n' "$command_name" >&2
    exit 1
  fi
done
HARNESS

CALLLOG="$work/calls.txt" WS="$ws" LIB="$work/sandboxctl-lib.sh" ROOT="$root" \
  SLUG="$slug" bash "$work/harness.sh"

printf 'RESULT: command reachability checks passed\n'
