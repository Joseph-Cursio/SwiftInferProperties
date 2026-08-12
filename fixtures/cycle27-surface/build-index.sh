#!/bin/bash
# V1.50.A — rebuilds the cycle27-surface fixture's merged SemanticIndex.
#
# Procedure:
#   1. Resolve fixture dependencies into .build/checkouts/.
#   2. Run `swift-infer index` against each of the 4 cycle-27 corpus
#      checkouts, persisting per-package indexes.
#   3. Merge the per-package indexes into a single
#      `.swiftinfer/index.json` at the fixture root, sorted by
#      identityHash for stable diffs.
#
# Requires:
#   - `swift-infer` binary at the repo root's `.build/debug/swift-infer`
#   - `jq` for the merge step.
#
# Output: `fixtures/cycle27-surface/.swiftinfer/index.json` with all
# **103** cycle-27 surface picks (8 Algo + 20 ComplexModule + 74
# OrderedCollections + 1 PropertyLawKit). V1.57.A (cycle-54)
# narrowed the count from the original v1.29-frozen 109 by filtering
# `private`/`fileprivate` declarations at scan time — dropped 6
# picks from PropertyLawKit (3 file-private helpers in
# *CollectionLaws.swift + 3 `private static` members of
# ViolationFormatter). See docs/calibration-cycle-54-findings.md.
#
# ── Diffing a sweep of this fixture: compare `outcome`, NOT `outcomeDetail` ──
#
# `verify --all-from-index` over this fixture is verdict-stable and detail-noisy.
# Two entries report a different FAILING TRIAL INDEX run to run, with the same
# binary and no source change:
#
#   0x0EE19DA4B456B0F5  associativity   trial=1 / trial=0
#   0xB8FE8FAB14F3C1A8  commutativity   trial=0 / trial=1 / trial=3
#
# Both stay `measured-defaultFails` every time, so this never surfaces as a
# pass/fail flake — only as movement in `outcomeDetail`.
#
# Measured 2026-08-12 while A/B-ing the round-trip domain-anchor fix (#236):
# three sweeps, the arm comparison showed exactly these two entries differing,
# and a SAME-BINARY control reproduced both. Without that control the honest
# reading was "the change perturbed two entries", and the search would have gone
# looking for a cause in `associativity`/`commutativity` — templates the change
# cannot reach. **Run the control arm before attributing any delta here.**
#
# Verdict tallies across all three sweeps: 39 bothPass, 6 defaultFails,
# 8 edgeCaseAdvisory, over 53 entries.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
FIXTURE_DIR="$REPO_ROOT/fixtures/cycle27-surface"
SWIFT_INFER="$REPO_ROOT/.build/debug/swift-infer"

if [[ ! -x "$SWIFT_INFER" ]]; then
    echo "Error: swift-infer not built. Run 'swift build' from $REPO_ROOT first." >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq not installed (brew install jq)." >&2
    exit 1
fi

cd "$FIXTURE_DIR"

# Step 1 — resolve SwiftPM deps.
echo "Resolving fixture dependencies..."
swift package resolve

# Step 2 — index each cycle-27 corpus checkout.
declare -A CORPORA=(
    ["swift-numerics"]="ComplexModule"
    ["swift-algorithms"]="Algorithms"
    ["swift-collections"]="OrderedCollections"
    ["SwiftPropertyLaws"]="PropertyLawKit"
)

for checkout in "${!CORPORA[@]}"; do
    target="${CORPORA[$checkout]}"
    echo "Indexing $checkout / $target ..."
    (cd "$FIXTURE_DIR/.build/checkouts/$checkout" && "$SWIFT_INFER" index --target "$target")
done

# Step 3 — merge into a single fixture-level index, sorted by identityHash.
mkdir -p "$FIXTURE_DIR/.swiftinfer"
echo "Merging per-corpus indexes..."
jq -s '{
    "entries": (map(.entries) | add | sort_by(.identityHash)),
    "schemaVersion": 3,
    "updatedAt": (.[0].updatedAt)
}' \
    "$FIXTURE_DIR/.build/checkouts/swift-numerics/.swiftinfer/index.json" \
    "$FIXTURE_DIR/.build/checkouts/swift-algorithms/.swiftinfer/index.json" \
    "$FIXTURE_DIR/.build/checkouts/swift-collections/.swiftinfer/index.json" \
    "$FIXTURE_DIR/.build/checkouts/SwiftPropertyLaws/.swiftinfer/index.json" \
    > "$FIXTURE_DIR/.swiftinfer/index.json"

count=$(jq '.entries | length' "$FIXTURE_DIR/.swiftinfer/index.json")
echo "Done. Merged index at $FIXTURE_DIR/.swiftinfer/index.json ($count entries)."
