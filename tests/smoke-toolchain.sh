#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ctl="$root/bin/sandboxctl"
slug="toolchain-smoke-$(date -u +%Y%m%d-%H%M%S)-$$"
ws="$(mktemp -d)"
case "$ws" in /tmp/*) ;; *) echo 'unsafe test root' >&2; exit 1 ;; esac
export CODEX_SANDBOX_WORKSPACES_ROOT="$ws"
cleanup() {
  local id volume
  while IFS= read -r id; do
    [[ -z "$id" ]] || docker rm -f "$id" >/dev/null 2>&1 || true
  done < <(docker ps -aq --filter "label=io.codex-sandbox.project=$slug")
  for volume in "codex-sbx-$slug-auth-v2" "codex-sbx-$slug-opencode-auth-v2" "codex-sbx-$slug-claude-auth-v2"; do
    docker volume rm "$volume" >/dev/null 2>&1 || true
  done
  case "$ws" in /tmp/*) rm -rf -- "$ws" ;; esac
}
trap cleanup EXIT INT TERM
"$ctl" init "$slug" >/dev/null
mkdir -p "$ws/$slug/repo/.git"
cp "$root/tests/toolchain-probe.sh" "$ws/$slug/repo/probe.sh"
for agent in codex opencode claude; do
  echo "Testing shared tools: $agent"
  "$ctl" "$agent" exec "$slug" -- bash /workspace/probe.sh
  "$ctl" "$agent" exec "$slug" -- bash -c '
    set -euo pipefail
    /data/venv/bin/python -c "import probe_pkg; assert probe_pkg.VALUE == 42"
    test -s /data/toolchain/page.png
    test ! -e /home/node/.cache/uv/CACHED_SENTINEL
    '
  # Remove only this disposable test's generated environments before next agent.
  "$ctl" "$agent" exec "$slug" -- bash -c 'set -e; test -d /data/toolchain; rm -rf /data/toolchain /data/venv /data/legacy-venv /data/project-venv'
done
echo 'RESULT: shared toolchain smoke passed for all agents'
