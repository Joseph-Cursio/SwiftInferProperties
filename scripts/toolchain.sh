#!/usr/bin/env bash
#
# Run the lint -> infer loop against a target, and SAY WHAT IT DID NOT DO.
#
# The five packages are described everywhere as a "toolchain", and until now no command ran
# them. The sequence lived in prose and diagrams, which cannot be executed and therefore
# cannot be wrong out loud. This is that sequence, made executable — a DEFINITION first and
# a measurement harness second.
#
# ## Stages, and where this one stops
#
#   0  locate the tools          IMPLEMENTED  — versions + SHAs, so a run is attributable
#   1  lint  -> seeds.json       IMPLEMENTED  — SwiftProjectLint --format pbt-seeds
#   2  discover --seeds -> index IMPLEMENTED  — the one hop that is the whole lint->infer link
#   3  verify                    NOT BUILT    — opt-in, spawns real builds per suggestion
#   4  kit conformance suites    NOT BUILT    — scaffold-kit-suites emits; nothing runs them
#   5  hardening                 NOT A COMMAND — annotating and writing tests is a human's job
#
# Stages 3-5 are declared and unimplemented ON PURPOSE. A driver that silently ended at
# stage 2 would print a clean run having never executed a single law — a confident zero
# wearing the loop's clothes, which is the exact failure this whole repo is built against.
# So they are listed, marked, and reported every run.
#
# ## This script is itself a border claim
#
# It asserts things about a repository it cannot see: that a binary exists, that a flag is
# spelled `--format pbt-seeds`, that the manifest is schema v2. Those claims rot the same way
# any other border claim does (see docs/design-internal/glossary.md#border-claim), so:
#
#   - it PROBES rather than assumes, and records what it found;
#   - a missing tool is NEVER treated as a clean stage. It is `unavailable`, and it is loud.
#
# ## Exit codes
#
#   0  every attempted stage completed
#   1  a stage FAILED, or could not run because a tool was missing/unbuildable
#
# Note what is not an error: stages 3-5 not running. They are `not-implemented`, reported in
# the manifest, and do not fail the run — otherwise the driver could never exit 0 and the
# signal would be worthless.
#
# Usage:
#   scripts/toolchain.sh <target-repo> [--target <SwiftPM target>] [--sources <dir>]
#                        [--out <dir>] [--include-possible]
#
# Example:
#   scripts/toolchain.sh ~/xcode_projects/MacCloud_client_iOS --sources Sources
#
# Artifacts land in <out>/ (default .toolchain-run/): seeds.json, discover.txt, run.json.
# run.json is the point — it makes two runs comparable, which is what an end-to-end number
# needs and has never had.

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFER_REPO="$(cd "$SELF_DIR/.." && pwd)"
LINT_REPO="${LINT_REPO:-$HOME/xcode_projects/SwiftProjectLint}"

TARGET_REPO=""
SPM_TARGET=""
SOURCES_DIR=""
OUT_DIR=""
INCLUDE_POSSIBLE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --target)           SPM_TARGET="${2:-}"; shift 2 ;;
        --sources)          SOURCES_DIR="${2:-}"; shift 2 ;;
        --out)              OUT_DIR="${2:-}"; shift 2 ;;
        --include-possible) INCLUDE_POSSIBLE=1; shift ;;
        -h|--help)          sed -n '2,50p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)                 printf 'unknown flag: %s\n' "$1" >&2; exit 1 ;;
        *)                  TARGET_REPO="$1"; shift ;;
    esac
done

if [ -z "$TARGET_REPO" ]; then
    printf 'usage: %s <target-repo> [--target <t>] [--sources <dir>] [--out <dir>]\n' "$0" >&2
    exit 1
fi
if [ ! -d "$TARGET_REPO" ]; then
    printf 'no such directory: %s\n' "$TARGET_REPO" >&2
    exit 1
fi
TARGET_REPO="$(cd "$TARGET_REPO" && pwd)"
OUT_DIR="${OUT_DIR:-$TARGET_REPO/.toolchain-run}"
mkdir -p "$OUT_DIR"

# ── Scan scope, resolved BEFORE any work ──────────────────────────────────────────────────
#
# **The two ends of this hop do not take the same input, and that is a real seam.** The
# linter takes a repository path and works the layout out for itself. `swift-infer discover`
# requires exactly one of `--target <SwiftPM target>` or `--sources <dir>` and errors without
# one. So a reader who pipes a manifest from the first into the second — which is the entire
# documented lint→infer link — hits an argument error on their first attempt.
#
# Found by running it: the first version of this driver passed neither and stage 2 died AFTER
# paying for a full linter build. Hence resolving here, before stage 0, and reporting what
# was inferred rather than silently guessing.
if [ -n "$SPM_TARGET" ] && [ -n "$SOURCES_DIR" ]; then
    printf 'pass at most one of --target or --sources (swift-infer accepts exactly one)\n' >&2
    exit 1
fi
SCOPE_ORIGIN="explicit"
if [ -z "$SPM_TARGET" ] && [ -z "$SOURCES_DIR" ]; then
    SCOPE_ORIGIN="inferred"
    if [ -d "$TARGET_REPO/Sources" ]; then
        # One directory under Sources/ is the unambiguous SwiftPM case. Several is ambiguous
        # and guessing would silently scan a third of the package, so scan the tree instead.
        # No `mapfile` — macOS ships bash 3.2 and this script must run on the machine it
        # documents. Counting with `wc` is portable where a bash-4 array read is not.
        _count=$(find "$TARGET_REPO/Sources" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
        if [ "$_count" -eq 1 ]; then
            SPM_TARGET=$(find "$TARGET_REPO/Sources" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null)
        else
            SOURCES_DIR="Sources"
        fi
    else
        # No Sources/ at all — an Xcode app. This is the case `--sources` exists for, and the
        # case where guessing wrong produces a confident zero rather than an error.
        printf 'no Sources/ in %s — pass --sources <dir> naming where the .swift files live\n' \
            "$TARGET_REPO" >&2
        exit 1
    fi
fi

failures=0
STAGE_JSON=""

# Record a stage outcome. `status` is deliberately richer than pass/fail, because the four
# ways a stage can not-run are four different facts and collapsing them is how a driver
# starts lying: ok · failed · unavailable · not-implemented · not-a-command.
record() {
    local id="$1" name="$2" status="$3" detail="$4"
    [ -n "$STAGE_JSON" ] && STAGE_JSON="$STAGE_JSON,"
    STAGE_JSON="$STAGE_JSON
    {\"stage\": $id, \"name\": \"$name\", \"status\": \"$status\", \"detail\": \"$(printf '%s' "$detail" | sed 's/"/\\"/g')\"}"
    case "$status" in
        ok)              printf '  ✔ %d %-28s %s\n' "$id" "$name" "$detail" ;;
        failed)          printf '  ✘ %d %-28s %s\n' "$id" "$name" "$detail"; failures=$((failures + 1)) ;;
        unavailable)     printf '  ✘ %d %-28s UNAVAILABLE — %s\n' "$id" "$name" "$detail"; failures=$((failures + 1)) ;;
        not-implemented) printf '  ▪ %d %-28s not built — %s\n' "$id" "$name" "$detail" ;;
        not-a-command)   printf '  ▪ %d %-28s not a command — %s\n' "$id" "$name" "$detail" ;;
    esac
}

sha_of() { git -C "$1" rev-parse --short HEAD 2>/dev/null || printf 'unknown'; }

printf '\n  Toolchain run — lint → infer\n'
printf '  target: %s\n' "$TARGET_REPO"
printf '  scope:  %s (%s)\n' \
    "$([ -n "$SPM_TARGET" ] && echo "--target $SPM_TARGET" || echo "--sources $SOURCES_DIR")" \
    "$SCOPE_ORIGIN"
printf '  %s\n\n' "$(printf '─%.0s' {1..72})"

# ── Stage 0 ───────────────────────────────────────────────────────────────────────────────
# Attribution, and it is not ceremony. Every measurement this repo has had to withdraw was
# withdrawn because nobody could say which binary produced it. A run that cannot name its
# tools cannot be compared with any other run, which makes it worthless as a baseline.
INFER_BIN="$INFER_REPO/.build/debug/swift-infer"
if [ ! -x "$INFER_BIN" ]; then
    ( cd "$INFER_REPO" && swift build --product swift-infer ) >/dev/null 2>&1
fi
if [ -x "$INFER_BIN" ]; then
    record 0 "locate swift-infer" ok "$(sha_of "$INFER_REPO") ($("$INFER_BIN" --version 2>/dev/null || echo 'no --version'))"
else
    record 0 "locate swift-infer" unavailable "could not build $INFER_REPO"
fi

LINT_AVAILABLE=0
if [ -d "$LINT_REPO" ]; then
    # The linter ships no installed binary and is run via `swift run CLI`. Building it is a
    # real cost on first use, and that cost IS part of the finding: the loop's entry point is
    # not something a reader can invoke today without compiling a package first.
    if ( cd "$LINT_REPO" && swift build --product CLI ) >/dev/null 2>&1; then
        LINT_BIN="$LINT_REPO/.build/debug/CLI"
        [ -x "$LINT_BIN" ] && LINT_AVAILABLE=1
    fi
fi
if [ "$LINT_AVAILABLE" -eq 1 ]; then
    record 0 "locate swiftprojectlint" ok "$(sha_of "$LINT_REPO") (built from source; no installed binary exists)"
else
    record 0 "locate swiftprojectlint" unavailable "not found or would not build at $LINT_REPO"
fi

# ── Stage 1 ───────────────────────────────────────────────────────────────────────────────
SEEDS="$OUT_DIR/seeds.json"
if [ "$LINT_AVAILABLE" -eq 1 ]; then
    # `pbt-seeds` deliberately bypasses the severity exit gate — it is an extraction format,
    # not a lint gate — so a non-zero exit here means the run itself broke, not that the
    # target has findings.
    if "$LINT_BIN" "$TARGET_REPO" --format pbt-seeds > "$SEEDS" 2>"$OUT_DIR/lint.stderr"; then
        if command -v jq >/dev/null 2>&1; then
            total=$(jq '.seeds | length' "$SEEDS" 2>/dev/null || echo '?')
            analysable=$(jq '[.seeds[] | select(.kind=="pure-function" or .kind=="idempotency" or .kind=="restricted-function")] | length' "$SEEDS" 2>/dev/null || echo '?')
            pending=$(jq '[.seeds[] | select(.kind=="extractable-kernel")] | length' "$SEEDS" 2>/dev/null || echo '?')
            ver=$(jq -r '.version' "$SEEDS" 2>/dev/null || echo '?')
            # An empty manifest is NOT a clean bill of health. It usually means the linter
            # could not see the shape of the code — which downstream reads as "nothing to
            # test here", the confident zero this hop is most prone to.
            if [ "$total" = "0" ]; then
                record 1 "lint → seeds.json" ok "0 seeds (schema v$ver) — EMPTY: usually the linter cannot see this code's shape, not that it has none"
            else
                record 1 "lint → seeds.json" ok "$total seeds (schema v$ver): $analysable analysable, $pending refactor-pending"
            fi
        else
            record 1 "lint → seeds.json" ok "written (install jq for a breakdown)"
        fi
    else
        record 1 "lint → seeds.json" failed "see $OUT_DIR/lint.stderr"
    fi
else
    record 1 "lint → seeds.json" unavailable "stage 0 could not provide the linter"
fi

# ── Stage 2 ───────────────────────────────────────────────────────────────────────────────
# The whole lint→infer link is this one flag. `--seeds` is the ONLY consumer of the manifest
# in the entire toolchain; no other swift-infer mode accepts it.
DISCOVER_OUT="$OUT_DIR/discover.txt"
if [ ! -x "$INFER_BIN" ]; then
    record 2 "discover --seeds" unavailable "stage 0 could not provide swift-infer"
elif [ ! -s "$SEEDS" ]; then
    record 2 "discover --seeds" unavailable "no seed manifest from stage 1"
else
    args=(discover --seeds "$SEEDS")
    [ -n "$SPM_TARGET" ] && args+=(--target "$SPM_TARGET")
    [ -n "$SOURCES_DIR" ] && args+=(--sources "$SOURCES_DIR")
    [ -n "$INCLUDE_POSSIBLE" ] && args+=(--include-possible)
    if ( cd "$TARGET_REPO" && "$INFER_BIN" "${args[@]}" ) > "$DISCOVER_OUT" 2>"$OUT_DIR/discover.stderr"; then
        # `grep -c` prints its count AND exits non-zero on no match, so a `|| echo 0`
        # fallback fires on top of the printed 0 and yields "0\n0". `|| true` swallows the
        # status without adding a second line.
        picks=$(grep -c '^\[Suggestion\]' "$DISCOVER_OUT" 2>/dev/null || true)
        # stderr is where the seed hop reports focus ratio, refactor-pending work, and the
        # rescue warnings that name a LINTER gap. Silently dropping it would discard the
        # most actionable output of the hop.
        warns=$(grep -c 'warning:' "$OUT_DIR/discover.stderr" 2>/dev/null || true)
        record 2 "discover --seeds" ok "$picks suggestion(s), $warns warning(s) — see discover.stderr for focus + linter-gap notes"
    else
        record 2 "discover --seeds" failed "see $OUT_DIR/discover.stderr"
    fi
fi

# ── Stages 3-5: declared, not run ─────────────────────────────────────────────────────────
record 3 "verify" not-implemented "opt-in; spawns a full SwiftPM build per suggestion"
record 4 "kit conformance suites" not-implemented "scaffold-kit-suites emits them; nothing runs them"
record 5 "hardening" not-a-command "annotate @Idempotent/@ClockDeterministic and write the tests — a human owes this"

# ── Run manifest ──────────────────────────────────────────────────────────────────────────
# The artifact that makes two runs comparable. Every withdrawn measurement in this repo was
# withdrawn partly because nobody recorded the conditions; this is the cheap fix.
cat > "$OUT_DIR/run.json" <<JSON
{
  "target": "$TARGET_REPO",
  "tools": {
    "swift-infer": "$(sha_of "$INFER_REPO")",
    "swiftprojectlint": "$(sha_of "$LINT_REPO")"
  },
  "options": {
    "spmTarget": "$SPM_TARGET",
    "sources": "$SOURCES_DIR",
    "includePossible": $([ -n "$INCLUDE_POSSIBLE" ] && echo true || echo false)
  },
  "stagesImplemented": [0, 1, 2],
  "stagesNotImplemented": [3, 4, 5],
  "stages": [$STAGE_JSON
  ]
}
JSON

printf '\n  %s\n' "$(printf '─%.0s' {1..72})"
printf '  artifacts: %s\n' "$OUT_DIR"
if [ "$failures" -gt 0 ]; then
    printf '  %d stage(s) failed or were unavailable — this run did NOT execute the loop.\n\n' "$failures"
    exit 1
fi
printf '  stages 0-2 ran. Stages 3-5 did NOT — no law was executed by this run.\n\n'
exit 0
