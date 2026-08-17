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
stale_clones=0

# The commit a doc's claims should be measured against: the project's tip, not this machine's.
#
# Prefers `origin/<default-branch>`, resolved from `origin/HEAD` where it exists and falling
# back to the conventional names. Returns the literal `HEAD` when there is no usable remote
# ref — a local-only or never-fetched clone — and the caller SAYS SO rather than passing the
# weaker measurement off as the stronger one.
project_tip() {
    local repo="$1" ref
    ref=$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
    if [ -n "$ref" ] && git -C "$repo" rev-parse -q --verify "$ref" >/dev/null 2>&1; then
        printf '%s' "$ref"; return
    fi
    for candidate in origin/main origin/master; do
        if git -C "$repo" rev-parse -q --verify "$candidate" >/dev/null 2>&1; then
            printf '%s' "$candidate"; return
        fi
    done
    printf 'HEAD'
}

# Refresh remote refs so `origin/<branch>` means today rather than whenever this clone last
# fetched — otherwise the fix above just moves the staleness one level out.
#
# `NOFETCH=1` skips it. The session-start hook is the reason: five network round-trips before
# a prompt appears is how a check becomes something people disable. Skipping is safe because
# the report still names the tip it used; the cost is that a repo nobody has fetched reports
# against whatever it last saw, which is strictly better than reporting against local HEAD.
fetch_quietly() {
    [ -n "${NOFETCH:-}" ] && return 0
    git -C "$1" fetch --quiet --no-tags origin >/dev/null 2>&1 || true
}

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

    fetch_quietly "$repo"

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
    # **Compare against the PROJECT tip, not the local clone's HEAD.**
    #
    # The first version counted `<sha>..HEAD`, which measures how stale the doc is relative to
    # *this checkout* — a different question from the one the doc raises. Measured 2026-08-03:
    # the local SwiftProjectLint clone sat 44 commits behind its origin, so a doc written
    # against that clone reported `unmoved` while the project it describes had moved 44 times.
    # True of the clone, false of the project, and the tool built to catch exactly that said
    # `ok`. Same failure as every other border claim here — verified against a local proxy for
    # the thing actually being claimed about.
    tip=$(project_tip "$repo")
    tip_label=""
    [ "$tip" = "HEAD" ] && tip_label=" (no remote — local HEAD only)"

    behind=$(git -C "$repo" rev-list --count "${sha}..${tip}" -- '*Sources/*' '*Package.swift' 2>/dev/null || echo "?")
    total=$(git -C "$repo" rev-list --count "${sha}..${tip}" 2>/dev/null || echo "?")
    # A stale clone is its own fact, reported separately. It does not make the doc wrong — the
    # doc is measured against the project — but it does mean anything you go and READ in that
    # checkout to re-verify a count is itself out of date.
    local_behind=$(git -C "$repo" rev-list --count "HEAD..${tip}" 2>/dev/null || echo 0)

    if [ "$behind" = "?" ] || [ "$total" = "?" ]; then
        printf '  ?  %-28s could not count commits in %s\n' "$(basename "$doc")" "$name"
        unresolved=$((unresolved + 1))
    elif [ "$behind" -eq 0 ]; then
        if [ "$total" -eq 0 ]; then
            printf '  ok %-28s %s @ %.7s — unmoved since %s%s\n' \
                "$(basename "$doc")" "$name" "$sha" "$date" "$tip_label"
        else
            printf '  ok %-28s %s @ %.7s — %s commit(s) since %s, none touching source%s\n' \
                "$(basename "$doc")" "$name" "$sha" "$total" "$date" "$tip_label"
        fi
    else
        drifted=$((drifted + 1))
        printf '  ⚠  %-28s %s has %s source commit(s) since %.7s (doc dated %s)%s\n' \
            "$(basename "$doc")" "$name" "$behind" "$sha" "$date" "$tip_label"
        git -C "$repo" log --oneline "${sha}..${tip}" -- '*Sources/*' '*Package.swift' \
            | head -5 | sed 's/^/         /'
        [ "$behind" -gt 5 ] && printf '         … and %s more\n' "$((behind - 5))"
    fi

    if [ "$local_behind" != "0" ]; then
        printf '     ↳ your %s checkout is %s commit(s) behind %s — re-verify by fetching, not by reading it\n' \
            "$name" "$local_behind" "$tip"
        stale_clones=$((stale_clones + 1))
    fi
done

printf '\n  %s\n' "$(printf '─%.0s' {1..72})"
printf '  %s doc(s) checked · %s drifted · %s unresolved · %s stale checkout(s)\n' \
    "$checked" "$drifted" "$unresolved" "$stale_clones"

# THE DENOMINATOR. Without it the line above is a count wearing a coverage report:
# "8 docs checked, 0 drifted" reads as "the docs are fine" and means "the eight docs
# in one directory are fine". This project's own standing rule — a census's zero cannot
# be read without its corpus list — was being broken by the tool that reports on docs.
#
# Measured when this was added (2026-08-17, open item 39): 9 of 91 docs under `docs/`
# were in scope, and 49 of the 82 out of scope named a sibling repo, i.e. made exactly
# the class of claim this check exists to verify. The survey that prompted the item
# (`PBT_EFFECT_VOCABULARY_SURVEY.md`) was not among either count: it lives in the
# workspace parent, outside every git repository, where no per-repo check can reach it.
#
# Deliberately NOT fixed by widening DOCS_DIR. Every one of those 82 lacks a provenance
# trailer, so a wider glob prints 82 `?` rows and the signal drowns — the check would
# become the thing nobody reads, which is the failure mode two other rows in the
# open-threads doc already record.
scope_total=$(find docs -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
scope_claims=$(find docs -name '*.md' ! -path "$DOCS_DIR/*" -exec \
    grep -lE 'SwiftEffectInference|SwiftProjectLint|SwiftPropertyLaws|SwiftIdempotency' {} \; \
    2>/dev/null | wc -l | tr -d ' ')
printf '  scope: %s/*.md only — %s of %s docs under docs/. %s out-of-scope doc(s) name a\n' \
    "$DOCS_DIR" "$checked" "$scope_total" "$scope_claims"
printf '  sibling repo and are NOT checked here; docs outside the repo are invisible to it.\n\n'

# Restore stdout, then show the buffer only if there is something to act on. Note
# `unresolved` counts here as loudly as `drifted`: a check that could not answer must
# never be indistinguishable from a clean one, least of all in the mode built for callers
# who are not watching.
#
# `stale_clones` deliberately does NOT break silence. Since drift is now measured against the
# project tip, a behind-by-N checkout invalidates no claim in any doc — it only means that
# re-verifying a count by *reading that clone* would read the wrong thing. That is advisory,
# and a repo someone is deliberately not pulling (local work in progress, say) would otherwise
# nag at every session until they gave up on the check.
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
