#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export CODEX_SANDBOX_WORKSPACES_ROOT="$work/workspaces"
sbx="$root/bin/sbx"
"$sbx" init probe >/dev/null
project="$CODEX_SANDBOX_WORKSPACES_ROOT/probe"
mkdir -p "$work/source" "$work/bin"
printf 'original\n' > "$work/source/Plan with spaces.pdf"
printf 'image\n' > "$work/source/image.png"
# Import before cloning a repository is supported. Windows translation is
# stubbed here; the actual wslpath integration is checked on WSL separately.
cat > "$work/bin/wslpath" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == -u && "$2" == 'C:\Users\Derek\Plan with spaces.pdf' ]] || exit 1
printf '%s/source/Plan with spaces.pdf' "$CONTEXT_TEST_ROOT"
STUB
chmod +x "$work/bin/wslpath"
export CONTEXT_TEST_ROOT="$work"
export PATH="$work/bin:$PATH"
printf '"C:\Users\Derek\Plan with spaces.pdf"\r\n"%s/source/image.png"\r\n\r\n' "$work" \
  | "$sbx" context probe > "$work/result"
grep -qx 'Imported: /context/Plan with spaces.pdf' "$work/result"
cmp "$work/source/Plan with spaces.pdf" "$project/context/Plan with spaces.pdf"
"$sbx" context probe list | grep -qx '/context/image.png'
printf 'changed\n' > "$work/source/image.png"
printf 'n\n' | "$sbx" context probe add "$work/source/image.png" >/dev/null
grep -qx image "$project/context/image.png"
printf 'y\n' | "$sbx" context probe add "$work/source/image.png" >/dev/null
grep -qx changed "$project/context/image.png"
# No shell expansion: a command substitution in a filename stays literal.
literal='$(touch NOT_EXECUTED).txt'
printf 'literal\n' > "$work/source/$literal"
"$sbx" context probe add "$work/source/$literal" >/dev/null
test -f "$project/context/$literal"
test ! -e NOT_EXECUTED
if "$sbx" context probe add "$work/missing.pdf" > /dev/null 2>&1; then exit 1; fi
if "$sbx" context probe remove ../source/image.png > /dev/null 2>&1; then exit 1; fi
"$sbx" context probe remove image.png >/dev/null
test -f "$work/source/image.png"
test ! -e "$project/context/image.png"
git -C "$project/repo" init -q
printf 'state\n' > "$project/data/state.txt"
test -z "$(git -C "$project/repo" status --porcelain)"
mkdir "$project/control/.session-lock"
printf 'pid=%s\n' "$$" > "$project/control/.session-lock/owner.txt"
if "$sbx" context probe add "$work/source/image.png" >"$work/out" 2>"$work/err"; then exit 1; fi
grep -q 'a session is already active' "$work/err"
rm "$project/control/.session-lock/owner.txt"
rmdir "$project/control/.session-lock"
# Symlink tests require real symlinks (Linux, or MSYS winsymlinks:nativestrict).
if ln -s "$work/source/image.png" "$work/link.png" 2>/dev/null && [[ -L "$work/link.png" ]]; then
  if "$sbx" context probe add "$work/link.png" >/dev/null 2>&1; then exit 1; fi
  ln -s "$work/source/image.png" "$project/context/image.png"
  if "$sbx" context probe add "$work/source/image.png" >/dev/null 2>&1; then exit 1; fi
else
  printf 'SKIP: symlink rejection requires a filesystem with symlink support\n'
fi
printf 'PASS: context imports, replacement decisions, literal paths, removal, lock, and Git separation\n'
