#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM
HOME="$work/home" XDG_DATA_HOME="$work/data" CODEX_SANDBOX_WORKSPACES_ROOT="$work/ws" "$root/bin/sandboxctl" version > "$work/version"
grep -q '^Kit version: 3.3.0$' "$work/version"
grep -q "^Runtime root: $root$" "$work/version"
grep -q '^Runtime kind: source$' "$work/version"
grep -q "^Workspace root: $work/ws$" "$work/version"
grep -q '^Network image: local/codex-sandbox-networked:3.3.0$' "$work/version"
printf 'PASS: version reports source root, launcher inputs, workspace, and images\n'
mkdir -p "$work/data/agent-sandbox-kit"
printf 'KIT_VERSION=stale-test\n' > "$work/data/agent-sandbox-kit/versions.lock"
HOME="$work/home" XDG_DATA_HOME="$work/data" "$root/bin/sandboxctl" version > "$work/mismatch"
grep -q 'source=3.3.0, installed=stale-test' "$work/mismatch"
grep -q 'run ./install.sh from this source checkout' "$work/mismatch"
printf 'PASS: source/installed mismatch gives both versions and reinstall action\n'
sed '$d' "$root/bin/sandboxctl" > "$work/library.sh"
source "$work/library.sh"
KIT_VERSION=3.3.0 NETWORK_IMAGE=local/codex-sandbox-networked:3.3.0 OPENCODE_IMAGE=local/codex-sandbox-opencode:3.3.0
PROJECT_SLUG=stale-probe PROJECT_NETWORK_IMAGE=local/codex-sandbox-networked:stale PROJECT_OPENCODE_IMAGE=local/codex-sandbox-opencode:stale
if check_image_label "$PROJECT_NETWORK_IMAGE" io.codex-sandbox.kit.version 3.3.0 stale-test 2>"$work/image"; then exit 1; fi
for expected in 'Image: local/codex-sandbox-networked:stale' 'Label: io.codex-sandbox.kit.version' 'Expected: 3.3.0' 'Actual: stale-test' 'sbx upgrade stale-probe' 'Safe remediation: sbx build'; do grep -q "$expected" "$work/image"; done
printf 'PASS: stale image diagnostics identify image/label/values and exact recovery\n'

# Use the public launcher with an unavailable engine and with a reachable
# engine that genuinely lacks the image. Neither path may create a container.
mkdir -p "$work/bin"
cat > "$work/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$DOCKER_LOG"
case "$1" in
  info)
    if [[ "${DAEMON_DOWN:-0}" == 1 ]]; then
      printf 'dial unix /var/run/docker.sock: no such file or directory\n' >&2
      exit 1
    fi
    ;;
  image) exit 1 ;;
  *) printf 'FAIL: unexpected Docker operation\n' >&2; exit 99 ;;
esac
DOCKER
chmod +x "$work/bin/docker"
export CODEX_SANDBOX_WORKSPACES_ROOT="$work/ws" DOCKER_LOG="$work/docker.log"
export SBX_DISABLE_UPDATE_CHECK=1 PATH="$work/bin:/usr/bin:/bin"
"$root/bin/sbx" init daemon-probe >/dev/null
mkdir -p "$work/ws/daemon-probe/repo/.git"
for agent in codex opencode claude; do
  : > "$DOCKER_LOG"
  if DAEMON_DOWN=1 "$root/bin/sbx" "$agent" run daemon-probe >"$work/out" 2>"$work/err"; then exit 1; fi
  grep -q 'Docker daemon is unavailable or inaccessible' "$work/err"
  grep -q 'Start Docker Desktop and enable WSL integration' "$work/err"
  grep -q '/var/run/docker.sock' "$work/err"
  ! grep -q 'image is missing\|sbx build' "$work/err"
  ! grep -Eq '^(create|volume|build|start) ' "$DOCKER_LOG"
  if "$root/bin/sbx" "$agent" run daemon-probe >"$work/out" 2>"$work/err"; then exit 1; fi
  grep -q 'image is missing' "$work/err"
  grep -q 'Safe remediation: sbx build' "$work/err"
  ! grep -q 'Docker daemon is unavailable' "$work/err"
done
printf 'PASS: all harnesses distinguish an unavailable Docker daemon from a missing image before container creation\n'
