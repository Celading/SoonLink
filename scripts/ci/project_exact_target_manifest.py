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
    parser.add_argument("--cangjie-llvm-bin", type=pathlib.Path)
    parser.add_argument("--ohos-llvm-bin", type=pathlib.Path)
    parser.add_argument("--ohos-sysroot", type=pathlib.Path)
    parser.add_argument("--ohos-target-lib", type=pathlib.Path)
    parser.add_argument("--ohos-llvm-target-lib", type=pathlib.Path)
    return parser.parse_args()


def section_target(section: str) -> str | None:
    if not section.startswith("target."):
        return None
    return section[len("target.") :].split(".", 1)[0]


def ohos_compile_option(args: argparse.Namespace) -> str | None:
    if not args.ohos_sysroot:
        return None
    if "linux-ohos" not in args.target:
        raise SystemExit("OHOS compile paths were supplied for a non-OHOS target")
    if not args.cangjie_llvm_bin or not args.ohos_llvm_bin:
        raise SystemExit("Cangjie and OpenHarmony LLVM paths are required for OHOS projection")
    arch = "aarch64" if "aarch64" in args.target else "x86_64"
    sysroot_target_lib = args.ohos_sysroot / "usr" / "lib" / f"{arch}-linux-ohos"
    parts = [
        f'-B "{args.cangjie_llvm_bin}"',
        f'-B "{args.ohos_llvm_bin}"',
        f'-B "{sysroot_target_lib}"',
        f'-L "{sysroot_target_lib}"',
    ]
    if args.ohos_target_lib and args.ohos_target_lib != sysroot_target_lib:
        parts.append(f'-L "{args.ohos_target_lib}"')
    if args.ohos_llvm_target_lib:
        parts.append(f'-L "{args.ohos_llvm_target_lib}"')
    parts.append(f'--sysroot "{args.ohos_sysroot}"')
    return "  compile-option = \"" + " ".join(parts).replace('"', '\\"') + "\"\n"


def project_manifest(path: pathlib.Path, args: argparse.Namespace) -> list[str]:
    target = args.target
    original = path.read_text(encoding="utf-8")
    output: list[str] = []
    removed: list[str] = []
    keep_section = True
    active_section = ""
    rewritten_compile_option = False
    replacement = ohos_compile_option(args)

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
                active_section = section
            else:
                active_section = ""
        if (
            keep_section
            and replacement
            and active_section == f"target.{target}"
            and re.match(r"^\s*compile-option\s*=", line)
        ):
            output.append(replacement)
            rewritten_compile_option = True
            continue
        if keep_section:
            output.append(line)

    if replacement and not rewritten_compile_option:
        base_section = f"target.{target}"
        base_header_index: int | None = None
        first_nested_index: int | None = None
        for index, line in enumerate(output):
            match = HEADER_PATTERN.match(line.rstrip("\r\n"))
            if not match:
                continue
            section = match.group(1).strip()
            if section == base_section:
                base_header_index = index
                break
            if section.startswith(base_section + ".") and first_nested_index is None:
                first_nested_index = index

        if base_header_index is not None:
            output.insert(base_header_index + 1, replacement)
        else:
            insertion = [f"[target.{target}]\n", replacement, "\n"]
            if first_nested_index is not None:
                output[first_nested_index:first_nested_index] = insertion
            else:
                if output and output[-1].strip():
                    output.append("\n")
                output.extend(insertion)

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
        removed = project_manifest(manifest, args)
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
                "ohosCompileOptionRewritten": bool(
                    args.ohos_sysroot and "linux-ohos" in args.target
                ),
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
