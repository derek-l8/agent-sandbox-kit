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
env "${common_env[@]}" "$ctl" update --auto-check stale-project >"$work/auto.out" 2>"$work/auto.err"
grep -q '^UPDATE AVAILABLE:' "$work/auto.err"
grep -q '^Run: sbx update stale-project$' "$work/auto.err"
grep -q '^Optional preview: sbx update --check$' "$work/auto.err"
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
cat > "$fake_bin/docker" <<'DOCKER'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DOCKER_LOG"
if [[ "$1" == build && "${BUILD_FAIL:-0}" == 1 ]]; then
  printf 'fixture image build failed\n' >&2
  exit 23
fi
if [[ "$1" == info && "${DAEMON_DOWN:-0}" == 1 ]]; then
  printf 'fixture Docker daemon unavailable\n' >&2
  exit 1
fi
if [[ "$1" == build && -n "${PROJECT_LOCK_ON_BUILD:-}" && ! -d "$PROJECT_LOCK_ON_BUILD" ]]; then
  mkdir "$PROJECT_LOCK_ON_BUILD"
  printf 'pid=%s\n' "$OWNER_PID" > "$PROJECT_LOCK_ON_BUILD/owner.txt"
fi
DOCKER
chmod +x "$fake_bin/docker"
common_env+=(PATH="$fake_bin:/usr/bin:/bin" DOCKER_LOG="$docker_log")
pending_build="$xdg_data/.agent-sandbox-kit.image-build-pending"
ln -s "$xdg_data" "$work/data-alias"
: > "$docker_log"
env "${common_env[@]}" PATH="$fake_bin:/usr/bin:/bin" DOCKER_LOG="$docker_log" \
  SBX_UPDATE_TEST_NESTED=1 "$ctl" update --yes >"$work/update.out" 2>"$work/update.err"
[[ "$(git -C "$source_checkout" rev-parse HEAD)" == "$(git -C "$publisher" rev-parse HEAD)" ]]
[[ ! -s "$docker_log" ]]
grep -q 'Remote URL:' "$work/update.out"
grep -q 'Current commit:' "$work/update.out"
grep -q 'Target commit:' "$work/update.out"
grep -q 'Change summary:' "$work/update.out"
grep -q 'Review command:' "$work/update.out"
grep -q "runs the fetched checkout's tests and installer" "$work/update.out"
grep -q 'Image inputs unchanged; skipping image rebuild.' "$work/update.out"
grep -q 'Apply the selected images to an existing project: sbx upgrade my-project' "$work/update.out"
if grep -Eq 'Paste Copy as path|Replace imported copy' "$work/update.out" "$work/update.err"; then
  printf 'FAIL: automated update checks displayed fixture input prompts\n' >&2
  exit 1
fi
printf 'PASS: confirmed host-only update fast-forwards, validates, installs, and skips image builds\n'

printf '\nimage update\n' >> "$publisher/config/agent-workspace.md"
git -C "$publisher" add config/agent-workspace.md
git -C "$publisher" commit -qm image-update
git -C "$publisher" push -q origin main
# A stopped daemon must fail before touching source, installed files, or the
# project. Host-only updates above still require no Docker calls.
source_before="$(git -C "$source_checkout" rev-parse HEAD)"
cp "$xdg_data/agent-sandbox-kit/config/agent-workspace.md" "$work/preflight-runtime-before"
cp "$config" "$work/preflight-project-before"
if env "${common_env[@]}" "${project_env[@]}" DAEMON_DOWN=1 "$ctl" update --yes stale-project \
  >"$work/preflight.out" 2>"$work/preflight.err"; then exit 1; fi
grep -q 'Docker daemon is unavailable' "$work/preflight.err"
[[ "$source_before" == "$(git -C "$source_checkout" rev-parse HEAD)" ]]
cmp "$xdg_data/agent-sandbox-kit/config/agent-workspace.md" "$work/preflight-runtime-before"
cmp "$config" "$work/preflight-project-before"
[[ ! -e "$pending_build" ]]
printf 'PASS: unavailable Docker is rejected before advancing source or installing runtime\n'
: > "$docker_log"
env "${common_env[@]}" PATH="$fake_bin:/usr/bin:/bin" DOCKER_LOG="$docker_log" \
  XDG_DATA_HOME="$work/data-alias" SBX_UPDATE_TEST_NESTED=1 "$ctl" update --yes >"$work/image-update.out"
[[ "$(git -C "$source_checkout" rev-parse HEAD)" == "$(git -C "$publisher" rev-parse HEAD)" ]]
[[ "$(grep -c '^build ' "$docker_log")" == 3 ]]
printf 'PASS: confirmed image-input update rebuilds all pinned images\n'
[[ ! -e "$pending_build" ]]
printf 'PASS: symlinked data directories share the updater and installer lock and clear completed build state\n'

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

# A fetched check must receive EOF rather than waiting for or consuming input
# meant for the user's terminal. --yes bypasses the real update confirmation.
cat > "$publisher/tests/static.sh" <<'CHECK'
#!/usr/bin/env bash
set -euo pipefail
if read -r unexpected; then
  printf 'FAIL: automated checks received user input\n' >&2
  exit 1
fi
printf 'PASS: automated checks have no terminal input\n'
CHECK
git -C "$publisher" add tests/static.sh
git -C "$publisher" commit -qm noninteractive-checks
git -C "$publisher" push -q origin main
printf 'input for the terminal\n' | env "${common_env[@]}" "$ctl" update --yes \
  >"$work/noninteractive.out" 2>"$work/noninteractive.err"
grep -q 'PASS: automated checks have no terminal input' "$work/noninteractive.out"
printf 'PASS: update validation does not read user input\n'

# A failed build must survive installation and remain resumable even though
# the source and installed runtime now match.
printf '\n# build recovery probe\n' >> "$publisher/config/agent-workspace.md"
git -C "$publisher" add config/agent-workspace.md
git -C "$publisher" commit -qm failed-build-probe
git -C "$publisher" push -q origin main
sed -i 's/:3.3.0/:retry-stale/g' "$config"
cp "$config" "$work/build-project-before"
set +e
env "${common_env[@]}" "${project_env[@]}" PATH="$fake_bin:/usr/bin:/bin" \
  DOCKER_LOG="$docker_log" BUILD_FAIL=1 "$ctl" update --yes stale-project \
  >"$work/build-failure.out" 2>"$work/build-failure.err"
result=$?
set -e
[[ "$result" == 23 ]]
grep -q 'fixture image build failed' "$work/build-failure.err"
grep -q 'source checkout and installed runtime are current' "$work/build-failure.err"
grep -q 'Project configuration has not been upgraded' "$work/build-failure.err"
grep -q 'retry: sbx update stale-project' "$work/build-failure.err"
[[ -f "$pending_build" && "$(stat -c %a "$pending_build")" == 600 ]]
[[ -z "$(git -C "$source_checkout" status --porcelain)" ]]
cmp "$config" "$work/build-project-before"
cmp "$source_checkout/config/agent-workspace.md" "$xdg_data/agent-sandbox-kit/config/agent-workspace.md"
[[ "$(git -C "$source_checkout" rev-parse HEAD)" == "$(git -C "$publisher" rev-parse HEAD)" ]]
! grep -Eq 'Next:.*doctor|Next: sbx build' "$work/build-failure.out"
printf 'PASS: a failed image build preserves its status and project, records pending builds, and prints the same update command\n'
env "${common_env[@]}" "$ctl" update --check >"$work/pending-check.out"
grep -q 'Update available: yes' "$work/pending-check.out"
grep -q 'Update unfinished: image builds pending' "$work/pending-check.out"
# A reinstall must not erase the pending flag stored beside its runtime.
env "${common_env[@]}" bash "$source_checkout/install.sh" >"$work/pending-reinstall.out"
[[ -f "$pending_build" ]]
if env "${common_env[@]}" "${project_env[@]}" DAEMON_DOWN=1 "$ctl" update --yes stale-project \
  >"$work/retry-daemon.out" 2>"$work/retry-daemon.err"; then exit 1; fi
grep -q 'Docker daemon is unavailable' "$work/retry-daemon.err"
[[ -f "$pending_build" ]]
cmp "$config" "$work/build-project-before"
set +e
env "${common_env[@]}" "${project_env[@]}" BUILD_FAIL=1 "$ctl" update --yes stale-project \
  >"$work/retry-failed.out" 2>"$work/retry-failed.err"
result=$?
set -e
[[ "$result" == 23 && -f "$pending_build" ]]
grep -q 'resuming unfinished image builds' "$work/retry-failed.out"
cmp "$config" "$work/build-project-before"
: > "$docker_log"
env "${common_env[@]}" "${project_env[@]}" "$ctl" update --yes stale-project >"$work/retry.out" 2>"$work/retry.err"
[[ "$(grep -c '^build ' "$docker_log")" == 3 ]]
[[ ! -e "$pending_build" ]]
for image_key in PROJECT_NETWORK_IMAGE PROJECT_OPENCODE_IMAGE PROJECT_CLAUDE_IMAGE; do
  grep -q "^$image_key=.*:3.3.0$" "$config"
done
diff <(sed '/^PROJECT_.*IMAGE=/d' "$work/build-project-before") <(sed '/^PROJECT_.*IMAGE=/d' "$config")
! grep -Eq '^(volume|create|start) ' "$docker_log"
cp "$config" "$work/build-project-before"
grep -q 'resuming unfinished image builds' "$work/retry.out"
grep -q '^Next: sbx codex run stale-project$' "$work/retry.out"
! grep -Eq 'doctor|Next: sbx build' "$work/retry.out"
: > "$docker_log"
env "${common_env[@]}" "${project_env[@]}" "$ctl" update --yes stale-project >"$work/retry-current.out"
[[ ! -s "$docker_log" ]]
printf 'PASS: retries retain unfinished builds through repeated failures and reinstall, then finish once and remain idempotent\n'

# A successful manual build also clears pending work under the runtime lock.
printf 'pending\n' > "$pending_build"
env "${common_env[@]}" "$xdg_bin/sbx" build >"$work/manual-recovery.out"
[[ ! -e "$pending_build" ]]
printf 'PASS: a successful manual build clears pending work\n'

printf 'preserve\n' > "$work/state-target"
ln -s "$work/state-target" "$pending_build"
if env "${common_env[@]}" "$ctl" update --check >"$work/state.out" 2>"$work/state.err"; then exit 1; fi
grep -q 'invalid pending image-build state' "$work/state.err"
grep -qx preserve "$work/state-target"
rm "$pending_build"
printf 'PASS: symbolic pending-state files are rejected without changing their targets\n'

# Successful named-project updates point straight to run, including when no
# images need rebuilding.
printf '\nsuccessful follow-up\n' >> "$publisher/README.md"
git -C "$publisher" add README.md
git -C "$publisher" commit -qm successful-follow-up
git -C "$publisher" push -q origin main
env "${common_env[@]}" "${project_env[@]}" "$ctl" update --yes stale-project >"$work/success.out" 2>"$work/success.err"
grep -q '^Next: sbx codex run stale-project$' "$work/success.out"
! grep -Eq 'doctor|Next: sbx build' "$work/success.out"
printf 'PASS: a successful named-project update recommends run without redundant checks or builds\n'

# Failure before installation must say that only the source advanced.
printf '\n# validation recovery probe\n' >> "$publisher/config/agent-workspace.md"
printf '#!/usr/bin/env bash\nprintf "fixture validation failed\\n" >&2\nexit 24\n' > "$publisher/tests/static.sh"
git -C "$publisher" add config/agent-workspace.md tests/static.sh
git -C "$publisher" commit -qm failed-validation-probe
git -C "$publisher" push -q origin main
cp "$xdg_data/agent-sandbox-kit/config/agent-workspace.md" "$work/runtime-before-validation"
set +e
env "${common_env[@]}" "${project_env[@]}" "$ctl" update --yes stale-project >"$work/validation.out" 2>"$work/validation.err"
result=$?
set -e
[[ "$result" == 24 ]]
grep -q 'fixture validation failed' "$work/validation.err"
grep -q 'source checkout advanced, but runtime and project configuration were not changed' "$work/validation.err"
grep -q 'After fixing it, run: bash' "$work/validation.err"
cmp "$xdg_data/agent-sandbox-kit/config/agent-workspace.md" "$work/runtime-before-validation"
cmp "$config" "$work/build-project-before"
printf 'PASS: validation failure preserves runtime and project and reports the advanced source\n'

# The installer remains a separate process so its own fail-fast/rollback
# behavior is preserved while the updater adds stage-specific recovery text.
printf '#!/usr/bin/env bash\nexit 0\n' > "$publisher/tests/static.sh"
printf '#!/usr/bin/env bash\nprintf "fixture installation failed\\n" >&2\nexit 25\n' > "$publisher/install.sh"
git -C "$publisher" add tests/static.sh install.sh
git -C "$publisher" commit -qm failed-installation-probe
git -C "$publisher" push -q origin main
set +e
env "${common_env[@]}" "${project_env[@]}" "$ctl" update --yes stale-project >"$work/installation.out" 2>"$work/installation.err"
result=$?
set -e
[[ "$result" == 25 ]]
grep -q 'fixture installation failed' "$work/installation.err"
grep -q 'runtime installation failed; source checkout advanced' "$work/installation.err"
grep -q 'retry: sbx update stale-project' "$work/installation.err"
cmp "$xdg_data/agent-sandbox-kit/config/agent-workspace.md" "$work/runtime-before-validation"
cmp "$config" "$work/build-project-before"
printf 'PASS: installation failure preserves its status and prints a retry command\n'

# Restore a working installer and acquire the project lock during the build,
# after the updater's initial check. Report the remaining project-only step.
cp "$root/install.sh" "$publisher/install.sh"
git -C "$publisher" add install.sh
git -C "$publisher" commit -qm project-upgrade-failure-probe
git -C "$publisher" push -q origin main
project_lock="$workspaces/stale-project/control/.session-lock"
set +e
env "${common_env[@]}" "${project_env[@]}" PATH="$fake_bin:/usr/bin:/bin" \
  DOCKER_LOG="$docker_log" PROJECT_LOCK_ON_BUILD="$project_lock" OWNER_PID="$$" \
  "$ctl" update --yes stale-project >"$work/project-failure.out" 2>"$work/project-failure.err"
result=$?
set -e
[[ "$result" != 0 ]]
grep -q 'while an agent task session is active' "$work/project-failure.err"
grep -q 'runtime installed, but the project configuration upgrade did not complete' "$work/project-failure.err"
grep -q 'retry: sbx update stale-project' "$work/project-failure.err"
[[ ! -e "$pending_build" ]]
cmp "$config" "$work/build-project-before"
rm "$project_lock/owner.txt"
rmdir "$project_lock"
printf 'PASS: a session acquired during building produces project-only recovery instructions\n'
: > "$docker_log"
env "${common_env[@]}" "${project_env[@]}" "$ctl" update --yes stale-project >"$work/project-retry.out"
[[ ! -s "$docker_log" ]]
grep -q '^Next: sbx codex run stale-project$' "$work/project-retry.out"
printf 'PASS: a retry after successful builds applies project references without rebuilding\n'

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
