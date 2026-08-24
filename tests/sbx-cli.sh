#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/kit/bin" "$work/kit/adapters"
cp "$root/bin/sbx" "$work/kit/bin/sbx"
cp "$root/adapters/"*.sh "$work/kit/adapters/"

cat > "$work/kit/bin/sandboxctl" <<'STUB'
#!/usr/bin/env bash
printf '<%s>\n' "$@"
STUB
chmod +x "$work/kit/bin/sbx" "$work/kit/bin/sandboxctl"
sbx="$work/kit/bin/sbx"

assert_output() {
  local expected="$1"
  shift
  local actual
  actual="$("$sbx" "$@")"
  [[ "$actual" == "$expected" ]] || {
    printf 'FAIL: %q produced %q; expected %q\n' "$*" "$actual" "$expected" >&2
    exit 1
  }
}

for spec in \
  'codex run run' 'codex login login' 'codex doctor doctor' \
  'codex shell shell' 'codex exec exec' \
  'opencode run run-opencode' 'opencode login login-opencode' \
  'opencode doctor doctor-opencode' 'opencode shell shell-opencode' \
  'opencode exec exec-opencode'; do
  read -r agent action legacy <<< "$spec"
  assert_output "<$legacy>
<probe>" "$agent" "$action" probe
done
printf 'PASS: all public agent/action routes translate to compatibility commands\n'

assert_output '<exec>
<probe>
<-->
<bash>
<-lc>
<printf "%s %s" one two>' codex exec probe -- bash -lc 'printf "%s %s" one two'
assert_output '<exec-opencode>
<probe>
<-->
<command with spaces>
<--literal>' opencode exec probe -- 'command with spaces' --literal
printf 'PASS: arguments after -- retain their exact boundaries\n'

assert_output '<init>
<probe>' init probe
assert_output '<build>' build
printf 'PASS: shared commands translate directly\n'

help="$($sbx --help)"
[[ "$help" == *'Agent Sandbox Kit'* && "$help" == *'sbx <agent> <action> <project>'* ]] \
  || { echo 'FAIL: help output is incomplete' >&2; exit 1; }
printf 'PASS: help presents the short interface\n'

for bad in 'claude run probe' 'codex fly probe' 'opencode destroy probe'; do
  read -ra args <<< "$bad"
  if "$sbx" "${args[@]}" >"$work/out" 2>"$work/err"; then
    printf 'FAIL: invalid invocation succeeded: %s\n' "$bad" >&2
    exit 1
  fi
  grep -Eq 'unknown agent|invalid action' "$work/err" \
    || { printf 'FAIL: unclear error for %s\n' "$bad" >&2; exit 1; }
done
printf 'PASS: unknown agents and actions fail clearly\n'

# The original entrypoint remains executable and dispatches help itself.
compat="$($root/bin/sandboxctl --help)"
[[ "$compat" == *'Usage: sandboxctl <command>'* && "$compat" == *'run-opencode'* ]] \
  || { echo 'FAIL: sandboxctl compatibility help changed' >&2; exit 1; }
printf 'PASS: bin/sandboxctl remains directly usable\n'
