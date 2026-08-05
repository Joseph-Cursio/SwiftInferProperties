#!/usr/bin/env bash
#
# Build a binary that can say where it came from.
#
# `BuildIdentity.commit` ships as "unattributable" on purpose — a plain `swift build`
# cannot know its own commit, and guessing would be a claim that looks like provenance
# and is not. This script is the deliberate act that earns the attribution: it writes the
# real SHA in, builds, and puts the file back.
#
#   ./scripts/stamp_build_identity.sh [--configuration release] [-- <extra swift build args>]
#
# ## Why a script and not a SwiftPM plugin
#
# A prebuild plugin is the textbook answer and was rejected: plugins run sandboxed,
# invoking `git` from one is unreliable across toolchains, and a mechanism that silently
# fails would reintroduce exactly the false attribution this exists to prevent. A visible
# edit that a `trap` reverses is worse engineering and better honesty.
#
# ## The dirty window
#
# Between the stamp and the restore, the working tree is modified. The trap restores it on
# ANY exit including a failed build or a Ctrl-C. If you find a stamped constant in
# `git status`, a stamped build was killed hard; `git checkout` the file.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITY_FILE="$REPO_ROOT/Sources/SwiftInferCore/BuildIdentity.swift"
CONFIGURATION="release"

while [ $# -gt 0 ]; do
    case "$1" in
        --configuration) CONFIGURATION="${2:-release}"; shift 2 ;;
        --) shift; break ;;
        *) printf 'usage: %s [--configuration <debug|release>] [-- <swift build args>]\n' "$0" >&2; exit 2 ;;
    esac
done

cd "$REPO_ROOT"

# A dirty tree means the SHA does not describe the source being compiled. Say so in the
# stamp rather than pretending — `a1b2c3d+dirty` is the truth and is still more useful
# than "unattributable", which is what the driver already prints for this case.
SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    SHA="${SHA}+dirty"
fi

# Restore from a COPY, not from git.
#
# The first version used `git checkout -- "$IDENTITY_FILE" || true`, which cannot restore an
# untracked file — and swallowed the failure, so the very first stamped build left the
# constant baked into the working tree while reporting success. A `|| true` on a restore is
# how a guard fires never. A copy works whether the file is tracked, untracked, or staged.
BACKUP="$(mktemp)"
cp "$IDENTITY_FILE" "$BACKUP"
restore() {
    cp "$BACKUP" "$IDENTITY_FILE"
    rm -f "$BACKUP"
}
trap restore EXIT

# Rewrites the one line the type's doc pins as the stamp target.
/usr/bin/sed -i '' "s|public static let commit = \"unattributable\"|public static let commit = \"$SHA\"|" \
    "$IDENTITY_FILE"

printf 'stamping build identity: %s (%s)\n' "$SHA" "$CONFIGURATION"
swift build --configuration "$CONFIGURATION" "$@"
printf 'built; restoring %s\n' "${IDENTITY_FILE#"$REPO_ROOT"/}"
