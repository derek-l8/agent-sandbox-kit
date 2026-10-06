#!/usr/bin/env bash

set -euo pipefail
if [[ "$#" -eq 0 ]]; then
  for agent in codex opencode claude; do bash "$0" "$agent"; done
  exit 0
fi
agent="$1"
case "$agent" in
  codex) prefix=CODEX; label=Codex; project_image_key=PROJECT_NETWORK_IMAGE; image_name=networked ;;
  opencode) prefix=OPENCODE; label=OpenCode; project_image_key=PROJECT_OPENCODE_IMAGE; image_name=opencode ;;
  claude) prefix=CLAUDE; label='Claude Code'; project_image_key=PROJECT_CLAUDE_IMAGE; image_name=claude ;;
esac
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap '[[ -z "${updater_pid:-}" ]] || { kill "$updater_pid" 2>/dev/null || true; wait "$updater_pid" 2>/dev/null || true; }; rm -rf -- "$work"' EXIT
export PYTHONDONTWRITEBYTECODE=1
unset SBX_DISABLE_UPDATE_CHECK SBX_DISABLE_HARNESS_UPDATE_CHECK SBX_DISABLE_CODEX_UPDATE_CHECK SBX_DISABLE_OPENCODE_UPDATE_CHECK SBX_DISABLE_CLAUDE_UPDATE_CHECK
mkdir -p "$work/source" "$work/fake-bin" "$work/metadata"
cp -a "$root/install.sh" "$root/bin" "$root/adapters" "$root/config" "$root/container" "$root/images" "$root/versions.lock" "$work/source/"
export HOME="$work/home" XDG_DATA_HOME="$work/data" XDG_BIN_HOME="$work/commands" XDG_CACHE_HOME="$work/cache"
export CODEX_SANDBOX_WORKSPACES_ROOT="$work/projects" DOCKER_LOG="$work/docker.log" METADATA_ROOT="$work/metadata"
export METADATA="$METADATA_ROOT/$agent"
bash "$work/source/install.sh" >/dev/null
ctl="$XDG_DATA_HOME/agent-sandbox-kit/bin/sandboxctl"
kit="$XDG_DATA_HOME/agent-sandbox-kit"
python3 - "$root" "$METADATA_ROOT" <<'PY'
import importlib.util, json, pathlib, sys
spec = importlib.util.spec_from_file_location('fixtures', pathlib.Path(sys.argv[1]) / 'tests/harness-release.py')
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)
for agent in ('codex', 'opencode', 'claude'):
    folder = pathlib.Path(sys.argv[2]) / agent
    folder.mkdir()
    for label, value in zip(('wrapper', 'platform'), fixtures.metadata(selected="9.999.0", agent=agent)):
        (folder / (label + '.json')).write_text(json.dumps(value))
PY
cat > "$work/fake-bin/python3" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == */harness-release.py && "${4:-}" == resolve ]]; then
  printf 'registry\n' >> "$METADATA/calls"
  /usr/bin/python3 - "$@" <<'PY'
import importlib.util, json, os, pathlib, sys
spec = importlib.util.spec_from_file_location('release', sys.argv[1])
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
release.configure(sys.argv[3])
def fetch(selector, package=None):
    if os.environ.get('REGISTRY_FAIL') == '1' or os.environ.get('REGISTRY_FAIL_AGENT') == release.AGENT:
        raise OSError('fixture offline')
    name = 'platform' if package is not None else 'wrapper'
    return json.loads((pathlib.Path(os.environ['METADATA_ROOT']) / release.AGENT / (name + '.json')).read_text())
release.fetch = fetch
sys.argv = sys.argv[1:]
sys.exit(release.main())
PY
else
  exec /usr/bin/python3 "$@"
fi
SH
cat > "$work/fake-bin/docker" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DOCKER_LOG"
if [[ "$1" == build ]]; then
  [[ "${BUILD_FAIL:-0}" != 1 ]] || exit 1
  if [[ -n "${BUILD_GATE:-}" ]]; then
    touch "$BUILD_GATE/entered"
    while [[ ! -f "$BUILD_GATE/release" ]]; do sleep 0.02; done
  fi
  printf '%s\n' "$@" > "$DOCKER_LOG.args"
elif [[ "$1 $2" == 'image inspect' && "${3:-}" == --format ]]; then
  case "$4" in
    *kit.version*) key=KIT_VERSION ;;
    *codex.version*) key=CODEX_VERSION ;;
    *opencode.version*) key=OPENCODE_VERSION ;;
    *claude.version*) key=CLAUDE_VERSION ;;
    *base.image*) key=BASE_IMAGE ;;
    *codex.package-integrity*) key=CODEX_PACKAGE_INTEGRITY ;;
    *opencode.package-integrity*) key=OPENCODE_PACKAGE_INTEGRITY ;;
    *claude.package-integrity*) key=CLAUDE_PACKAGE_INTEGRITY ;;
    *codex.linux-x64-integrity*) key=CODEX_LINUX_X64_INTEGRITY ;;
    *opencode.linux-x64-integrity*) key=OPENCODE_LINUX_X64_INTEGRITY ;;
    *claude.linux-x64-integrity*) key=CLAUDE_LINUX_X64_INTEGRITY ;;
    *mode*) echo networked-public; exit 0 ;;
    *) exit 1 ;;
  esac
  if [[ "${LABEL_FAIL:-0}" == 1 && "$key" == KIT_VERSION ]]; then echo mismatched; exit 0; fi
  sed -n "s/^$key=//p" "$DOCKER_LOG.args"
fi
SH
chmod +x "$work/fake-bin/"*
export PATH="$work/fake-bin:/usr/bin:/bin"
"$ctl" init probe >/dev/null
mkdir -p "$CODEX_SANDBOX_WORKSPACES_ROOT/probe/repo/.git"
config="$CODEX_SANDBOX_WORKSPACES_ROOT/probe/control/project.env"
# Unrelated project pins must survive a single-harness update, even when stale.
for key in PROJECT_NETWORK_IMAGE PROJECT_OPENCODE_IMAGE PROJECT_CLAUDE_IMAGE; do
  [[ "$key" == "$project_image_key" ]] || sed -i "/^$key=/s/:3.3.0/:retain/" "$config"
done
cp "$config" "$work/config-before"
touch "$DOCKER_LOG"
"$ctl" ${agent}-update --check > "$work/check.out"
grep -q "$label update available: yes" "$work/check.out"
[[ ! -e "$kit/${agent}-release.lock" && ! -s "$DOCKER_LOG" ]]
cmp "$config" "$work/config-before"
printf 'PASS: independent CLI check resolves stable metadata without changing selection, images, or project\n'

for args in '--check --yes' '--check probe' '--version' '--version latest' '--version 9.999.0-alpha.1'; do
  read -ra invocation <<< "$args"
  if "$ctl" ${agent}-update "${invocation[@]}" >"$work/out" 2>"$work/err"; then exit 1; fi
done
if REGISTRY_FAIL=1 "$ctl" ${agent}-update --check >"$work/out" 2>"$work/err"; then exit 1; fi
grep -q "could not resolve published $label release" "$work/err"
printf 'PASS: explicit checks fail clearly on invalid arguments or registry failure\n'

REGISTRY_FAIL=1 "$ctl" update --auto-check >"$work/out" 2>"$work/err"
[[ ! -s "$work/err" && -f "$XDG_CACHE_HOME/agent-sandbox-kit/${agent}-update-check" ]]
calls="$(wc -l < "$METADATA/calls")"
"$ctl" update --auto-check >"$work/out" 2>"$work/err"
[[ ! -s "$work/err" && "$calls" -eq "$(wc -l < "$METADATA/calls")" ]]
rm "$XDG_CACHE_HOME/agent-sandbox-kit/${agent}-update-check"
"$ctl" update --auto-check >"$work/out" 2>"$work/err"
grep -q "${prefix} UPDATE AVAILABLE:" "$work/err"
rm "$XDG_CACHE_HOME/agent-sandbox-kit/${agent}-update-check"
SBX_DISABLE_UPDATE_CHECK=1 "$ctl" update --auto-check >"$work/out" 2>"$work/err"
[[ ! -s "$work/err" && ! -e "$XDG_CACHE_HOME/agent-sandbox-kit/${agent}-update-check" ]]
env "SBX_DISABLE_${prefix}_UPDATE_CHECK=1" "$ctl" update --auto-check >"$work/out" 2>"$work/err"
[[ ! -s "$work/err" && ! -e "$XDG_CACHE_HOME/agent-sandbox-kit/${agent}-update-check" ]]
# An expired cache is checked again while the other harness caches stay fresh.
touch -d '25 hours ago' "$XDG_CACHE_HOME/agent-sandbox-kit/${agent}-update-check"
calls="$(wc -l < "$METADATA/calls")"
"$ctl" update --auto-check >"$work/out" 2>"$work/err"
grep -q "${prefix} UPDATE AVAILABLE:" "$work/err"
[[ "$(( calls + 1 ))" -eq "$(wc -l < "$METADATA/calls")" ]]
printf 'PASS: launch discovery works without a Git source, caches failed attempts for 24 hours, and respects opt-out\n'

rm "$XDG_CACHE_HOME/agent-sandbox-kit/"*-update-check
calls="$(wc -l < "$METADATA/calls")"
"$ctl" update --auto-check >"$work/out" 2>"$work/err"
for notice in CODEX OPENCODE CLAUDE; do grep -q "$notice UPDATE AVAILABLE:" "$work/err"; done
[[ "$(( calls + 3 ))" -eq "$(wc -l < "$METADATA/calls")" ]]
"$ctl" update --auto-check >"$work/out" 2>"$work/err"
[[ ! -s "$work/err" && "$(( calls + 3 ))" -eq "$(wc -l < "$METADATA/calls")" ]]
printf 'PASS: one launch independently resolves all three profiles and the next launch uses their caches\n'

rm "$XDG_CACHE_HOME/agent-sandbox-kit/"*-update-check
REGISTRY_FAIL_AGENT="$agent" "$ctl" update --auto-check >"$work/out" 2>"$work/err"
! grep -q "$prefix UPDATE AVAILABLE:" "$work/err"
[[ "$(grep -c 'UPDATE AVAILABLE:' "$work/err")" -eq 2 ]]
calls="$(wc -l < "$METADATA/calls")"
"$ctl" update --auto-check >"$work/out" 2>"$work/err"
[[ ! -s "$work/err" && "$calls" -eq "$(wc -l < "$METADATA/calls")" ]]
printf 'PASS: one unavailable harness does not suppress the other notices and its failure is cached\n'

mkdir "$CODEX_SANDBOX_WORKSPACES_ROOT/probe/control/.session-lock"
printf 'pid=%s\n' "$$" > "$CODEX_SANDBOX_WORKSPACES_ROOT/probe/control/.session-lock/owner.txt"
if "$ctl" ${agent}-update --yes probe >"$work/out" 2>"$work/err"; then exit 1; fi
grep -q 'while an agent task session is active' "$work/err"
rm -rf "$CODEX_SANDBOX_WORKSPACES_ROOT/probe/control/.session-lock"
if BUILD_FAIL=1 "$ctl" ${agent}-update --yes probe >"$work/out" 2>"$work/err"; then exit 1; fi
[[ ! -e "$kit/${agent}-release.lock" ]]
cmp "$config" "$work/config-before"
printf 'PASS: active sessions and failed builds preserve the previous selection and project\n'

if LABEL_FAIL=1 "$ctl" ${agent}-update --yes >"$work/out" 2>"$work/err"; then exit 1; fi
grep -q 'image label mismatch' "$work/err"
[[ ! -e "$kit/${agent}-release.lock" ]]
cmp "$config" "$work/config-before"
printf 'PASS: image label mismatch fails before activating the CLI selection even without a named project\n'

: > "$DOCKER_LOG"
"$ctl" ${agent}-update --yes --version 9.999.0 probe >"$work/apply.out"
[[ "$(grep -c '^build ' "$DOCKER_LOG")" -eq 1 ]]
grep -q "^${prefix}_VERSION=9.999.0$" "$kit/${agent}-release.lock"
grep -Eq "^${project_image_key}=local/codex-sandbox-${image_name}:3.3.0-${agent}-9.999.0-[a-f0-9]{16}$" "$config"
diff <(sed "/^${project_image_key}=/d" "$work/config-before") <(sed "/^${project_image_key}=/d" "$config")
backup="$(find "$(dirname "$config")" -name 'project.env.pre-upgrade-*.bak' -print -quit)"
cmp "$backup" "$work/config-before"
cmp "$kit/versions.lock" "$root/versions.lock"
! grep -Eq 'volume|create|start|login|latest' "$DOCKER_LOG"
"$ctl" version | grep -q "Selected $label CLI: 9.999.0"
printf 'PASS: confirmed host upgrade builds only a pinned distinct harness image, verifies labels, then activates selection and backs up project config\n'

: > "$DOCKER_LOG"
"$ctl" ${agent}-update --check >"$work/no-update.out"
grep -q "$label update available: no" "$work/no-update.out"
[[ ! -s "$DOCKER_LOG" ]]
"$ctl" init late-project >/dev/null
mkdir -p "$CODEX_SANDBOX_WORKSPACES_ROOT/late-project/repo/.git"
sed -i "s/^${project_image_key}=.*/${project_image_key}=local\/codex-sandbox-${image_name}:stale/" "$CODEX_SANDBOX_WORKSPACES_ROOT/late-project/control/project.env"
"$ctl" ${agent}-update --yes late-project >/dev/null
! grep -q '^build ' "$DOCKER_LOG"
grep -q "${agent}-9.999.0-" "$CODEX_SANDBOX_WORKSPACES_ROOT/late-project/control/project.env"
printf 'PASS: no-update path can still migrate a stale project without rebuilding\n'

python3 - "$METADATA" <<'PY'
import json, pathlib, sys
folder = pathlib.Path(sys.argv[1])
for name in ('wrapper', 'platform'):
    path = folder / (name + '.json')
    path.write_text(path.read_text().replace('9.999.0', '9.1000.0'))
PY
cp "$kit/${agent}-release.lock" "$work/previous-selection"
mkdir "$work/build-gate"
BUILD_GATE="$work/build-gate" "$ctl" ${agent}-update --yes >"$work/locked-update.out" 2>"$work/locked-update.err" &
updater_pid=$!
for (( attempt=0; attempt<500; attempt++ )); do
  [[ ! -f "$work/build-gate/entered" ]] || break
  kill -0 "$updater_pid" 2>/dev/null || { cat "$work/locked-update.err" >&2; exit 1; }
  sleep 0.02
done
[[ -f "$work/build-gate/entered" ]]
if bash "$work/source/install.sh" >"$work/out" 2>"$work/err"; then exit 1; fi
grep -q 'another runtime installation or version update is active' "$work/err"
if "$ctl" ${agent}-update --yes probe >"$work/out" 2>"$work/err"; then exit 1; fi
grep -q 'another runtime installation or version update is active' "$work/err"
cmp "$kit/${agent}-release.lock" "$work/previous-selection"
touch "$work/build-gate/release"
wait "$updater_pid"
printf 'PASS: concurrent reinstall and CLI application cannot overwrite an in-progress selection\n'
selection_backup="$(find "$kit" -name "${agent}-release.lock.pre-update-*.bak" -print -quit)"
cmp "$selection_backup" "$work/previous-selection"
printf 'PASS: replacing a host CLI selection retains its exact previous pins as a backup\n'

before="$(cat "$kit/${agent}-release.lock")"
bash "$work/source/install.sh" >/dev/null
[[ "$(cat "$kit/${agent}-release.lock")" == "$before" ]]
"$ctl" version | grep -q "Selected $label CLI: 9.1000.0"
cmp "$selection_backup" "$work/previous-selection"
printf 'PASS: source-kit reinstall preserves and validates independent harness selection\n'

printf 'BAD=value\n' >> "$kit/${agent}-release.lock"
if bash "$work/source/install.sh" >"$work/out" 2>"$work/err"; then exit 1; fi
grep -q "invalid $agent release lock" "$work/err"
printf 'PASS: malformed retained lock prevents replacement of the installed runtime\n'
