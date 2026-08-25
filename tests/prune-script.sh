#!/usr/bin/env bash

# Docker-free tests for container/prune-auth-volume.sh (the root-owned
# authentication-volume pruning script). Proves, against temporary
# directories:
#   - junk files and directories are removed;
#   - auth.json remains and becomes mode 0600;
#   - absence of auth.json is valid;
#   - an auth.json directory or symlink is removed;
#   - a non-writable directory produces a visible nonzero result rather than
#     a false pass;
#   - a missing directory is refused.
# Model-free; no Docker daemon is contacted.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
prune="$root/container/prune-auth-volume.sh"

fail_out() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

work="$(mktemp -d)"
mkdir "$work/bin"
printf '%s\n' '#!/usr/bin/env python3' 'import json,sys; json.load(open(sys.argv[-1], encoding="utf-8"))' > "$work/bin/node"
chmod +x "$work/bin/node"
export PATH="$work/bin:$PATH"
cleanup() {
  find "$work" -type d -exec chmod u+w {} + 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

# --- Case 1: junk files and directories removed; auth.json kept at 0600. ---
d1="$work/case1"
mkdir -p "$d1/junk-dir/nested" "$d1/another-junk"
printf '{"credential":"synthetic"}\n' > "$d1/auth.json"
printf 'junk\n' > "$d1/junk-file.txt"
printf 'junk\n' > "$d1/junk-dir/nested/deep.txt"
printf 'junk\n' > "$d1/another-junk/x"
chmod 0644 "$d1/auth.json"

if bash "$prune" "$d1" >"$work/case1.out" 2>"$work/case1.err"; then
  fail_out "unexpected content was silently accepted"
fi

[[ -f "$d1/auth.json" ]] || fail_out "auth.json was deleted"
[[ ! -e "$d1/junk-file.txt" && ! -e "$d1/junk-dir" && ! -e "$d1/another-junk" ]] \
  || fail_out "unexpected content survived pruning"
mode="$(stat -c '%a' "$d1/auth.json")"
[[ "$mode" == "600" ]] || fail_out "auth.json mode is $mode, expected 600"
echo "PASS: junk removed, auth.json normalized, and command failed closed"

# --- Case 2: absence of auth.json is valid. ---
d2="$work/case2"
mkdir -p "$d2"
bash "$prune" "$d2" || fail_out "prune rejected an empty volume"
[[ -z "$(ls -A "$d2")" ]] || fail_out "empty volume was modified"
echo "PASS: absence of auth.json accepted"

# --- Case 3: junk-only volume ends up completely empty. ---
d3="$work/case3"
mkdir -p "$d3/leftover"
touch "$d3/leftover-file"
if bash "$prune" "$d3" >"$work/case3.out" 2>"$work/case3.err"; then fail_out "junk-only state was accepted"; fi
[[ -z "$(ls -A "$d3")" ]] || fail_out "junk-only volume was not emptied"
echo "PASS: junk-only volume emptied"

# --- Case 4: non-writable directory must fail loudly, never pass silently. ---
d4="$work/case4"
mkdir -p "$d4/stuck-dir"
touch "$d4/stuck-dir/inside" "$d4/stuck-file"
chmod 0555 "$d4"
rc=0
bash "$prune" "$d4" > /dev/null 2> "$work/case4.err" || rc=$?
chmod u+w "$d4"
if [[ "$rc" -eq 0 ]]; then
  fail_out "prune reported success on a non-writable directory"
fi
grep -q . "$work/case4.err" || fail_out "prune failure produced no diagnostic output"
echo "PASS: non-writable directory produced a visible nonzero result"

# --- Case 5: missing directory is refused. ---
rc=0
bash "$prune" "$work/does-not-exist" > /dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail_out "prune accepted a missing directory"
echo "PASS: missing directory refused"

# --- Case 6: a directory cannot masquerade as auth.json. ---
d6="$work/case6"
mkdir -p "$d6/auth.json"
touch "$d6/auth.json/junk"
if bash "$prune" "$d6" >"$work/case6.out" 2>"$work/case6.err"; then fail_out "auth.json directory was accepted"; fi
[[ ! -e "$d6/auth.json" ]] || fail_out "auth.json directory survived pruning"
echo "PASS: auth.json directory removed"

# --- Case 7: a symlink cannot masquerade as auth.json. ---
d7="$work/case7"
mkdir -p "$d7"
printf 'target\n' > "$work/symlink-target"
ln -s "$work/symlink-target" "$d7/auth.json"
if bash "$prune" "$d7" >"$work/case7.out" 2>"$work/case7.err"; then fail_out "auth.json symlink was accepted"; fi
[[ ! -e "$d7/auth.json" && ! -L "$d7/auth.json" ]] \
  || fail_out "auth.json symlink survived pruning"
[[ "$(cat "$work/symlink-target")" == "target" ]] \
  || fail_out "prune modified the symlink target"
echo "PASS: auth.json symlink removed without changing its target"

d8="$work/case8"
mkdir "$d8"
printf 'not-json\n' > "$d8/auth.json"
if bash "$prune" "$d8" >"$work/case8.out" 2>"$work/case8.err"; then fail_out "malformed JSON was accepted"; fi
grep -q 'malformed JSON' "$work/case8.err" || fail_out "malformed JSON diagnostic missing"
[[ -f "$d8/auth.json" ]] || fail_out "malformed credential was deleted automatically"
echo "PASS: malformed auth.json rejected without automatic credential deletion"

printf 'RESULT: prune-script checks passed\n'
