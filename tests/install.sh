#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

output="$(HOME="$work/home" PATH=/usr/bin:/bin bash "$root/install.sh")"
[[ -L "$work/home/.local/bin/sbx" ]]
[[ "$(readlink "$work/home/.local/bin/sbx")" == "$root/bin/sbx" ]]
[[ "$output" == *'export PATH="$HOME/.local/bin:$PATH"'* ]] \
  || { echo 'FAIL: installer omitted PATH setup instructions' >&2; exit 1; }
printf 'PASS: installer creates a user-local sbx link and explains missing PATH\n'

output="$(HOME="$work/home" PATH="$work/home/.local/bin:/usr/bin:/bin" bash "$root/install.sh")"
[[ "$output" == *'Run: sbx --help'* ]]
printf 'PASS: installer detects when the user command directory is on PATH\n'
