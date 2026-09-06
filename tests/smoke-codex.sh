#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ctl="$root/bin/sandboxctl"
slug="codex-smoke-$(date -u +%Y%m%d-%H%M%S)-$$"
ws="$(mktemp -d)"
case "$ws" in /tmp/*) ;; *) printf 'ERROR: unsafe temporary workspace: %s\n' "$ws" >&2; exit 1 ;; esac
export CODEX_SANDBOX_WORKSPACES_ROOT="$ws"
project_root="$ws/$slug"
volume="codex-sbx-${slug}-auth-v2"
cleanup() {
  local id
  while IFS= read -r id; do
    [[ -n "$id" ]] && docker rm -f "$id" >/dev/null 2>&1 || true
  done < <(docker ps -aq --filter "label=io.codex-sandbox.project=$slug" 2>/dev/null || true)
  docker volume rm "$volume" >/dev/null 2>&1 || true
  case "$project_root" in "$ws"/codex-smoke-*) rm -rf -- "$project_root" ;; esac
  rmdir "$ws" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

command -v docker >/dev/null 2>&1 || { echo 'ERROR: docker CLI is missing' >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo 'ERROR: Docker daemon is unavailable' >&2; exit 1; }
"$ctl" init "$slug" >/dev/null
mkdir -p "$project_root/repo/.git"

printf 'reference\n' > "$project_root/context/reference.txt"
"$ctl" codex doctor "$slug"
"$ctl" codex exec "$slug" -- bash -lc \
  'set -euo pipefail; test -r /context/reference.txt; if touch /context/forbidden 2>/dev/null; then exit 1; fi; test ! -e "$CODEX_HOME/config.toml"; codex --strict-config --disable apps --disable remote_plugin --help >/tmp/codex-help.txt; codex features list >/tmp/features.txt; printf "persistent\n" > /data/state.txt'
"$ctl" codex exec "$slug" -- bash -lc \
  'set -euo pipefail; test "$(cat /data/state.txt)" = persistent; test "$(cat /context/reference.txt)" = reference'
test "$(cat "$project_root/data/state.txt")" = persistent
printf 'RESULT: Codex Docker smoke tests passed without authentication or a model invocation\n'
