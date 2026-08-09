#!/usr/bin/env python3
"""Keep only the selected Cangjie target tables in projected manifests."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import tempfile


HEADER_PATTERN = re.compile(r"^\s*\[([^\]]+)\]\s*(?:#.*)?$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=pathlib.Path)
    parser.add_argument("--target", required=True)
    parser.add_argument("--receipt", required=True, type=pathlib.Path)
    return parser.parse_args()


def section_target(section: str) -> str | None:
    if not section.startswith("target."):
        return None
    return section[len("target.") :].split(".", 1)[0]


def project_manifest(path: pathlib.Path, target: str) -> list[str]:
    original = path.read_text(encoding="utf-8")
    output: list[str] = []
    removed: list[str] = []
    keep_section = True

    for line in original.splitlines(keepends=True):
        match = HEADER_PATTERN.match(line.rstrip("\r\n"))
        if match:
            section = match.group(1).strip()
            selected_target = section_target(section)
            if selected_target is None:
                keep_section = True
            else:
                keep_section = selected_target == target
                if not keep_section:
                    removed.append(section)
        if keep_section:
            output.append(line)

    projected = "".join(output)
    if projected != original:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            delete=False,
        ) as temporary:
            temporary.write(projected)
            temporary_path = pathlib.Path(temporary.name)
        temporary_path.replace(path)
    return removed


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    if not root.is_dir():
        raise SystemExit(f"projection root not found: {root}")

    manifests = []
    for manifest in sorted(root.rglob("cjpm.toml")):
        relative = manifest.relative_to(root)
        if any(part in {".git", "target", "build", "dist"} for part in relative.parts):
            continue
        removed = project_manifest(manifest, args.target)
        manifests.append(
            {
                "manifest": str(relative),
                "removedTargetSections": removed,
            }
        )

    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    args.receipt.write_text(
        json.dumps(
            {
                "schema": "soonlink-exact-target-projection-receipt-v1",
                "ok": True,
                "target": args.target,
                "projectionRoot": str(root),
                "manifests": manifests,
                "projectionManifestsMutated": any(
                    item["removedTargetSections"] for item in manifests
                ),
                "sourceCheckoutMutated": False,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
