#!/usr/bin/env bash

# Image-build step only. Install verified exact archives without vendor scripts
# that could download a fallback or select a different native package.
set -euo pipefail
agent="${1:?harness is required}"
case "$agent" in
  codex) prefix=CODEX; wrapper=@openai/codex; platform=@openai/codex; dependency=@openai/codex-linux-x64; platform_suffix=-linux-x64; entry=bin/codex.js ;;
  opencode) prefix=OPENCODE; wrapper=opencode-ai; platform=opencode-linux-x64; dependency="$platform"; platform_suffix=''; entry=bin/opencode.exe ;;
  claude) prefix=CLAUDE; wrapper=@anthropic-ai/claude-code; platform=@anthropic-ai/claude-code-linux-x64; dependency="$platform"; platform_suffix=''; entry=bin/claude.exe ;;
  *) echo "ERROR: unknown harness: $agent" >&2; exit 1 ;;
esac
version_key="${prefix}_VERSION"
package_key="${prefix}_PACKAGE_INTEGRITY"
binary_key="${prefix}_LINUX_X64_INTEGRITY"
version="${!version_key:?}"; package_integrity="${!package_key:?}"; binary_integrity="${!binary_key:?}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$(uname -m)" == x86_64 ]] || { echo 'ERROR: harness images support Linux x64 only' >&2; exit 1; }
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
registry=https://registry.npmjs.org
for kind in wrapper platform; do
  package="$wrapper"; selected="$version"; expected="$package_integrity"
  if [[ "$kind" == platform ]]; then package="$platform"; selected="${version}${platform_suffix}"; expected="$binary_integrity"; fi
  archive="$work/$kind.tgz"
  curl --fail --silent --show-error --proto '=https' --max-time 300 \
    "$registry/$package/-/${package##*/}-${selected}.tgz" -o "$archive"
  actual="$(python3 -c '
import base64, hashlib, sys
digest = hashlib.sha512()
with open(sys.argv[1], "rb") as stream:
    for chunk in iter(lambda: stream.read(1048576), b""):
        digest.update(chunk)
print("sha512-" + base64.b64encode(digest.digest()).decode())
' "$archive")"
  [[ "$actual" == "$expected" ]] || { echo 'ERROR: harness archive integrity mismatch' >&2; exit 1; }
  tar -xOf "$archive" package/package.json | python3 -c '
import json, sys
metadata = json.load(sys.stdin)
package, selected, kind, dependency, version, agent, entry = sys.argv[1:]
def require(condition, message):
    if not condition:
        raise ValueError(message)

require(metadata["name"] == package and metadata["version"] == selected, "package identity/version mismatch")
require(not metadata.get("dependencies") and not metadata.get("peerDependencies"), "unexpected unpinned dependencies")
if kind == "platform":
    require(metadata["os"] == ["linux"] and metadata["cpu"] == ["x64"], "platform is not Linux x64")
    require(metadata.get("libc") in (None, ["glibc"]), "platform is not compatible with glibc")
else:
    mapping = "npm:@openai/codex@" + version + "-linux-x64" if agent == "codex" else version
    require(metadata["optionalDependencies"][dependency] == mapping, "unsupported dependency mapping")
    require(metadata["bin"][agent] in (entry, "./" + entry), "unsupported wrapper entrypoint")
' "$package" "$selected" "$kind" "$dependency" "$version" "$agent" "$entry"
done
npm install --global --ignore-scripts --omit=optional --offline --no-audit --no-fund "$work/wrapper.tgz"
wrapper_dir="$(npm root --global)/$wrapper"
platform_dir="$wrapper_dir/node_modules/$dependency"
mkdir -p "$platform_dir"
tar -xzf "$work/platform.tgz" --strip-components=1 -C "$platform_dir"
case "$agent" in
  codex) actual_version="$(codex --version | awk '{print $2}')" ;;
  opencode)
    install -m 0755 "$platform_dir/bin/opencode" "$wrapper_dir/$entry"
    actual_version="$(opencode --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)" ;;
  claude)
    install -m 0755 "$platform_dir/claude" "$wrapper_dir/$entry"
    actual_version="$(claude --version | awk '{print $1}')" ;;
esac
test "$actual_version" = "$version"
npm cache clean --force
