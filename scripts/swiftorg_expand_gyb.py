#!/usr/bin/env python3
"""Expand a corpus's `.gyb` templates into real Swift, so `discover` can see them.

**Study tooling, deliberately not a product feature.** `FunctionScanner` cannot parse a
`.gyb` file — it is not valid Swift — and in `swift` that blind spot is concentrated
exactly where this study looks: `Float16/32/64`, the `SIMD` types and `IntegerTypes` are
declared ONLY in templates, and they are the carriers swift.org writes the most property
tests about.

Why this is not built into the scanner: of the six swift.org corpora checked on 2026-07-30,
**only `swift` uses gyb at all** (291 files; the other five have zero). It is a stdlib build
tool rather than an ecosystem pattern, so teaching the product to expand it would be
speculative surface for one corpus. Measuring what `discover` WOULD find is the useful part,
and that is what this does.

gyb needs the build's parameters. `CMAKE_SIZEOF_VOID_P` is the one the numeric templates
require; it is a 64-bit assumption, stated here rather than hidden, and it is why the output
is a *measurement aid* rather than the truth for every target.

Usage:
    scripts/swiftorg_expand_gyb.py --repo ~/GitHub_projects/swift \\
        --subdir stdlib/public/core --out /tmp/core-expanded
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--subdir", default="stdlib/public/core")
    parser.add_argument("--out", required=True)
    parser.add_argument(
        "--define", action="append", default=["CMAKE_SIZEOF_VOID_P=8"],
        help="gyb -D bindings; repeat for more (default assumes a 64-bit target)",
    )
    args = parser.parse_args()

    repo = os.path.abspath(os.path.expanduser(args.repo))
    source = os.path.join(repo, args.subdir)
    gyb = os.path.join(repo, "utils", "gyb.py")
    if not os.path.isfile(gyb):
        print(f"gyb not found at {gyb}", file=sys.stderr)
        return 1

    out = os.path.abspath(os.path.expanduser(args.out))
    os.makedirs(out, exist_ok=True)

    # Copy the hand-written Swift across unchanged, so the expanded tree is a superset and
    # a before/after `discover` diff isolates exactly the gyb contribution.
    copied = 0
    for name in sorted(os.listdir(source)):
        if name.endswith(".swift"):
            shutil.copy2(os.path.join(source, name), os.path.join(out, name))
            copied += 1

    expanded, failed = [], []
    for name in sorted(os.listdir(source)):
        if not name.endswith(".gyb"):
            continue
        target = os.path.join(out, name[: -len(".gyb")])
        command = [sys.executable, gyb, "--line-directive", ""]
        for define in args.define:
            command += ["-D", define]
        command += ["-o", target, os.path.join(source, name)]
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode == 0 and os.path.getsize(target) > 0:
            expanded.append(name)
        else:
            failed.append((name, (result.stderr or "").strip().split("\n")[-1][:110]))
            if os.path.exists(target):
                os.remove(target)

    print(f"copied {copied} .swift, expanded {len(expanded)} .gyb -> {out}")
    for name in expanded:
        print(f"  ok      {name}")
    for name, why in failed:
        print(f"  FAILED  {name}\n            {why}")
    # A partial expansion is still useful, and silence about the failures would not be.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
