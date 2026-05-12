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
# 109 cycle-27 surface picks (8 Algo + 20 ComplexModule + 74
# OrderedCollections + 7 PropertyLawKit per surface-counts.md).

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
