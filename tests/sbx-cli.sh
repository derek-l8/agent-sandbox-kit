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
  'codex run' 'codex login' 'codex auth-status' \
  'codex logout' 'codex doctor' 'codex reset-auth' \
  'codex shell' 'codex exec' \
  'opencode run' 'opencode login' \
  'opencode auth-status' 'opencode logout' 'opencode reset-auth' \
  'opencode doctor' 'opencode shell' 'opencode exec' \
  'claude run' 'claude login' 'claude auth-status' 'claude logout' \
  'claude doctor' 'claude reset-auth' 'claude shell' 'claude exec'; do
  read -r agent action <<< "$spec"
  assert_output "<$agent>
<$action>
<probe>" "$agent" "$action" probe
done
printf 'PASS: all public agent/action routes forward canonical commands\n'

assert_output '<codex>
<exec>
<probe>
<-->
<bash>
<-lc>
<printf "%s %s" one two>' codex exec probe -- bash -lc 'printf "%s %s" one two'
assert_output '<opencode>
<exec>
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

for bad in 'unknown-agent run probe' 'codex fly probe' 'opencode destroy probe'; do
  read -ra args <<< "$bad"
  if "$sbx" "${args[@]}" >"$work/out" 2>"$work/err"; then
    printf 'FAIL: invalid invocation succeeded: %s\n' "$bad" >&2
    exit 1
  fi
  grep -Eq 'unknown agent|invalid action' "$work/err" \
    || { printf 'FAIL: unclear error for %s\n' "$bad" >&2; exit 1; }
done
printf 'PASS: unknown agents and actions fail clearly\n'

for command in run run-opencode offline package; do
  if "$root/bin/sandboxctl" "$command" probe >"$work/out" 2>"$work/err"; then
    echo "FAIL: removed command accepted: $command" >&2; exit 1
  fi
  grep -q 'unknown agent or command' "$work/err"
done
printf 'PASS: removed commands are rejected by the launcher\n'
