#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ctl="$root/bin/sandboxctl"
slug="${1:-sandbox-v2-test}"
project_root="${CODEX_SANDBOX_WORKSPACES_ROOT:-$HOME/agent-workspaces}/$slug"

if [[ ! -d "$project_root" ]]; then
  "$ctl" init "$slug"
fi

if [[ ! -d "$project_root/repo/.git" ]]; then
  git -C "$project_root/repo" init
  git -C "$project_root/repo" branch -M main
  git -C "$project_root/repo" -c user.name='Sandbox v2 Test' \
    -c user.email='sandbox-v2-test@local.invalid' commit --allow-empty -m 'Create sandbox v2 smoke-test baseline'
fi

printf 'synthetic-private-fixture\n' > "$project_root/inbox/smoke-private.txt"

"$ctl" doctor "$slug"

"$ctl" exec "$slug" -- bash -lc \
  'set -euo pipefail; test "$(codex --version | awk '\''{print $2}'\'')" = "0.148.0"; test ! -e "$CODEX_HOME/config.toml"; codex --strict-config --disable apps --disable remote_plugin --help >/tmp/codex-help.txt; codex features list >/tmp/features.txt; printf "networked-smoke-ok\n" > /agent/scratch/networked-smoke.txt'

"$ctl" offline "$slug" -- bash -lc \
  'set -euo pipefail; test -d /workspace/.git; test -f /agent/inbox/smoke-private.txt; ! command -v codex >/dev/null 2>&1; printf "offline-smoke-ok\n" > /agent/outbox/offline-smoke.txt'

test "$(cat "$project_root/scratch/networked-smoke.txt")" = 'networked-smoke-ok'
test "$(cat "$project_root/outbox/offline-smoke.txt")" = 'offline-smoke-ok'

printf 'RESULT: Docker smoke tests passed without a model invocation\n'
