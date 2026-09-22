#!/usr/bin/env python3
"""Resolve an approved release manifest into a host-only `images.env`.

Reads a release manifest (see `deploy/releases/README.md`) and writes the
digest-pinned Compose image pins consumed by `deploy/compose.yaml`:

    WEB_IMAGE=ghcr.io/<owner>/<repo>@sha256:<64 hex>
    API_IMAGE=ghcr.io/<owner>/<repo>@sha256:<64 hex>

Only immutable `@sha256:` references are accepted. Mutable tags, malformed
registry references, missing image entries, and unexpected schema versions are
rejected. The output contains exactly the two pins and nothing else.

No network access is performed: the approved manifest is the source of truth.
This helper prepares metadata only; it never deploys anything.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

SCHEMA_VERSION = 1

# Registry reference without a tag: registry component plus at least one path
# component (e.g. `ghcr.io/owner/repo`). A `:` is deliberately not allowed, so
# mutable tag references cannot slip through.
_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*(?:/[A-Za-z0-9._-]+)+$")
_DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")


class ManifestError(ValueError):
    """Raised when a release manifest is missing, malformed, or unsafe."""


def read_manifest(path: Path) -> dict:
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as error:
        raise ManifestError(f"cannot read manifest {path}: {error}") from error
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as error:
        raise ManifestError(f"manifest is not valid JSON: {error}") from error
    if not isinstance(data, dict):
        raise ManifestError("manifest must be a JSON object")
    return data


def require_digest_ref(value: object, field: str) -> str:
    if not isinstance(value, str) or not value:
        raise ManifestError(f"{field} is missing")
    if value.count("@") != 1:
        raise ManifestError(
            f"{field} must be an immutable '@sha256:<digest>' reference, got: {value}"
        )
    name, digest = value.split("@", 1)
    if ":" in name:
        raise ManifestError(f"{field} must not contain a mutable tag, got: {value}")
    if not _NAME_RE.match(name):
        raise ManifestError(f"{field} has a malformed registry reference: {value}")
    if not _DIGEST_RE.match(digest):
        raise ManifestError(f"{field} must end with 'sha256:<64 lowercase hex>': {value}")
    return value


def image_ref(images: dict, key: str) -> str:
    entry = images.get(key)
    if not isinstance(entry, dict):
        raise ManifestError(f"images.{key} is missing")
    return require_digest_ref(entry.get("ref"), f"images.{key}.ref")


def resolve(manifest: dict) -> dict:
    version = manifest.get("schemaVersion")
    if version != SCHEMA_VERSION:
        raise ManifestError(f"unsupported schemaVersion {version!r}; expected {SCHEMA_VERSION}")
    images = manifest.get("images")
    if not isinstance(images, dict):
        raise ManifestError("images is missing")
    return {
        "WEB_IMAGE": image_ref(images, "web"),
        "API_IMAGE": image_ref(images, "api"),
    }


def render(pins: dict) -> str:
    """Exactly the two image pins, in a stable order, and nothing else."""
    return f"WEB_IMAGE={pins['WEB_IMAGE']}\nAPI_IMAGE={pins['API_IMAGE']}\n"


def main(argv: list) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path, help="approved release manifest (JSON)")
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("images.env"),
        help="output file (default: ./images.env; host-only, git-ignored)",
    )
    args = parser.parse_args(argv)
    try:
        pins = resolve(read_manifest(args.manifest))
        content = render(pins)
    except ManifestError as error:
        print(f"resolve-release-manifest: {error}", file=sys.stderr)
        return 1
    try:
        args.out.write_text(content, encoding="utf-8")
    except OSError as error:
        print(f"resolve-release-manifest: cannot write {args.out}: {error}", file=sys.stderr)
        return 1
    print(f"resolve-release-manifest: wrote {args.out} ({pins['WEB_IMAGE']} / {pins['API_IMAGE']})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
