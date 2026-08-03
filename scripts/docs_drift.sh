#!/usr/bin/env bash
#
# Report which `docs/design-internal/` docs have a subject repository that has MOVED
# since the doc was written.
#
# Each of those docs carries a machine-readable trailer in its header:
#
#   <!-- doc-provenance date=YYYY-MM-DD subject=Repo@<full-sha> [version=x.y.z] observer=... -->
#
# A date says when someone looked. A SHA says exactly WHAT they looked at, which is the
# only one of the two a machine can act on: `git log <sha>..HEAD` turns "is this doc
# stale?" into a count.
#
# ## What this checks, and what it deliberately does not
#
# It answers ONE question: has the subject repo gained commits since the doc was written?
# It does NOT verify any claim in any doc. A moved subject means "re-verify the counts in
# here"; it does not mean the doc is wrong, and an unmoved subject does not mean the doc is
# right. The durable content of these docs — diagnoses, design rationale, the reason a
# decision was made — cannot go stale this way and is not what this is about.
#
# ## Exit codes, and why drift alone is not a failure
#
#   0  every subject resolved; drift (if any) reported
#   1  the check COULD NOT ANSWER for at least one doc — repo missing, SHA unknown to it,
#      or a malformed trailer
#   2  drift found AND `STRICT=1` was set
#
# Drift is normal: siblings move constantly and a doc written today is behind tomorrow.
# Failing on it would make this noise, and noise gets muted. What must never pass quietly
# is the check being UNABLE to tell you — a missing repo returning "no drift" would be the
# same confident zero this whole toolchain is designed against, reproduced inside the tool
# meant to catch it. Hence the split: exit 1 is a broken check, exit 2 is opt-in strictness.
#
# Usage:  make docs-drift           # report
#         STRICT=1 make docs-drift  # non-zero exit when anything has drifted
#         QUIET=1  make docs-drift  # print NOTHING when there is nothing to say
#
# QUIET exists for unattended callers — a session-start hook, a pre-push check. A clean
# report printed on every session is wallpaper, and wallpaper is how a check stops being
# read. Silence when clean is only safe because "could not answer" is NOT clean and still
# prints: the quiet path is skipped whenever drifted or unresolved is non-zero.

set -uo pipefail

DOCS_DIR="${DOCS_DIR:-docs/design-internal}"
SIBLING_ROOT="${SIBLING_ROOT:-$HOME/xcode_projects}"
CHECKOUTS="${CHECKOUTS:-.build/checkouts}"

drifted=0
unresolved=0
checked=0

# Where a subject repo lives. Siblings sit next to this one; third-party dependencies
# only exist as resolved checkouts, so both roots are tried before giving up.
resolve_repo() {
    local name="$1"
    for candidate in "$SIBLING_ROOT/$name" "$CHECKOUTS/$name" "../$name"; do
        if [ -d "$candidate/.git" ] || [ -f "$candidate/.git" ]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

# Buffer stdout so QUIET can decide, AFTER the counts are known, whether any of it is
# worth showing. Redirecting the whole body beats threading a `say()` helper through a
# dozen call sites, and leaves the reporting code identical in both modes — so the quiet
# path cannot drift from the loud one.
if [ -n "${QUIET:-}" ]; then
    QUIET_BUFFER=$(mktemp)
    exec 3>&1 1>"$QUIET_BUFFER"
fi

printf '\n  Doc drift — has each doc'"'"'s subject repo moved since it was written?\n'
printf '  %s\n\n' "$(printf '─%.0s' {1..72})"

shopt -s nullglob
for doc in "$DOCS_DIR"/*.md; do
    trailer=$(grep -m1 'doc-provenance' "$doc" 2>/dev/null) || true
    if [ -z "$trailer" ]; then
        printf '  ?  %-28s no doc-provenance trailer\n' "$(basename "$doc")"
        unresolved=$((unresolved + 1))
        continue
    fi

    checked=$((checked + 1))
    subject=$(printf '%s' "$trailer" | sed -n 's/.*subject=\([^ ]*\).*/\1/p')
    date=$(printf '%s' "$trailer" | sed -n 's/.*date=\([^ ]*\).*/\1/p')
    name="${subject%@*}"
    sha="${subject#*@}"

    if [ -z "$name" ] || [ -z "$sha" ] || [ "$name" = "$sha" ]; then
        printf '  ?  %-28s malformed subject: %s\n' "$(basename "$doc")" "${subject:-<none>}"
        unresolved=$((unresolved + 1))
        continue
    fi

    if ! repo=$(resolve_repo "$name"); then
        printf '  ?  %-28s repo not found: %s — CANNOT TELL, not "clean"\n' \
            "$(basename "$doc")" "$name"
        unresolved=$((unresolved + 1))
        continue
    fi

    # A SHA the repo has never heard of is unresolved, NOT zero drift. Usually a shallow
    # clone or an un-fetched remote; occasionally a typo in the trailer.
    if ! git -C "$repo" cat-file -e "${sha}^{commit}" 2>/dev/null; then
        printf '  ?  %-28s %s has no commit %.7s — try `git -C %s fetch`\n' \
            "$(basename "$doc")" "$name" "$sha" "$repo"
        unresolved=$((unresolved + 1))
        continue
    fi

    # Count only commits that touched what the docs make claims ABOUT — source and the
    # manifest. Every countable claim in these docs (file counts, law-suite counts, arity
    # ceilings, pins) is read off those paths; none is read off a doc or a README.
    #
    # Without this the check is self-defeating. The commit that ADDS a doc drifts that same
    # doc, so the two self-subject rows would report non-zero after every commit forever —
    # permanent noise, and noise gets muted. That is the failure the exit codes are designed
    # around, so it must not be reintroduced by the counting rule.
    behind=$(git -C "$repo" rev-list --count "${sha}..HEAD" -- Sources Package.swift 2>/dev/null || echo "?")
    total=$(git -C "$repo" rev-list --count "${sha}..HEAD" 2>/dev/null || echo "?")
    if [ "$behind" = "?" ] || [ "$total" = "?" ]; then
        printf '  ?  %-28s could not count commits in %s\n' "$(basename "$doc")" "$name"
        unresolved=$((unresolved + 1))
    elif [ "$behind" -eq 0 ]; then
        if [ "$total" -eq 0 ]; then
            printf '  ok %-28s %s @ %.7s — unmoved since %s\n' \
                "$(basename "$doc")" "$name" "$sha" "$date"
        else
            printf '  ok %-28s %s @ %.7s — %s commit(s) since %s, none touching source\n' \
                "$(basename "$doc")" "$name" "$sha" "$total" "$date"
        fi
    else
        drifted=$((drifted + 1))
        printf '  ⚠  %-28s %s has %s source commit(s) since %.7s (doc dated %s)\n' \
            "$(basename "$doc")" "$name" "$behind" "$sha" "$date"
        git -C "$repo" log --oneline "${sha}..HEAD" -- Sources Package.swift \
            | head -5 | sed 's/^/         /'
        [ "$behind" -gt 5 ] && printf '         … and %s more\n' "$((behind - 5))"
    fi
done

printf '\n  %s\n' "$(printf '─%.0s' {1..72})"
printf '  %s doc(s) checked · %s drifted · %s unresolved\n\n' \
    "$checked" "$drifted" "$unresolved"

# Restore stdout, then show the buffer only if there is something to act on. Note
# `unresolved` counts here as loudly as `drifted`: a check that could not answer must
# never be indistinguishable from a clean one, least of all in the mode built for callers
# who are not watching.
if [ -n "${QUIET:-}" ]; then
    exec 1>&3 3>&-
    if [ "$drifted" -gt 0 ] || [ "$unresolved" -gt 0 ]; then
        cat "$QUIET_BUFFER"
    fi
    rm -f "$QUIET_BUFFER"
fi

if [ "$drifted" -gt 0 ]; then
    printf '  Drift means RE-VERIFY THE COUNTS in those docs — not that the prose is wrong.\n'
    printf '  Diagnoses and design rationale do not expire; measurements do.\n\n'
fi

if [ "$unresolved" -gt 0 ]; then
    printf '  %s doc(s) could not be checked. That is a broken check, not a clean bill of\n' "$unresolved"
    printf '  health — fix it before trusting this output.\n\n'
    exit 1
fi

if [ "$drifted" -gt 0 ] && [ -n "${STRICT:-}" ]; then
    exit 2
fi

exit 0
