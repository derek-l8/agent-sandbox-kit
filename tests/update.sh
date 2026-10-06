#!/usr/bin/env bash

set -euo pipefail

if [[ "${SBX_UPDATE_TEST_NESTED:-0}" == 1 ]]; then
  printf 'PASS: nested update suite skipped during the full update-path probe\n'
  exit 0
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

source_checkout="$work/source"
remote="$work/remote.git"
publisher="$work/publisher"
mkdir -p "$source_checkout"
tar --exclude=.git -C "$root" -cf - . | tar -C "$source_checkout" -xf -

git init -q -b main "$source_checkout"
git -C "$source_checkout" config user.name test
git -C "$source_checkout" config user.email test@example.invalid
git -C "$source_checkout" add .
git -C "$source_checkout" commit -qm baseline
git init -q --bare -b main "$remote"
git -C "$source_checkout" remote add origin "$remote"
git -C "$source_checkout" push -qu origin main

home="$work/home"
xdg_bin="$work/xdg/bin"
xdg_data="$work/xdg/data"
xdg_cache="$work/xdg/cache"
mkdir -p "$home"
HOME="$home" XDG_BIN_HOME="$xdg_bin" XDG_DATA_HOME="$xdg_data" \
  PATH=/usr/bin:/bin bash "$source_checkout/install.sh" >/dev/null
ctl="$xdg_data/agent-sandbox-kit/bin/sandboxctl"
runtime_source="$xdg_data/agent-sandbox-kit/source-path"
[[ "$(cat "$runtime_source")" == "$source_checkout" ]]

common_env=(HOME="$home" XDG_BIN_HOME="$xdg_bin" XDG_DATA_HOME="$xdg_data" XDG_CACHE_HOME="$xdg_cache" SBX_DISABLE_HARNESS_UPDATE_CHECK=1 PATH=/usr/bin:/bin)
for args in '--check --yes' '--check probe'; do
  read -ra invalid_args <<< "$args"
  if env "${common_env[@]}" "$ctl" update "${invalid_args[@]}" >"$work/invalid.out" 2>"$work/invalid.err"; then
    printf 'FAIL: incompatible update arguments succeeded: %s\n' "$args" >&2
    exit 1
  fi
  grep -q 'usage: sbx update --check' "$work/invalid.err"
done
printf 'PASS: update check rejects install-only arguments\n'

output="$(env "${common_env[@]}" "$ctl" update --check)"
[[ "$output" == *'Update available: no'* ]]
printf 'PASS: update check reports a synchronized tracked source\n'

workspaces="$work/workspaces"
project_env=(CODEX_SANDBOX_WORKSPACES_ROOT="$workspaces")
env "${common_env[@]}" "${project_env[@]}" "$ctl" init stale-project >/dev/null
mkdir -p "$workspaces/stale-project/repo/.git"
config="$workspaces/stale-project/control/project.env"
sed -i 's/:3.3.0/:stale/g' "$config"
cp "$config" "$work/project-before"
env "${common_env[@]}" "${project_env[@]}" "$ctl" update --yes stale-project >"$work/current-project.out"
grep -q 'Agent Sandbox Kit is already current.' "$work/current-project.out"
grep -q '^PROJECT_NETWORK_IMAGE=.*:3.3.0$' "$config"
backup="$(find "$(dirname "$config")" -name 'project.env.pre-upgrade-*.bak' -print -quit)"
cmp "$backup" "$work/project-before"
env "${common_env[@]}" "${project_env[@]}" "$ctl" update --yes stale-project >/dev/null
[[ "$(find "$(dirname "$config")" -name 'project.env.pre-upgrade-*.bak' | wc -l)" -eq 1 ]]
mkdir "$workspaces/stale-project/control/.session-lock"
printf 'pid=%s\n' "$$" > "$workspaces/stale-project/control/.session-lock/owner.txt"
if env "${common_env[@]}" "${project_env[@]}" "$ctl" update --yes stale-project >"$work/active.out" 2>"$work/active.err"; then exit 1; fi
grep -q 'while an agent task session is active' "$work/active.err"
rm -rf "$workspaces/stale-project/control/.session-lock"
printf 'PASS: an already-current kit upgrades a stale project with backup, idempotence, and active-session protection\n'

git clone -q "$remote" "$publisher"
git -C "$publisher" config user.name test
git -C "$publisher" config user.email test@example.invalid
printf '\nremote update\n' >> "$publisher/README.md"
git -C "$publisher" add README.md
git -C "$publisher" commit -qm update
git -C "$publisher" push -q origin main

output="$(env "${common_env[@]}" "$ctl" update --check)"
[[ "$output" == *'Update available: yes'* ]]
printf 'PASS: explicit check detects a remote fast-forward without changing the source\n'

rm -f "$xdg_cache/agent-sandbox-kit/update-check"
env "${common_env[@]}" "$ctl" update --auto-check >"$work/auto.out" 2>"$work/auto.err"
grep -q '^UPDATE AVAILABLE:' "$work/auto.err"
env "${common_env[@]}" "$ctl" update --auto-check >"$work/repeat.out" 2>"$work/repeat.err"
[[ ! -s "$work/repeat.out" && ! -s "$work/repeat.err" ]]
printf 'PASS: automatic checks notify once and use the 24-hour cache\n'

rm -f "$xdg_cache/agent-sandbox-kit/update-check"
env "${common_env[@]}" SBX_DISABLE_UPDATE_CHECK=1 "$ctl" update --auto-check >"$work/disabled.out" 2>"$work/disabled.err"
[[ ! -e "$xdg_cache/agent-sandbox-kit/update-check" ]]
[[ ! -s "$work/disabled.out" && ! -s "$work/disabled.err" ]]
printf 'PASS: automatic update checks support an explicit opt-out\n'

git -C "$source_checkout" remote set-url origin "$work/unavailable-remote.git"
env "${common_env[@]}" "$ctl" update --auto-check >"$work/unavailable.out" 2>"$work/unavailable.err"
[[ -f "$xdg_cache/agent-sandbox-kit/update-check" ]]
[[ ! -s "$work/unavailable.out" && ! -s "$work/unavailable.err" ]]
git -C "$source_checkout" remote set-url origin "$remote"
printf 'PASS: failed automatic remote checks stay silent and are cached\n'

fake_bin="$work/fake-bin"
docker_log="$work/docker.log"
mkdir -p "$fake_bin"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "$DOCKER_LOG"' > "$fake_bin/docker"
chmod +x "$fake_bin/docker"
: > "$docker_log"
env "${common_env[@]}" PATH="$fake_bin:/usr/bin:/bin" DOCKER_LOG="$docker_log" \
  SBX_UPDATE_TEST_NESTED=1 "$ctl" update --yes >"$work/update.out"
[[ "$(git -C "$source_checkout" rev-parse HEAD)" == "$(git -C "$publisher" rev-parse HEAD)" ]]
[[ ! -s "$docker_log" ]]
grep -q 'Remote URL:' "$work/update.out"
grep -q 'Current commit:' "$work/update.out"
grep -q 'Target commit:' "$work/update.out"
grep -q 'Change summary:' "$work/update.out"
grep -q 'Review command:' "$work/update.out"
grep -q "runs the fetched checkout's tests and installer" "$work/update.out"
grep -q 'Image inputs unchanged; skipping image rebuild.' "$work/update.out"
grep -q 'Next: sbx upgrade <project>' "$work/update.out"
printf 'PASS: confirmed host-only update fast-forwards, validates, installs, and skips image builds\n'

printf '\nimage update\n' >> "$publisher/config/agent-workspace.md"
git -C "$publisher" add config/agent-workspace.md
git -C "$publisher" commit -qm image-update
git -C "$publisher" push -q origin main
: > "$docker_log"
env "${common_env[@]}" PATH="$fake_bin:/usr/bin:/bin" DOCKER_LOG="$docker_log" \
  SBX_UPDATE_TEST_NESTED=1 "$ctl" update --yes >"$work/image-update.out"
[[ "$(git -C "$source_checkout" rev-parse HEAD)" == "$(git -C "$publisher" rev-parse HEAD)" ]]
[[ "$(grep -c '^build ' "$docker_log")" == 3 ]]
printf 'PASS: confirmed image-input update rebuilds all pinned images\n'

printf '\nmanual source update\n' >> "$publisher/README.md"
git -C "$publisher" add README.md
git -C "$publisher" commit -qm manual-source-update
git -C "$publisher" push -q origin main
git -C "$source_checkout" fetch -q origin
git -C "$source_checkout" merge -q --ff-only origin/main
# Detect a manually advanced source even without a KIT_VERSION bump.
output="$(env "${common_env[@]}" "$ctl" update --check)"
[[ "$output" == *'Update available: no'* ]] # README-only changes do not affect the runtime
printf '\n# manually advanced image input\n' >> "$publisher/config/agent-workspace.md"
git -C "$publisher" add config/agent-workspace.md
git -C "$publisher" commit -qm manual-image-change
git -C "$publisher" push -q origin main
git -C "$source_checkout" fetch -q origin
git -C "$source_checkout" merge -q --ff-only origin/main
output="$(env "${common_env[@]}" "$ctl" update --check)"
[[ "$output" == *'Update available: yes'* ]]
: > "$docker_log"
env "${common_env[@]}" PATH="$fake_bin:/usr/bin:/bin" DOCKER_LOG="$docker_log" \
  SBX_UPDATE_TEST_NESTED=1 "$ctl" update --yes >"$work/manual-image-update.out"
[[ "$(grep -c '^build ' "$docker_log")" == 3 ]]
printf 'PASS: manually advanced same-version image inputs reinstall and rebuild from the installed snapshot\n'
sed -i 's/^KIT_VERSION=.*/KIT_VERSION=stale-test/' "$xdg_data/agent-sandbox-kit/versions.lock"
: > "$docker_log"
env "${common_env[@]}" PATH="$fake_bin:/usr/bin:/bin" DOCKER_LOG="$docker_log" \
  SBX_UPDATE_TEST_NESTED=1 "$ctl" update --yes >"$work/manual-update.out"
[[ "$(grep -c '^build ' "$docker_log")" == 3 ]]
grep -q 'Current commit:' "$work/manual-update.out"
grep -q 'Target commit:' "$work/manual-update.out"
printf 'PASS: source advanced outside sbx still rebuilds images when the installed kit version differs\n'

printf '\nthird remote update\n' >> "$publisher/README.md"
git -C "$publisher" add README.md
git -C "$publisher" commit -qm third-update
git -C "$publisher" push -q origin main
printf 'dirty\n' > "$source_checkout/local-change"
if env "${common_env[@]}" "$ctl" update --yes >"$work/dirty.out" 2>"$work/dirty.err"; then
  echo 'FAIL: update accepted a dirty source checkout' >&2
  exit 1
fi
grep -q 'source checkout has local changes' "$work/dirty.err"
[[ "$(git -C "$source_checkout" rev-parse HEAD)" != "$(git -C "$publisher" rev-parse HEAD)" ]]
printf 'PASS: explicit update refuses a dirty source before fast-forwarding\n'

mv "$source_checkout" "$work/source-unavailable"
if env "${common_env[@]}" "$ctl" update --check >"$work/missing.out" 2>"$work/missing.err"; then
  echo 'FAIL: explicit check accepted an unavailable recorded source' >&2
  exit 1
fi
grep -q 'no available Git source checkout' "$work/missing.err"
printf 'PASS: explicit update fails clearly when the recorded source is unavailable\n'
