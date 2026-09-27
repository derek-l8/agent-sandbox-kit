#!/usr/bin/env bash

set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM
export CODEX_SANDBOX_WORKSPACES_ROOT="$work/workspaces"
ctl="$root/bin/sandboxctl"

make_project() {
  local slug="$1"
  "$ctl" init "$slug" >/dev/null
  mkdir -p "$CODEX_SANDBOX_WORKSPACES_ROOT/$slug/repo/.git"
  sed -i \
    -e 's/:3.3.0/:stale/g' \
    -e 's/PROJECT_CPUS=6/PROJECT_CPUS=3/' \
    -e 's/PROJECT_MEMORY=8g/PROJECT_MEMORY=4096m/' \
    "$CODEX_SANDBOX_WORKSPACES_ROOT/$slug/control/project.env"
  printf 'policy.txt\n' > "$CODEX_SANDBOX_WORKSPACES_ROOT/$slug/control/protected-paths.txt"
  printf 'preserve\n' > "$CODEX_SANDBOX_WORKSPACES_ROOT/$slug/repo/policy.txt"
  printf 'data\n' > "$CODEX_SANDBOX_WORKSPACES_ROOT/$slug/data/data"
}

slug=upgrade-probe
make_project "$slug"
config="$CODEX_SANDBOX_WORKSPACES_ROOT/$slug/control/project.env"
before="$(sha256sum "$config")"
"$ctl" upgrade --dry-run "$slug" | grep -q 'Dry run: no files changed.'
[[ "$before" == "$(sha256sum "$config")" ]]
"$ctl" upgrade "$slug" >/dev/null
for image_key in PROJECT_NETWORK_IMAGE PROJECT_OPENCODE_IMAGE PROJECT_CLAUDE_IMAGE; do
  grep -q "^$image_key=.*:3.3.0$" "$config"
done
grep -q '^PROJECT_CPUS=3$' "$config"
grep -q '^PROJECT_MEMORY=4096m$' "$config"
grep -q '^PROJECT_SLUG=upgrade-probe$' "$config"
grep -qx policy.txt "$CODEX_SANDBOX_WORKSPACES_ROOT/$slug/control/protected-paths.txt"
grep -qx data "$CODEX_SANDBOX_WORKSPACES_ROOT/$slug/data/data"
compgen -G "$config.pre-upgrade-*.bak" >/dev/null
backup_count="$(find "$(dirname "$config")" -maxdepth 1 -name 'project.env.pre-upgrade-*.bak' | wc -l)"
"$ctl" upgrade "$slug" | grep -q 'already current'
[[ "$backup_count" -eq "$(find "$(dirname "$config")" -maxdepth 1 -name 'project.env.pre-upgrade-*.bak' | wc -l)" ]]
printf 'PASS: current project image pins update without changing settings/data, with backup and idempotence\n'

make_project unknown-key
printf 'SURPRISE=yes\n' >> "$CODEX_SANDBOX_WORKSPACES_ROOT/unknown-key/control/project.env"
if "$ctl" upgrade unknown-key >"$work/out" 2>"$work/err"; then exit 1; fi
grep -q 'unknown key' "$work/err"
printf 'PASS: upgrade rejects unknown project keys\n'

make_project active-lock
mkdir "$CODEX_SANDBOX_WORKSPACES_ROOT/active-lock/control/.session-lock"
printf 'agent=codex\npid=%s\n' "$$" > "$CODEX_SANDBOX_WORKSPACES_ROOT/active-lock/control/.session-lock/owner.txt"
if "$ctl" upgrade active-lock >"$work/out" 2>"$work/err"; then exit 1; fi
grep -q 'while an agent task session is active' "$work/err"
grep -q ':stale$' "$CODEX_SANDBOX_WORKSPACES_ROOT/active-lock/control/project.env"
printf 'PASS: upgrade refuses an active cross-agent session lock\n'

# Exercise the real rollback branch by overriding only its validation helper.
sed '$d' "$ctl" > "$work/library.sh"
make_project rollback-probe
config="$CODEX_SANDBOX_WORKSPACES_ROOT/rollback-probe/control/project.env"
before="$(sha256sum "$config")"
if bash -c 'source "$1"; read_versions; validate_upgraded_project(){ return 1; }; cmd_upgrade rollback-probe' _ "$work/library.sh" \
    >"$work/out" 2>"$work/err"; then exit 1; fi
[[ "$before" == "$(sha256sum "$config")" ]]
printf 'PASS: failed replacement validation restores the original configuration\n'
