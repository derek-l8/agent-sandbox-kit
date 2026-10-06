#!/usr/bin/env bash

# Real archive verification with mocked downloads/npm and disposable destinations.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin" "$work/archives" "$work/global"
export ARCHIVES="$work/archives" NPM_ROOT="$work/global" NPM_LOG="$work/npm.log"
cat > "$work/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
archive=wrapper.tgz
[[ "$*" != *'-linux-x64'* ]] || archive=platform.tgz
for (( i=1; i<=$#; i++ )); do
  if [[ "${!i}" == -o ]]; then
    next=$((i + 1)); cp "$ARCHIVES/$archive" "${!next}"; exit
  fi
done
exit 1
SH
cat > "$work/bin/npm" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$NPM_LOG"
if [[ "$1" == root ]]; then
  printf '%s\n' "$NPM_ROOT"
elif [[ "$1" == install ]]; then
  [[ "$*" == *'--global --ignore-scripts --omit=optional'* ]]
  [[ "$*" == *'--offline --no-audit --no-fund'* ]]
  mkdir -p "$NPM_ROOT/$WRAPPER_PACKAGE"
  tar -xzf "${!#}" --strip-components=1 -C "$NPM_ROOT/$WRAPPER_PACKAGE"
fi
SH
cat > "$work/bin/codex" <<'SH'
#!/usr/bin/env bash
[[ "$*" == --version ]] || exit 1
[[ -f "$NPM_ROOT/@openai/codex/node_modules/@openai/codex-linux-x64/package.json" ]] || exit 1
printf 'codex-cli %s\n' "$CODEX_VERSION"
SH
for executable in opencode claude; do
  printf '#!/usr/bin/env bash\nexec "$NPM_ROOT/$WRAPPER_PACKAGE/bin/%s.exe" "$@"\n' "$executable" > "$work/bin/$executable"
done
chmod +x "$work/bin/"*
export PATH="$work/bin:/usr/bin:/bin"
hash_archive() {
  python3 -c 'import base64,hashlib,sys; print("sha512-" + base64.b64encode(hashlib.sha512(open(sys.argv[1],"rb").read()).digest()).decode())' "$1"
}
for agent in codex opencode claude; do
  case "$agent" in
    codex) prefix=CODEX; export WRAPPER_PACKAGE=@openai/codex ;;
    opencode) prefix=OPENCODE; export WRAPPER_PACKAGE=opencode-ai ;;
    claude) prefix=CLAUDE; export WRAPPER_PACKAGE=@anthropic-ai/claude-code ;;
  esac
  export "${prefix}_VERSION=9.999.0"
  python3 - "$ARCHIVES" "$agent" <<'PY'
import io, json, pathlib, tarfile, sys
folder, agent = pathlib.Path(sys.argv[1]), sys.argv[2]
profiles = {
    'codex': ('@openai/codex', '@openai/codex', '@openai/codex-linux-x64', '-linux-x64', 'bin/codex.js', ''),
    'opencode': ('opencode-ai', 'opencode-linux-x64', 'opencode-linux-x64', '', 'bin/opencode.exe', 'bin/opencode'),
    'claude': ('@anthropic-ai/claude-code', '@anthropic-ai/claude-code-linux-x64', '@anthropic-ai/claude-code-linux-x64', '', 'bin/claude.exe', 'claude'),
}
wrapper, platform, dependency, suffix, entry, binary_path = profiles[agent]
for kind in ('wrapper', 'platform'):
    metadata = {'name': wrapper if kind == 'wrapper' else platform, 'version': '9.999.0' + (suffix if kind == 'platform' else '')}
    if kind == 'platform':
        metadata.update(os=['linux'], cpu=['x64'])
    else:
        mapping = 'npm:@openai/codex@9.999.0-linux-x64' if agent == 'codex' else '9.999.0'
        # npm normalizes OpenCode's ./ prefix in registry metadata, while the
        # integrity-verified archive retains it in package.json.
        wrapper_entry = './' + entry if agent == 'opencode' else entry
        metadata.update(optionalDependencies={dependency: mapping}, bin={agent: wrapper_entry})
    files = {'package.json': json.dumps(metadata).encode()}
    if kind == 'wrapper':
        files[entry] = b'#!/bin/sh\nexit 1\n'  # must be replaced by the pinned native fixture
    elif binary_path:
        output = '9.999.0 (Claude Code)' if agent == 'claude' else '9.999.0'
        files[binary_path] = f'#!/bin/sh\n[ "$*" = --version ] || exit 1\nprintf "%s\\n" "{output}"\n'.encode()
    with tarfile.open(folder / (kind + '.tgz'), 'w:gz') as archive:
        for name, data in files.items():
            entry = tarfile.TarInfo('package/' + name); entry.size = len(data); entry.mode = 0o755
            archive.addfile(entry, io.BytesIO(data))
PY
  export "${prefix}_PACKAGE_INTEGRITY=$(hash_archive "$ARCHIVES/wrapper.tgz")"
  export "${prefix}_LINUX_X64_INTEGRITY=$(hash_archive "$ARCHIVES/platform.tgz")"
  : > "$NPM_LOG"
  bash "$root/container/install-harness.sh" "$agent"
  [[ "$(grep -c '^install ' "$NPM_LOG")" -eq 1 ]]
  printf 'PASS: %s installer verifies archives and places the exact native dependency without vendor scripts\n' "$agent"
  for archive in wrapper.tgz platform.tgz; do
    cp "$ARCHIVES/$archive" "$work/original"
    printf tampered >> "$ARCHIVES/$archive"
    : > "$NPM_LOG"
    if bash "$root/container/install-harness.sh" "$agent" >"$work/out" 2>"$work/err"; then exit 1; fi
    grep -q 'archive integrity mismatch' "$work/err"
    [[ ! -s "$NPM_LOG" ]]
    mv "$work/original" "$ARCHIVES/$archive"
  done
  printf 'PASS: %s wrapper and platform tampering fails before installation\n' "$agent"
  cp "$ARCHIVES/wrapper.tgz" "$work/original-wrapper"
  python3 - "$ARCHIVES/wrapper.tgz" "$agent" <<'PY'
import io, json, tarfile, sys
with tarfile.open(sys.argv[1], 'r:gz') as archive:
    data = json.load(archive.extractfile('package/package.json'))
data['bin'][sys.argv[2]] = './../outside'
encoded = json.dumps(data).encode()
with tarfile.open(sys.argv[1], 'w:gz') as archive:
    entry = tarfile.TarInfo('package/package.json'); entry.size = len(encoded)
    archive.addfile(entry, io.BytesIO(encoded))
PY
  export "${prefix}_PACKAGE_INTEGRITY=$(hash_archive "$ARCHIVES/wrapper.tgz")"
  : > "$NPM_LOG"
  if bash "$root/container/install-harness.sh" "$agent" >"$work/out" 2>"$work/err"; then exit 1; fi
  grep -q 'unsupported wrapper entrypoint' "$work/err"
  [[ ! -s "$NPM_LOG" ]]
  mv "$work/original-wrapper" "$ARCHIVES/wrapper.tgz"
  export "${prefix}_PACKAGE_INTEGRITY=$(hash_archive "$ARCHIVES/wrapper.tgz")"
  printf 'PASS: %s integrity-valid unexpected wrapper path is rejected before installation\n' "$agent"
  python3 - "$ARCHIVES/platform.tgz" <<'PY'
import io, json, tarfile, sys
with tarfile.open(sys.argv[1], 'r:gz') as archive:
    data = json.load(archive.extractfile('package/package.json'))
data['cpu'] = ['arm64']
encoded = json.dumps(data).encode()
with tarfile.open(sys.argv[1], 'w:gz') as archive:
    entry = tarfile.TarInfo('package/package.json'); entry.size = len(encoded)
    archive.addfile(entry, io.BytesIO(encoded))
PY
  export "${prefix}_LINUX_X64_INTEGRITY=$(hash_archive "$ARCHIVES/platform.tgz")"
  : > "$NPM_LOG"
  if PYTHONOPTIMIZE=1 bash "$root/container/install-harness.sh" "$agent" >"$work/out" 2>"$work/err"; then exit 1; fi
  grep -q 'platform is not Linux x64' "$work/err"
  [[ ! -s "$NPM_LOG" ]]
  printf 'PASS: %s integrity-valid wrong-architecture archive is rejected even with Python optimization\n' "$agent"
  python3 - "$ARCHIVES/wrapper.tgz" <<'PY'
import io, json, tarfile, sys
with tarfile.open(sys.argv[1], 'r:gz') as archive:
    data = json.load(archive.extractfile('package/package.json'))
data['peerDependencies'] = {'unpinned-extra': 'latest'}
encoded = json.dumps(data).encode()
with tarfile.open(sys.argv[1], 'w:gz') as archive:
    entry = tarfile.TarInfo('package/package.json'); entry.size = len(encoded)
    archive.addfile(entry, io.BytesIO(encoded))
PY
  export "${prefix}_PACKAGE_INTEGRITY=$(hash_archive "$ARCHIVES/wrapper.tgz")"
  : > "$NPM_LOG"
  if bash "$root/container/install-harness.sh" "$agent" >"$work/out" 2>"$work/err"; then exit 1; fi
  grep -q 'unexpected unpinned dependencies' "$work/err"
  [[ ! -s "$NPM_LOG" ]]
  printf 'PASS: %s unpinned peer dependency is rejected before npm installation\n' "$agent"
done
