#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

while IFS= read -r script; do
  bash -n "$script" || fail "shell syntax: $script"
done < <(find "$root" \( -type f -name '*.sh' -o -path "$root/bin/sandboxctl" -o -path "$root/bin/sbx" \))

# Run every Docker-free suite from this one entry point. Any suite failure
# aborts static.sh with a nonzero status.
run_suite() {
  local suite="$1"
  printf '\n===== SUITE: %s =====\n' "$suite"
  bash "$root/tests/$suite" || fail "suite failed: $suite"
}

run_suite prune-script.sh
run_suite opencode-command-reachability.sh
run_suite opencode-control-flow.sh
run_suite codex-auth-control-flow.sh
run_suite launcher-boundaries.sh
run_suite adapter-conformance.sh
run_suite sbx-cli.sh
run_suite install.sh
run_suite upgrade.sh
run_suite auth-compatibility.sh
run_suite diagnostics.sh
run_suite smoke-safety.sh

python3 - <<'PY' "$root/config/codex-config.toml" "$root/config/codex-requirements.toml"
import sys
import tomllib
for path in sys.argv[1:]:
    with open(path, "rb") as handle:
        tomllib.load(handle)
    print(f"PASS: parsed {path}")
PY

python3 - <<'PY' "$root/config/opencode-managed.json"
import sys
import json
with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)

assertions = {
    "autoupdate disabled": lambda c: c.get("autoupdate") is False,
    "sharing disabled": lambda c: c.get("share") == "disabled",
    "snapshots disabled": lambda c: c.get("snapshot") is False,
    "no MCP servers": lambda c: c.get("mcp") == {},
    "loopback-only server without mdns": lambda c: c.get("server", {}).get("hostname") == "127.0.0.1"
        and c.get("server", {}).get("mdns") is False,
    "external directories denied": lambda c: c.get("permission", {}).get("external_directory") == "deny",
}
for label, check in assertions.items():
    if not check(config):
        raise SystemExit(f"managed OpenCode configuration violates: {label}")
    print(f"PASS: managed OpenCode configuration: {label}")

bash_denies = config.get("permission", {}).get("bash", {})
for pattern in ["git push*", "git commit*", "git remote*", "git submodule*", "gh *"]:
    if bash_denies.get(pattern) != "deny":
        raise SystemExit(f"Git/GitHub command restriction missing or not denied: {pattern}")
print("PASS: managed OpenCode configuration denies git push/commit/remote/submodule and gh")
PY

grep -Eq '^BASE_IMAGE=.+@sha256:[0-9a-f]{64}$' "$root/versions.lock" \
  || fail "base image digest pin"
grep -Eq '^CODEX_VERSION=[0-9]+\.[0-9]+\.[0-9]+$' "$root/versions.lock" \
  || fail "Codex version pin"
grep -Eq '^OPENCODE_VERSION=1\.18\.21$' "$root/versions.lock" \
  || fail "OpenCode version pin must be 1.18.21"
grep -Eq '^OPENCODE_PACKAGE_INTEGRITY=sha512-[A-Za-z0-9+/]+={0,2}$' "$root/versions.lock" \
  || fail "OpenCode package integrity pin"
grep -Eq '^OPENCODE_LINUX_X64_INTEGRITY=sha512-[A-Za-z0-9+/]+={0,2}$' "$root/versions.lock" \
  || fail "OpenCode linux-x64 binary integrity pin"

# Both agent images must contain the root-owned fail-closed authentication
# pruner. Codex task wrappers must never try to synchronize through a
# read-only /auth mount.
for dockerfile in codex-networked.Dockerfile opencode.Dockerfile; do
  grep -qF 'COPY container/prune-auth-volume.sh /usr/local/lib/codex-sandbox/prune-auth-volume' \
    "$root/images/$dockerfile" \
    || fail "$dockerfile does not include the authentication-volume pruner"
done
grep -qF '[[ -w /auth ]] || return 0' "$root/container/run-with-codex-auth.sh" \
  || fail "Codex auth wrapper does not skip synchronization for read-only task mounts"

# The pinned OpenCode image verifies both integrity values before installing.
for token in \
  'npm view "opencode-ai@${OPENCODE_VERSION}" dist.integrity' \
  'npm view "opencode-linux-x64@${OPENCODE_VERSION}" dist.integrity' \
  'opencode-ai@${OPENCODE_VERSION}'; do
  grep -qF "$token" "$root/images/opencode.Dockerfile" \
    || fail "opencode.Dockerfile is missing required pin element: $token"
done

# General temporary storage stays non-executable. Only OpenCode task/auth
# containers receive Bun's private executable extraction tmpfs and BUN_TMPDIR.
python3 - "$root/bin/sandboxctl" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
logical, pending = [], ""
for line in text.splitlines():
    combined = f"{pending} {line.strip()}" if pending else line
    if combined.rstrip().endswith("\\"):
        pending = combined.rstrip()[:-1]
    else:
        logical.append(combined)
        pending = ""
creates = [line for line in logical if re.search(r"\bdocker create\b", line)]
opencode = [line for line in creates if "PROJECT_OPENCODE_IMAGE" in line]
other = [line for line in creates if "PROJECT_OPENCODE_IMAGE" not in line]
tmp = "--tmpfs /tmp:rw,nosuid,nodev,noexec,size=1073741824,mode=1777"
bun_mount = "--tmpfs /run/opencode-bun-tmp:rw,nosuid,nodev,exec,size=67108864,uid=1000,gid=1000,mode=0700"
bun_env = "--env BUN_TMPDIR=/run/opencode-bun-tmp"
common = re.search(r"set_common_args\(\).*?container_common_args=\((.*?)\n  \)", text, re.S)
if not common or tmp not in " ".join(line.strip() for line in common.group(1).splitlines()):
    raise SystemExit("shared /tmp tmpfs must remain explicitly noexec")
if len(opencode) != 2 or any(bun_mount not in line or bun_env not in line for line in opencode):
    raise SystemExit("every OpenCode task/auth path must receive the exact Bun tmpfs and BUN_TMPDIR")
if any("BUN_TMPDIR" in line or "/run/opencode-bun-tmp" in line for line in other):
    raise SystemExit("Codex/offline path receives OpenCode executable temporary storage")
if any("target=/run/opencode-bun-tmp" in line for line in opencode):
    raise SystemExit("Bun tmpdir is backed by a volume or bind mount")
print("PASS: /tmp is noexec; only both OpenCode paths receive the private executable Bun tmpfs")
PY

# Managed configuration is baked root-owned/read-only, and automatic updates,
# default plugins, LSP downloads, and project configuration are disabled.
grep -q 'COPY config/opencode-managed.json /etc/opencode/opencode.json' "$root/images/opencode.Dockerfile" \
  || fail "managed OpenCode configuration is not baked into the image"
for token in \
  'OPENCODE_DISABLE_AUTOUPDATE=true' \
  'OPENCODE_DISABLE_DEFAULT_PLUGINS=true' \
  'OPENCODE_DISABLE_LSP_DOWNLOAD=true' \
  'OPENCODE_DISABLE_PROJECT_CONFIG=1'; do
  grep -qF "$token" "$root/images/opencode.Dockerfile" \
    || fail "opencode.Dockerfile environment is missing: $token"
done

# OPENCODE_DISABLE_PROJECT_CONFIG=1 must be present on every OpenCode container
# creation path in the launcher (task sessions AND authentication containers),
# and on no Codex/offline path.
python3 - "$root/bin/sandboxctl" <<'PY'
import re
import sys

text = open(sys.argv[1]).read()

logical = []
pending = ""
for line in text.splitlines():
    combined = f"{pending} {line.strip()}" if pending else line
    if combined.rstrip().endswith("\\"):
        pending = combined.rstrip()[:-1]
    else:
        logical.append(combined)
        pending = ""

creates = [c for c in logical if re.search(r'\bdocker create\b', c)]
opencode_creates = [c for c in creates if "PROJECT_OPENCODE_IMAGE" in c]
other_creates = [c for c in creates if "PROJECT_OPENCODE_IMAGE" not in c]

flag = "--env OPENCODE_DISABLE_PROJECT_CONFIG=1"
if not opencode_creates:
    raise SystemExit("no OpenCode container creation paths found")
for c in opencode_creates:
    if flag not in c:
        raise SystemExit("OpenCode container creation path without " + flag)
for c in other_creates:
    if "OPENCODE_DISABLE_PROJECT_CONFIG" in c:
        raise SystemExit("non-OpenCode container path sets OPENCODE_DISABLE_PROJECT_CONFIG")

print(f"PASS: all {len(opencode_creates)} OpenCode container paths set OPENCODE_DISABLE_PROJECT_CONFIG=1")

# The image ENTRYPOINT must be replaced exactly once per OpenCode creation
# path via --entrypoint placed before the image name; an entrypoint script
# appearing after the image name would run as an ordinary argument on top of
# the baked-in entrypoint.
task_entrypoint = "--entrypoint /usr/local/bin/start-opencode-session"
auth_entrypoint = "--entrypoint /usr/local/bin/start-opencode-auth-session"
for c in opencode_creates:
    if c.count("--entrypoint") != 1:
        raise SystemExit("OpenCode container creation path without exactly one --entrypoint")
    if task_entrypoint not in c and auth_entrypoint not in c:
        raise SystemExit("OpenCode container creation path selects no known entrypoint script")
    after_image = c.split('"$PROJECT_OPENCODE_IMAGE"', 1)[1]
    if "start-opencode" in after_image or "--entrypoint" in after_image:
        raise SystemExit("OpenCode container creation path passes an entrypoint selection after the image")
print(f"PASS: all {len(opencode_creates)} OpenCode container paths pass exactly one --entrypoint before the image")

# Task containers (read-only auth mount) select start-opencode-session;
# authentication containers select start-opencode-auth-session.
task_paths = [c for c in opencode_creates if "/auth,readonly" in c]
auth_paths = [c for c in opencode_creates if "/auth,readonly" not in c]
if not task_paths or not auth_paths:
    raise SystemExit("expected both task and authentication OpenCode creation paths")
for c in task_paths:
    if task_entrypoint not in c:
        raise SystemExit("task session does not select start-opencode-session via --entrypoint")
print(f"PASS: all {len(task_paths)} task paths select start-opencode-session")
for c in auth_paths:
    if auth_entrypoint not in c:
        raise SystemExit("authentication container does not select start-opencode-auth-session via --entrypoint")
print(f"PASS: all {len(auth_paths)} authentication paths select start-opencode-auth-session")
PY

# Normal task sessions must use `opencode --pure`.
grep -q 'run_opencode_command create_opencode_container true \\' "$root/bin/sandboxctl" \
  || fail "run-opencode does not route through the task-session container creator"
grep -qE 'opencode --pure "\$\@"' "$root/bin/sandboxctl" \
  || fail "task sessions do not run opencode with --pure"

# Forwarded commands remain intact after the entrypoint fix.
grep -q 'run_opencode_command create_opencode_container true bash' "$root/bin/sandboxctl" \
  || fail "shell-opencode does not forward bash through the task-session container"
grep -q 'run_opencode_command create_opencode_container false "\$@"' "$root/bin/sandboxctl" \
  || fail "exec-opencode does not forward arbitrary commands through the task-session container"
grep -q 'run_opencode_command create_opencode_login_container true \\' "$root/bin/sandboxctl" \
  || fail "login-opencode does not route through the authentication container creator"
for forwarded in 'opencode auth login' 'opencode auth list' 'opencode auth logout'; do
  grep -qF "$forwarded" "$root/bin/sandboxctl" \
    || fail "authentication command not forwarded: $forwarded"
done

# Task sessions mount the auth volume read-only; login containers mount it
# read-write.
grep -q 'target=/auth,readonly' "$root/bin/sandboxctl" \
  || fail "task sessions do not mount the auth volume read-only"

# The adapter deliberately excludes the reference implementation's runtime
# instruction-file guard architecture and kernel-enforcement mechanisms.
for forbidden in instruction-guard guarded-run 'LD_PRELOAD' ptrace 'seccomp'; do
  ! grep -RIl "$forbidden" "$root/bin" "$root/container" "$root/images" "$root/config" >/dev/null \
    || fail "excluded mechanism present in kit files: $forbidden"
done
! find "$root" -path "$root/.git" -prune -o -type f -name 'instruction-guard*' -print | grep -q . \
  || fail "instruction-guard file exists"
echo "PASS: no instruction-guard, polling, or kernel-enforcement mechanisms are present"

! grep -RIn 'REPLACE_PROJECT_SLUG\|include_apps_instructions\|/mnt/c/Users/example/Documents/Example-Workspace/2026-' "$root" \
  --exclude-dir=.git --exclude=static.sh \
  || fail "stale placeholder found"
! grep -RIn --exclude-dir=.git --exclude=static.sh -- '--ignore-user-config\|--ignore-rules' "$root" \
  || fail "unsupported flag found"

# Naming taxonomy: agent implementations are explicit, shared boundary pieces
# remain neutral, and the pre-2.0.2 generic Codex names may not return.
[[ ! -e "$root/tests/smoke.sh" ]] \
  || fail "tests/smoke.sh returned; the Codex smoke test is smoke-codex.sh"
for required in \
  tests/smoke-codex.sh images/codex-networked.Dockerfile \
  config/codex-config.toml config/codex-requirements.toml \
  container/check-codex-networked.sh \
  container/check-codex-login.sh container/run-with-codex-auth.sh \
  container/start-codex-auth-session.sh container/start-codex-session.sh \
  tests/opencode-control-flow.sh tests/opencode-command-reachability.sh; do
  [[ -f "$root/$required" ]] || fail "agent-specific file is missing or ambiguously named: $required"
done
for obsolete in \
  images/networked.Dockerfile config/config.toml config/requirements.toml \
  container/check-networked.sh container/check-login.sh \
  container/run-with-project-auth.sh container/start-auth-session.sh \
  container/start-networked-session.sh tests/control-flow.sh \
  tests/command-reachability.sh; do
  [[ ! -e "$root/$obsolete" ]] || fail "ambiguous agent-specific filename returned: $obsolete"
done
for shared in \
  images/offline.Dockerfile container/check-common.sh \
  container/check-offline.sh container/prune-auth-volume.sh \
  container/start-offline-session.sh tests/smoke-safety.sh; do
  [[ -f "$root/$shared" ]] || fail "shared component was incorrectly classified as agent-specific: $shared"
done
! grep -RInF 'tests/smoke.sh' "$root/README.md" "$root/docs" >/dev/null \
  || fail "documentation references the old Codex smoke-test name"
! grep -RInE 'sbx (run|login|auth-status|logout|doctor|shell|exec|reset-auth)([[:space:]`]|$)' \
  "$root/README.md" "$root/docs" >/dev/null \
  || fail "agent-specific public command omits the agent"
echo "PASS: repository naming taxonomy and canonical public commands are explicit"

# The Docker smoke test must take its image tag from versions.lock and must
# inspect the real auth volume (mounted read-only) during final inspection,
# not the image's empty /auth directory.
grep -qF 'IMAGE="$(read_lock_value OPENCODE_IMAGE)"' "$root/tests/smoke-opencode.sh" \
  || fail "smoke-opencode.sh does not read OPENCODE_IMAGE from versions.lock"
! grep -qF 'local/codex-sandbox-opencode:${KIT_VERSION_LOCK}' "$root/tests/smoke-opencode.sh" \
  || fail "smoke-opencode.sh still constructs the image tag from KIT_VERSION"
grep -qF 'type=volume,source=${volume},target=/auth,readonly' "$root/tests/smoke-opencode.sh" \
  || fail "smoke-opencode.sh final auth inspection does not mount the volume read-only"

# Documentation command names must match the launcher.
launcher_commands="$(
  sed -n 's/^    \([a-z][a-z-]*\)) cmd_.*/\1/p' "$root/bin/sandboxctl" | sort -u
)"
while IFS= read -r doc_cmd; do
  [[ -z "$doc_cmd" ]] && continue
  grep -qx "$doc_cmd" <<<"$launcher_commands" \
    || fail "documentation mentions unknown command: sandboxctl $doc_cmd"
done < <(
  grep -rhoE 'sandboxctl [a-z][a-z-]+' "$root/README.md" "$root/docs" 2>/dev/null \
    | sed 's/^sandboxctl //' | sort -u
)

printf 'RESULT: static checks passed\n'
