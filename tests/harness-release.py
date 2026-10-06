#!/usr/bin/env python3
"""Registry and independent-lock validation for all three harness profiles."""
import base64
import importlib.util
import io
import pathlib
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("codex_release", ROOT / "bin/harness-release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
SRI = "sha512-" + base64.b64encode(bytes(range(64))).decode()


def metadata(selected="0.999.0", agent="codex"):
    wrapper_name, dependency, *_ = release.PROFILES[agent]
    platform_name = wrapper_name if agent == "codex" else dependency
    platform_version = selected + "-linux-x64" if agent == "codex" else selected
    mapping = f"npm:{wrapper_name}@{platform_version}" if agent == "codex" else selected
    wrapper = {"name": wrapper_name, "version": selected,
               "optionalDependencies": {dependency: mapping},
               "dist": {"integrity": SRI, "tarball": f"https://registry.npmjs.org/{wrapper_name}/-/{wrapper_name.rsplit('/',1)[-1]}-{selected}.tgz"}}
    platform = {"name": platform_name, "version": platform_version, "os": ["linux"], "cpu": ["x64"],
                "dist": {"integrity": SRI, "tarball": f"https://registry.npmjs.org/{platform_name}/-/{platform_name.rsplit('/',1)[-1]}-{platform_version}.tgz"}}
    return wrapper, platform


class RegistryTests(unittest.TestCase):
    def setUp(self):
        release.configure("codex")

    def resolve_pair(self, wrapper, platform, selector="latest"):
        with patch.object(release, "fetch", side_effect=[wrapper, platform]):
            return release.resolve(selector)

    def test_latest_and_exact_version(self):
        expected = dict(zip(release.KEYS, ("0.999.0", SRI, SRI)))
        self.assertEqual(self.resolve_pair(*metadata()), expected)
        self.assertEqual(self.resolve_pair(*metadata(), "0.999.0"), expected)

    def test_newer_and_no_update(self):
        self.assertGreater(release.version("0.160.1"), release.version("0.156.1"))
        self.assertLess(release.version("0.9.0"), release.version("0.10.0"))
        self.assertEqual(release.version("0.160.1"), release.version("0.160.1"))

    def test_reject_nonstable_or_injected_versions(self):
        for value in [None, 160, "0.160.1-alpha.1", "0.160.1-linux-x64", "latest", "01.2.3", "0.1.0\nBAD=yes"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                release.version(value)
        with self.assertRaises(ValueError):
            self.resolve_pair(*metadata("0.999.0-alpha.1"))
        with self.assertRaises(ValueError):
            self.resolve_pair(*metadata(), "0.998.0")

    def test_wrapper_identity_mapping_and_dist(self):
        mutations = [lambda x: x.update(name="codex"), lambda x: x.pop("dist"),
                     lambda x: x["dist"].update(tarball="https://example.invalid/evil.tgz"),
                     lambda x: x["dist"].update(integrity="sha512-YQ=="),
                     lambda x: x.update(optionalDependencies={}),
                     lambda x: x["optionalDependencies"].update({"@openai/codex-linux-x64": "latest"})]
        for mutate in mutations:
            wrapper, platform = metadata()
            mutate(wrapper)
            with self.subTest(wrapper=wrapper), self.assertRaises(ValueError):
                self.resolve_pair(wrapper, platform)

    def test_platform_identity_architecture_and_integrity(self):
        for field, value in [("name", "other"), ("version", "0.999.0-linux-arm64"), ("os", ["darwin"]), ("cpu", ["arm64"])]:
            wrapper, platform = metadata()
            platform[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.resolve_pair(wrapper, platform)
        wrapper, platform = metadata()
        platform["dist"]["integrity"] = "sha256-deadbeef"
        with self.assertRaises(ValueError):
            self.resolve_pair(wrapper, platform)

    def test_integrity_encoding(self):
        for value in [None, "sha512-%%%", "sha512-YQ==", SRI + "\n", SRI.rstrip("=")]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                release.integrity(value)

    def test_network_error(self):
        with patch.object(release.REGISTRY_OPENER, "open", side_effect=OSError("offline")), self.assertRaises(OSError):
            release.resolve("latest")

    def test_other_harness_profiles_and_rejected_metadata(self):
        for agent in ("opencode", "claude"):
            release.configure(agent)
            values = self.resolve_pair(*metadata("9.999.0", agent))
            self.assertEqual(values[release.KEYS[0]], "9.999.0")
            for mutation in ("mapping", "name", "integrity", "libc", "dependencies", "peers"):
                wrapper, platform = metadata("9.999.0", agent)
                if mutation == "mapping":
                    wrapper["optionalDependencies"][release.PLATFORM_PACKAGE] = "^9.999.0"
                elif mutation == "name":
                    platform["name"] = "untrusted"
                elif mutation == "integrity":
                    platform["dist"]["integrity"] = "sha512-invalid"
                elif mutation == "libc":
                    platform["libc"] = ["musl"]
                elif mutation == "peers":
                    wrapper["peerDependencies"] = {"extra": "latest"}
                else:
                    wrapper["dependencies"] = {"extra": "latest"}
                with self.subTest(agent=agent, mutation=mutation), self.assertRaises(ValueError):
                    self.resolve_pair(wrapper, platform)

    def test_other_harness_locks_and_baseline_supersession(self):
        for agent in ("opencode", "claude"):
            release.configure(agent)
            with tempfile.TemporaryDirectory() as work:
                root = pathlib.Path(work)
                for folder in ("config", "container", "images"):
                    (root / folder).mkdir()
                baseline = dict(zip(release.KEYS, ("1.0.0", SRI, SRI)))
                (root / "versions.lock").write_text("KIT_VERSION=3.3.0\n" + "".join(f"{key}={value}\n" for key, value in baseline.items()))
                (root / f"images/{release.DOCKERFILE}.Dockerfile").write_text("fixture")
                selected = dict(zip(release.KEYS, ("9.999.0", SRI, SRI)))
                lock = root / f"{agent}-release.lock"
                lock.write_text("".join(f"{key}={value}\n" for key, value in selected.items()))
                effective = release.effective_lock(root, lock)
                self.assertIn(f"-{agent}-9.999.0-", effective[release.IMAGE_KEY])
                (root / "versions.lock").write_text((root / "versions.lock").read_text().replace("1.0.0", "10.0.0"))
                self.assertEqual(release.effective_lock(root, lock), {})
                # A different harness's keys cannot override this profile.
                lock.write_text(lock.read_text().replace(release.KEYS[0], "CODEX_VERSION"))
                with self.assertRaises(ValueError):
                    release.read_lock(lock)

    def test_unpinned_dependencies_are_rejected_for_every_harness(self):
        for agent in release.PROFILES:
            release.configure(agent)
            for key in ("dependencies", "peerDependencies"):
                for target in (0, 1):
                    pair = metadata("9.999.0", agent)
                    pair[target][key] = {"extra": "latest"}
                    with self.subTest(agent=agent, key=key, target=target), self.assertRaises(ValueError):
                        self.resolve_pair(*pair)

    def test_malformed_nonobject_or_oversized_response(self):
        for payload in [b"not json", b"[]", b"x" * (1024 * 1024 + 1)]:
            response = io.BytesIO(payload)
            response.geturl = lambda: release.REGISTRY + "/@openai%2fcodex/latest"
            with patch.object(release.REGISTRY_OPENER, "open", return_value=response), self.assertRaises(ValueError):
                release.fetch("latest")

    def test_redirect_rejected(self):
        response = io.BytesIO(b"{}")
        response.geturl = lambda: "https://example.invalid"
        with patch.object(release.REGISTRY_OPENER, "open", return_value=response), self.assertRaises(ValueError):
            release.fetch("latest")

    def test_redirect_is_blocked_before_following(self):
        handler = release.RegistryRedirectHandler()
        with self.assertRaisesRegex(ValueError, "unexpected registry redirect"):
            handler.redirect_request(None, None, 302, "Found", {}, "https://example.invalid")

    def test_lock_validation_and_image_fingerprint(self):
        with tempfile.TemporaryDirectory() as work:
            root = pathlib.Path(work)
            for folder in ["config", "container", "images"]:
                (root / folder).mkdir()
            (root / "versions.lock").write_text(f"KIT_VERSION=3.3.0\nCODEX_VERSION=0.156.1\nCODEX_PACKAGE_INTEGRITY={SRI}\nCODEX_LINUX_X64_INTEGRITY={SRI}\n")
            (root / "images/codex-networked.Dockerfile").write_text("fixture")
            lock = root / "codex-release.lock"
            lock.write_text(f"CODEX_VERSION=0.999.0\nCODEX_PACKAGE_INTEGRITY={SRI}\nCODEX_LINUX_X64_INTEGRITY={SRI}\n")
            image = release.effective_lock(root, lock)["NETWORK_IMAGE"]
            self.assertEqual(image, release.effective_lock(root, lock)["NETWORK_IMAGE"])
            (root / "config/codex-config.toml").write_text("new configuration")
            self.assertNotEqual(image, release.effective_lock(root, lock)["NETWORK_IMAGE"])
            original = lock.read_text()
            for addition in ["BAD=yes\n", "CODEX_VERSION=0.999.0\n"]:
                lock.write_text(original + addition)
                with self.assertRaises(ValueError):
                    release.read_lock(lock)
            lock.write_text(original.replace("0.999.0", "0.155.0"))
            self.assertEqual(release.effective_lock(root, lock), {})
            lock.write_text(original.replace("0.999.0", "0.156.1"))
            self.assertEqual(release.effective_lock(root, lock), {})
            lock.write_text(lock.read_text().replace(SRI, "sha512-" + base64.b64encode(b"x" * 64).decode()))
            with self.assertRaises(ValueError):
                release.effective_lock(root, lock)


if __name__ == "__main__":
    unittest.main()
