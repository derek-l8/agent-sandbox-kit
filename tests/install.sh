#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

source_copy="$work/source"
mkdir -p "$source_copy"
cp -a "$root/install.sh" "$root/bin" "$root/adapters" "$root/config" \
  "$root/container" "$root/images" "$root/versions.lock" "$source_copy/"

# Replace only the fixture's compatibility launcher so routing can be checked
# without Docker, authentication, networking, or a model.
apply_stub="$source_copy/bin/sandboxctl"
printf '%s\n' '#!/usr/bin/env bash' 'printf "<%s>\\n" "$@"' > "$apply_stub"
chmod +x "$apply_stub"

home="$work/home"
xdg_bin="$work/xdg/bin"
xdg_data="$work/xdg/data"
mkdir -p "$home/codex-sandbox-kit"
printf 'fallback-must-remain\n' > "$home/codex-sandbox-kit/sentinel"
output="$(HOME="$home" XDG_BIN_HOME="$xdg_bin" XDG_DATA_HOME="$xdg_data" PATH=/usr/bin:/bin bash "$source_copy/install.sh")"
sbx="$xdg_bin/sbx"
runtime="$xdg_data/agent-sandbox-kit"
[[ -L "$sbx" ]]
[[ "$(readlink "$sbx")" == "$runtime/bin/sbx" ]]
for item in bin adapters config container images versions.lock; do
  [[ -e "$runtime/$item" ]] || { echo "FAIL: installed runtime omitted $item" >&2; exit 1; }
done
grep -qx 'fallback-must-remain' "$home/codex-sandbox-kit/sentinel"
[[ "$output" == *"export PATH=\"$xdg_bin:\$PATH\""* ]] \
  || { echo 'FAIL: installer omitted PATH setup instructions' >&2; exit 1; }
printf 'PASS: installer creates a complete XDG runtime and explains missing PATH\n'

mv "$source_copy" "$work/source-unavailable"
help="$(HOME="$home" XDG_BIN_HOME="$xdg_bin" XDG_DATA_HOME="$xdg_data" "$sbx" --help)"
[[ "$help" == *'Agent Sandbox Kit'* ]] || { echo 'FAIL: installed help unavailable' >&2; exit 1; }
[[ "$("$sbx" codex run probe)" == $'<run>\n<probe>' ]]
[[ "$("$sbx" opencode exec probe -- command --flag)" == $'<exec-opencode>\n<probe>\n<-->\n<command>\n<--flag>' ]]
printf 'PASS: installed help and adapter routes survive an unavailable source tree\n'

output="$(HOME="$home" XDG_BIN_HOME="$xdg_bin" XDG_DATA_HOME="$xdg_data" PATH="$xdg_bin:/usr/bin:/bin" bash "$root/install.sh")"
[[ "$output" == *'Run: sbx --help'* ]]
"$sbx" --help >/dev/null
printf 'PASS: upgrade replaces the runtime and detects the command directory on PATH\n'

before="$(sha256sum "$runtime/bin/sbx" "$runtime/versions.lock")"
bad_source="$work/incomplete-source"
mkdir -p "$bad_source"
cp -a "$root/install.sh" "$root/bin" "$root/adapters" "$root/config" \
  "$root/container" "$root/images" "$bad_source/"
if HOME="$home" XDG_BIN_HOME="$xdg_bin" XDG_DATA_HOME="$xdg_data" \
  bash "$bad_source/install.sh" >"$work/bad.out" 2>"$work/bad.err"; then
  echo 'FAIL: incomplete upgrade unexpectedly succeeded' >&2
  exit 1
fi
after="$(sha256sum "$runtime/bin/sbx" "$runtime/versions.lock")"
[[ "$before" == "$after" ]]
"$sbx" --help >/dev/null
grep -qx 'fallback-must-remain' "$home/codex-sandbox-kit/sentinel"
printf 'PASS: failed upgrade preserves the installed runtime and fallback tree\n'
