#!/usr/bin/env python3
"""Resolve and validate published harness npm releases; never install packages."""

import argparse
import base64
import binascii
import hashlib
import json
import pathlib
import re
import sys
import urllib.request

REGISTRY = "https://registry.npmjs.org"
PACKAGE = "@openai/codex"
KEYS = ("CODEX_VERSION", "CODEX_PACKAGE_INTEGRITY", "CODEX_LINUX_X64_INTEGRITY")
PROFILES = {
    "codex": ("@openai/codex", "@openai/codex-linux-x64", "CODEX", "NETWORK_IMAGE", "codex-networked", "networked"),
    "opencode": ("opencode-ai", "opencode-linux-x64", "OPENCODE", "OPENCODE_IMAGE", "opencode", "opencode"),
    "claude": ("@anthropic-ai/claude-code", "@anthropic-ai/claude-code-linux-x64", "CLAUDE", "CLAUDE_IMAGE", "claude", "claude"),
}


def configure(agent):
    global AGENT, PACKAGE, PLATFORM_PACKAGE, KEYS, IMAGE_KEY, DOCKERFILE, IMAGE_NAME
    AGENT = agent
    PACKAGE, PLATFORM_PACKAGE, prefix, IMAGE_KEY, DOCKERFILE, IMAGE_NAME = PROFILES[agent]
    KEYS = (prefix + "_VERSION", prefix + "_PACKAGE_INTEGRITY", prefix + "_LINUX_X64_INTEGRITY")


configure("codex")


class RegistryRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        raise ValueError("unexpected registry redirect")


REGISTRY_OPENER = urllib.request.build_opener(RegistryRedirectHandler())


def version(value):
    if not isinstance(value, str) or not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", value):
        raise ValueError("expected an exact stable major.minor.patch version")
    return tuple(map(int, value.split(".")))


def integrity(value):
    if not isinstance(value, str) or not value.startswith("sha512-"):
        raise ValueError("missing SHA-512 integrity")
    try:
        digest = base64.b64decode(value[7:], validate=True)
    except (ValueError, binascii.Error) as exc:
        raise ValueError("invalid SHA-512 integrity") from exc
    if len(digest) != 64 or base64.b64encode(digest).decode() != value[7:]:
        raise ValueError("invalid SHA-512 integrity length or encoding")
    return value


def fetch(selector, package=None):
    package = package or PACKAGE
    url = f"{REGISTRY}/{package.replace('/', '%2f')}/{selector}"
    request = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "agent-sandbox-kit"})
    with REGISTRY_OPENER.open(request, timeout=5) as response:
        if response.geturl() != url:
            raise ValueError("unexpected registry redirect")
        body = response.read(1024 * 1024 + 1)
    if len(body) > 1024 * 1024:
        raise ValueError("registry response exceeds size limit")
    data = json.loads(body)
    if not isinstance(data, dict):
        raise ValueError("registry metadata must be an object")
    return data


def validate_metadata(data, expected, package=None):
    package = package or PACKAGE
    if data.get("name") != package or data.get("version") != expected:
        raise ValueError("registry package identity/version mismatch")
    dist = data.get("dist")
    if not isinstance(dist, dict):
        raise ValueError("registry metadata is missing dist")
    filename = package.rsplit("/", 1)[-1]
    if dist.get("tarball") != f"{REGISTRY}/{package}/-/{filename}-{expected}.tgz":
        raise ValueError("unexpected package tarball URL")
    return integrity(dist.get("integrity"))


def resolve(selector):
    if selector != "latest":
        version(selector)
    wrapper = fetch(selector)
    selected = wrapper.get("version")
    version(selected)  # reject alpha/beta/platform tags, including a malformed latest tag
    if selector != "latest" and selected != selector:
        raise ValueError("requested version differs from registry response")
    wrapper_integrity = validate_metadata(wrapper, selected)
    dependencies = wrapper.get("optionalDependencies", {})
    mapping = f"npm:{PACKAGE}@{selected}-linux-x64" if AGENT == "codex" else selected
    if not isinstance(dependencies, dict) or dependencies.get(PLATFORM_PACKAGE) != mapping:
        raise ValueError("unsupported Linux x64 dependency mapping")
    if wrapper.get("dependencies") or wrapper.get("peerDependencies"):
        raise ValueError("unsupported additional wrapper dependencies")
    platform_version = f"{selected}-linux-x64" if AGENT == "codex" else selected
    platform_package = PACKAGE if AGENT == "codex" else PLATFORM_PACKAGE
    platform = fetch(platform_version, platform_package)
    platform_integrity = validate_metadata(platform, platform_version, platform_package)
    if platform.get("os") != ["linux"] or platform.get("cpu") != ["x64"]:
        raise ValueError("platform metadata is not Linux x64")
    if platform.get("libc") not in (None, ["glibc"]):
        raise ValueError("platform metadata is not compatible with the glibc image")
    if platform.get("dependencies") or platform.get("peerDependencies"):
        raise ValueError("unsupported additional platform dependencies")
    return dict(zip(KEYS, (selected, wrapper_integrity, platform_integrity)))


def read_lock(path):
    values = {}
    for line in path.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator or key not in KEYS or key in values:
            raise ValueError("invalid or duplicate harness release lock key")
        values[key] = value
    if set(values) != set(KEYS):
        raise ValueError("incomplete harness release lock")
    version(values[KEYS[0]])
    integrity(values[KEYS[1]])
    integrity(values[KEYS[2]])
    return values


def effective_lock(root, path):
    values = read_lock(path)
    baseline = dict(line.split("=", 1) for line in (root / "versions.lock").read_text().splitlines()
                    if line and not line.startswith("#"))
    if version(values[KEYS[0]]) < version(baseline[KEYS[0]]):
        return {}  # a newer kit baseline supersedes an older local selection
    if values[KEYS[0]] == baseline[KEYS[0]]:
        if any(values[key] != baseline[key] for key in KEYS):
            raise ValueError("release integrity differs from the kit's pin for the same version")
        return {}
    # Distinct tags retain old images and change when baked configuration changes,
    # even if a maintainer did not bump KIT_VERSION.
    digest = hashlib.sha256()
    paths = [root / "versions.lock", root / f"images/{DOCKERFILE}.Dockerfile"]
    paths += sorted((root / "config").rglob("*")) + sorted((root / "container").rglob("*"))
    for item in paths:
        if item.is_file():
            digest.update(item.relative_to(root).as_posix().encode() + b"\0" + item.read_bytes())
    digest.update(json.dumps(values, sort_keys=True).encode())
    values[IMAGE_KEY] = f"local/codex-sandbox-{IMAGE_NAME}:{baseline['KIT_VERSION']}-{AGENT}-{values[KEYS[0]]}-{digest.hexdigest()[:16]}"
    return values


def emit(values):
    for key, value in values.items():
        print(f"{key}={value}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent", choices=PROFILES, default="codex")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("resolve").add_argument("selector", nargs="?", default="latest")
    load = commands.add_parser("load")
    load.add_argument("root", type=pathlib.Path)
    load.add_argument("lock", type=pathlib.Path)
    compare = commands.add_parser("newer")
    compare.add_argument("candidate")
    compare.add_argument("current")
    args = parser.parse_args()
    configure(args.agent)
    try:
        if args.command == "resolve":
            emit(resolve(args.selector))
        elif args.command == "load":
            emit(effective_lock(args.root, args.lock))
        else:
            return 0 if version(args.candidate) > version(args.current) else 1
    except (ValueError, OSError, KeyError, TypeError) as exc:
        print(f"ERROR: {AGENT} release metadata unavailable or invalid: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
