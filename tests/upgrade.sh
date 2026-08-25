#!/usr/bin/env bash

set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM
export CODEX_SANDBOX_WORKSPACES_ROOT="$work/workspaces"
ctl="$root/bin/sandboxctl"

make_project() {
  local slug="$1" version="$2"
  "$ctl" init "$slug" >/dev/null
  mkdir -p "$CODEX_SANDBOX_WORKSPACES_ROOT/$slug/repo/.git"
  sed -i \
    -e "s/:2.0.2/:$version/g" \
    -e 's/PROJECT_CPUS=6/PROJECT_CPUS=3/' \
    -e 's/PROJECT_MEMORY=8g/PROJECT_MEMORY=4096m/' \
    "$CODEX_SANDBOX_WORKSPACES_ROOT/$slug/control/project.env"
  printf 'policy.txt\n' > "$CODEX_SANDBOX_WORKSPACES_ROOT/$slug/control/protected-paths.txt"
  printf 'preserve\n' > "$CODEX_SANDBOX_WORKSPACES_ROOT/$slug/repo/policy.txt"
  printf 'data\n' > "$CODEX_SANDBOX_WORKSPACES_ROOT/$slug/scratch/data"
}

for version in 2.0.0 2.0.1; do
  slug="upgrade-${version//./-}"
  make_project "$slug" "$version"
  config="$CODEX_SANDBOX_WORKSPACES_ROOT/$slug/control/project.env"
  before="$(sha256sum "$config")"
  "$ctl" upgrade --dry-run "$slug" | grep -q 'Dry run: no files changed.'
  [[ "$before" == "$(sha256sum "$config")" ]]
  "$ctl" upgrade "$slug" >/dev/null
  grep -q ':2.0.2$' "$config"
  grep -q '^PROJECT_CPUS=3$' "$config"
  grep -q '^PROJECT_MEMORY=4096m$' "$config"
  grep -q '^PROJECT_SLUG='"$slug"'$' "$config"
  grep -qx policy.txt "$CODEX_SANDBOX_WORKSPACES_ROOT/$slug/control/protected-paths.txt"
  grep -qx data "$CODEX_SANDBOX_WORKSPACES_ROOT/$slug/scratch/data"
  compgen -G "$config.pre-upgrade-*.bak" >/dev/null
  backup_count="$(find "$(dirname "$config")" -maxdepth 1 -name 'project.env.pre-upgrade-*.bak' | wc -l)"
  "$ctl" upgrade "$slug" | grep -q 'already current'
  [[ "$backup_count" -eq "$(find "$(dirname "$config")" -maxdepth 1 -name 'project.env.pre-upgrade-*.bak' | wc -l)" ]]
done
printf 'PASS: 2.0.0/2.0.1 upgrades preserve settings/data, back up atomically, dry-run, and are idempotent\n'

make_project unknown-key 2.0.1
printf 'SURPRISE=yes\n' >> "$CODEX_SANDBOX_WORKSPACES_ROOT/unknown-key/control/project.env"
if "$ctl" upgrade unknown-key >"$work/out" 2>"$work/err"; then exit 1; fi
grep -q 'unknown key' "$work/err"
printf 'PASS: upgrade rejects unknown project keys\n'

make_project active-lock 2.0.1
mkdir "$CODEX_SANDBOX_WORKSPACES_ROOT/active-lock/control/.session-lock"
printf 'agent=codex\npid=%s\n' "$$" > "$CODEX_SANDBOX_WORKSPACES_ROOT/active-lock/control/.session-lock/owner.txt"
if "$ctl" upgrade active-lock >"$work/out" 2>"$work/err"; then exit 1; fi
grep -q 'while a Codex or OpenCode task session is active' "$work/err"
grep -q ':2.0.1$' "$CODEX_SANDBOX_WORKSPACES_ROOT/active-lock/control/project.env"
printf 'PASS: upgrade refuses an active cross-agent session lock\n'

# Exercise the real rollback branch by overriding only its validation helper.
sed '$d' "$ctl" > "$work/library.sh"
make_project rollback-probe 2.0.1
config="$CODEX_SANDBOX_WORKSPACES_ROOT/rollback-probe/control/project.env"
before="$(sha256sum "$config")"
if bash -c 'source "$1"; read_versions; validate_upgraded_project(){ return 1; }; cmd_upgrade rollback-probe' _ "$work/library.sh" \
    >"$work/out" 2>"$work/err"; then exit 1; fi
[[ "$before" == "$(sha256sum "$config")" ]]
printf 'PASS: failed replacement validation restores the original configuration\n'
