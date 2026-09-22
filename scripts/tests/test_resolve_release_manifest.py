#!/usr/bin/env python3
"""Deterministic, network-free tests for resolve_release_manifest.py."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = SCRIPTS_DIR.parent
SCRIPT = SCRIPTS_DIR / "resolve_release_manifest.py"
EXAMPLE_MANIFEST = REPO_ROOT / "deploy" / "releases" / "example-release.json"

WEB_REF = "ghcr.io/example/smshop-web@sha256:" + "a" * 64
API_REF = "ghcr.io/example/smshop-api@sha256:" + "b" * 64
TAG = "sha-" + "0" * 40


def valid_manifest() -> dict:
    return {
        "schemaVersion": 1,
        "createdAt": "2026-09-22T00:00:00Z",
        "source": {"repository": "github.com/example/smshop", "commit": "0" * 40, "ref": "main"},
        "ci": {"imagesRunId": "1"},
        "images": {
            "web": {"ref": WEB_REF, "platform": "linux/arm64", "tag": TAG},
            "api": {"ref": API_REF, "platform": "linux/arm64", "tag": TAG},
        },
    }


class ResolveReleaseManifestTest(unittest.TestCase):
    def invoke(self, manifest_text: str, manifest_name: str = "release.json"):
        """Run the resolver CLI against text and return (result, output-file-text)."""
        with tempfile.TemporaryDirectory() as tmp:
            manifest_path = Path(tmp) / manifest_name
            out_path = Path(tmp) / "images.env"
            manifest_path.write_text(manifest_text, encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(SCRIPT), str(manifest_path), "--out", str(out_path)],
                capture_output=True,
                text=True,
            )
            output = out_path.read_text(encoding="utf-8") if out_path.exists() else None
            return result, output

    def test_valid_manifest_writes_exact_pins(self):
        result, output = self.invoke(json.dumps(valid_manifest()))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output, f"WEB_IMAGE={WEB_REF}\nAPI_IMAGE={API_REF}\n")
        # Exactly two lines, no comments or unrelated configuration.
        self.assertEqual(len(output.splitlines()), 2)
        self.assertNotIn("#", output)

    def test_mutable_tag_rejected(self):
        manifest = valid_manifest()
        manifest["images"]["web"]["ref"] = "ghcr.io/example/smshop-web:latest"
        result, output = self.invoke(json.dumps(manifest))
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(output)

    def test_tag_and_digest_rejected(self):
        manifest = valid_manifest()
        manifest["images"]["api"]["ref"] = f"ghcr.io/example/smshop-api:sha-abc@sha256:{'b' * 64}"
        result, output = self.invoke(json.dumps(manifest))
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(output)

    def test_missing_digest_rejected(self):
        manifest = valid_manifest()
        manifest["images"]["web"]["ref"] = "ghcr.io/example/smshop-web"
        result, output = self.invoke(json.dumps(manifest))
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(output)

    def test_short_digest_rejected(self):
        manifest = valid_manifest()
        manifest["images"]["web"]["ref"] = "ghcr.io/example/smshop-web@sha256:abc123"
        result, output = self.invoke(json.dumps(manifest))
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(output)

    def test_malformed_registry_ref_rejected(self):
        manifest = valid_manifest()
        manifest["images"]["web"]["ref"] = "ghcr.io@sha256:" + "a" * 64
        result, output = self.invoke(json.dumps(manifest))
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(output)

    def test_wrong_schema_version_rejected(self):
        manifest = valid_manifest()
        manifest["schemaVersion"] = 2
        result, output = self.invoke(json.dumps(manifest))
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(output)

    def test_missing_web_image_rejected(self):
        manifest = valid_manifest()
        del manifest["images"]["web"]
        result, output = self.invoke(json.dumps(manifest))
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(output)

    def test_missing_api_image_rejected(self):
        manifest = valid_manifest()
        del manifest["images"]["api"]
        result, output = self.invoke(json.dumps(manifest))
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(output)

    def test_missing_images_object_rejected(self):
        manifest = valid_manifest()
        del manifest["images"]
        result, output = self.invoke(json.dumps(manifest))
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(output)

    def test_malformed_json_rejected(self):
        result, output = self.invoke('{"schemaVersion": 1, "images": ')
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(output)

    def test_committed_example_manifest_resolves(self):
        with tempfile.TemporaryDirectory() as tmp:
            out_path = Path(tmp) / "images.env"
            result = subprocess.run(
                [sys.executable, str(SCRIPT), str(EXAMPLE_MANIFEST), "--out", str(out_path)],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            content = out_path.read_text(encoding="utf-8")
        self.assertEqual(len(content.splitlines()), 2)
        for line in content.splitlines():
            self.assertRegex(line, r"^(WEB_IMAGE|API_IMAGE)=ghcr\.io/.+@sha256:[0-9a-f]{64}$")


if __name__ == "__main__":
    unittest.main(verbosity=2)
