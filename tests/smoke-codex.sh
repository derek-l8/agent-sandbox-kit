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

printf 'synthetic-private-fixture\n' > "$project_root/inbox/smoke-private.txt"

"$ctl" doctor "$slug"

"$ctl" exec "$slug" -- bash -lc \
  'set -euo pipefail; test "$(codex --version | awk '\''{print $2}'\'')" = "0.148.0"; test ! -e "$CODEX_HOME/config.toml"; codex --strict-config --disable apps --disable remote_plugin --help >/tmp/codex-help.txt; codex features list >/tmp/features.txt; printf "networked-smoke-ok\n" > /agent/scratch/networked-smoke.txt'

"$ctl" offline "$slug" -- bash -lc \
  'set -euo pipefail; test -d /workspace/.git; test -f /agent/inbox/smoke-private.txt; ! command -v codex >/dev/null 2>&1; printf "offline-smoke-ok\n" > /agent/outbox/offline-smoke.txt'

test "$(cat "$project_root/scratch/networked-smoke.txt")" = 'networked-smoke-ok'
test "$(cat "$project_root/outbox/offline-smoke.txt")" = 'offline-smoke-ok'

printf 'RESULT: Codex Docker smoke tests passed without authentication or a model invocation\n'
