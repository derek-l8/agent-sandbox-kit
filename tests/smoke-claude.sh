#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ctl="$root/bin/sandboxctl"
slug="claude-smoke-$(date -u +%Y%m%d-%H%M%S)-$$"
ws="$(mktemp -d)"
case "$ws" in /tmp/*) ;; *) printf 'ERROR: unsafe temporary workspace: %s\n' "$ws" >&2; exit 1 ;; esac
export CODEX_SANDBOX_WORKSPACES_ROOT="$ws"
project_root="$ws/$slug"
volume="codex-sbx-${slug}-claude-auth-v2"
cleanup() {
  local id
  while IFS= read -r id; do
    [[ -n "$id" ]] && docker rm -f "$id" >/dev/null 2>&1 || true
  done < <(docker ps -aq --filter "label=io.codex-sandbox.project=$slug" 2>/dev/null || true)
  docker volume rm "$volume" >/dev/null 2>&1 || true
  case "$project_root" in "$ws"/claude-smoke-*) rm -rf -- "$project_root" ;; esac
  rmdir "$ws" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

command -v docker >/dev/null 2>&1 || { echo 'ERROR: docker CLI is missing' >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo 'ERROR: Docker daemon is unavailable' >&2; exit 1; }
"$ctl" init "$slug" >/dev/null
mkdir -p "$project_root/repo/.git"

printf 'reference\n' > "$project_root/context/reference.txt"
"$ctl" claude doctor "$slug"
"$ctl" claude exec "$slug" -- bash -lc '
set -euo pipefail
test -r /context/reference.txt
if touch /context/forbidden 2>/dev/null; then exit 1; fi
if touch /workspace/.git/forbidden 2>/dev/null; then exit 1; fi
if touch /auth/forbidden 2>/dev/null; then exit 1; fi
claude --version
claude auth login --help >/tmp/login-help.txt
mkdir -p /workspace/.claude
printf "{\"hooks\":{\"SessionStart\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"touch /data/hook-ran\"}]}]}}" > /workspace/.claude/settings.json
printf "{\"mcpServers\":{\"hostile\":{\"command\":\"touch\",\"args\":[\"/data/mcp-ran\"]}}}" > /workspace/.mcp.json
claude --setting-sources "" --strict-mcp-config mcp list > /data/mcp-check.txt 2>&1
test ! -e /data/mcp-ran
rc=0
claude --setting-sources "" --strict-mcp-config --disable-slash-commands --append-system-prompt-file /etc/agent-workspace.md --dangerously-skip-permissions -p "Do not call tools." >/data/unauthenticated.txt 2>&1 || rc=$?
test "$rc" -ne 0
grep -q "Not logged in" /data/unauthenticated.txt
test ! -e /data/hook-ran
rc=0
claude --plugin-dir /tmp -p "Do not call tools." >/data/policy.txt 2>&1 || rc=$?
test "$rc" -ne 0
grep -q disableSideloadFlags /data/policy.txt
printf "persistent\n" > /data/state.txt
'
"$ctl" claude exec "$slug" -- bash -lc \
  'set -euo pipefail; test "$(cat /data/state.txt)" = persistent; test "$(cat /context/reference.txt)" = reference; test ! -e "$CLAUDE_CONFIG_DIR/.credentials.json"'
rc=0
"$ctl" claude auth-status "$slug" > "$project_root/data/status.txt" 2>&1 || rc=$?
test "$rc" -eq 1
grep -q '"loggedIn": false' "$project_root/data/status.txt"
# Synthetic credentials exercise file recognition and RO task-copy semantics.
# They are placeholders, never used for a model request or a real login.
source "$root/versions.lock"
docker run --rm --network none --read-only --cap-drop ALL \
  --security-opt no-new-privileges:true --user node \
  --mount "type=volume,source=$volume,target=/auth" \
  --entrypoint bash "$CLAUDE_IMAGE" -c '
  umask 077
  printf "%s\n" "{\"claudeAiOauth\":{\"accessToken\":\"synthetic-not-a-secret\",\"refreshToken\":\"synthetic-not-a-secret\",\"expiresAt\":4102444800000,\"scopes\":[\"user:inference\",\"user:profile\"],\"subscriptionType\":\"pro\"}}" > /auth/.credentials.json
  '
"$ctl" claude exec "$slug" -- bash -lc '
  set -euo pipefail
  claude auth status > /data/synthetic-status.txt
  grep -q "\"loggedIn\": true" /data/synthetic-status.txt
  printf "{}\n" > "$CLAUDE_CONFIG_DIR/.credentials.json"
  '
"$ctl" claude exec "$slug" -- bash -lc '
  set -euo pipefail
  claude auth status > /data/synthetic-status.txt
  grep -q "\"loggedIn\": true" /data/synthetic-status.txt
  '
"$ctl" claude logout "$slug"
rc=0
"$ctl" claude auth-status "$slug" > "$project_root/data/status.txt" 2>&1 || rc=$?
test "$rc" -eq 1
grep -q '"loggedIn": false' "$project_root/data/status.txt"
"$ctl" claude reset-auth "$slug" --yes
if docker volume inspect "$volume" >/dev/null 2>&1; then exit 1; fi
printf 'RESULT: Claude Docker smoke tests passed without credentials or a successful model invocation\n'
