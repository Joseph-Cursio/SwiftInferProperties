# Pipeline walk — subject 2: SwiftUMLStudio

Second subject of the corpus pipeline walk (`docs/plans/corpus-pipeline-walk-scope.md`).
The first, SwiftMarkdownWiki, ran twice and produced eleven filings across
seven stages. This one exists to give those stages a **second subject**, which
the walk's own stop rule requires before a stage is worth a general fix:
*"One row is an anecdote; the sweep has already recorded four separate cases of
a single-site reading producing a wrong general claim."*

It is also the first subject run against a **released** toolchain. Everything
the first pass measured ran against an unreleased kit.

## Instrument

| | |
|---|---|
| SwiftProjectLint | `770ac211` (clean) |
| SwiftInferProperties | `fab9a4ad` (clean) |
| SwiftPropertyLaws | `3e26278` = **v4.5.0** (clean) |
| SwiftEffectInference | `1b62e764` (clean) |
| **Subject** | SwiftUMLStudio `111d8bd` (clean) |

---

## Subject 1 — `String.globPatternToRegex()`

`SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Emitters/String+Extensions.swift:48`

```swift
/// Translate this glob pattern into an anchored regular-expression string
/// (`^…$`): escape regex metacharacters, then expand `?`, `**/`, `**`, and `*`.
func globPatternToRegex() -> String {
    "^\(self)$"
        .replacingOccurrences(of: "[.+(){\\\\|]", with: "\\\\$0", options: .regularExpression)
        .replacingOccurrences(of: "?", with: "[^/]")
        .replacingOccurrences(of: "**/", with: "(.+/)?")
        .replacingOccurrences(of: "**", with: ".+")
        .replacingOccurrences(of: "*", with: "([^/]+)?")
}
```

**Why this one.** It was invisible to the linter until SwiftProjectLint#214 —
an `extension String`, which the pure-function rule refused because the project
does not declare `String`. #214 called it *"the best of them"* among the ~12
that gap was hiding, and the fix recovered it. So this row tests that fix end
to end, on the function the issue named.

It also has a genuine **inverse** in the same package: `Glob.description`
(`Parsing/Glob.swift:32`) maps a regex back to a glob, replacing `([^/]+)?`
with `*`, `(.+/)?` with `**/`, `.+` with `**`, `[^/]` with `?`, and stripping
backslashes. A forward/inverse pair in one module is the shape `round-trip`
exists for, and the walk has not yet had one.

### Prediction — written 2026-09-13, before any tool was invoked

**G1 — anchoring.** The result begins `^` and ends `$`, for every input.

*Refutable?* **Yes.** An implementation that forgot the wrap, or that applied
the escape pass to the un-wrapped string and appended anchors afterwards,
returns something without them. The docstring states this outright, so it is
also **owed** rather than conjectured.

**G2 — validity.** The result is always a valid `NSRegularExpression` pattern.

*Refutable?* **Yes, and I expect this one to FAIL against the real code.** The
escape class is `[.+(){\|]` — it covers `.`, `+`, `(`, `)`, `{`, `\` and `|`
and omits `[`, `]`, `^` and `$`. A glob containing `[` should therefore emit
an unterminated character class. The consequence is not a crash: `isMatching`
reads

```swift
guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return true }
```

so **an invalid pattern matches everything**. A glob a user wrote to narrow a
file set would silently widen it to all files. Predicted witness: `"a[b"`.

**G3 — round-trip.** `Glob.description` of the regex recovers the glob, for
globs that contain no regex metacharacters of their own.

*Refutable?* **Yes,** and I expect it to fail on inputs that collide with the
expansion vocabulary. A glob whose literal text is already `[^/]` expands to
nothing and comes back as `?`. Whether that counts as a defect or an
out-of-domain input is a judgement the law's *domain clause* has to make, which
is exactly what a template cannot supply and a docstring might.

**G4 — totality.** `globPatternToRegex` never traps, for any `String`.

*Refutable?* **Yes** in principle, and I expect it to hold: the body is four
`replacingOccurrences` calls and a literal interpolation, none of which trap.
Role-entailed rather than conjectured — nothing about "translate this pattern"
admits "unless the pattern is strange".

### What I predict the tool will NOT propose, written before the run

**Idempotence.** `globPatternToRegex(globPatternToRegex(g))` is meaningless —
the output is a regex, not a glob — so a proposal of idempotence here would be
a **false conjecture**, the same class as `highlight` on subject 1 of
SwiftMarkdownWiki. `T -> T` shape, no idempotent semantics. If the tool
proposes it, that is a row against the catalog, not a bug in this code.

Recorded here because it is the cheapest possible prediction to edit after the
fact, and the walk's third stop rule makes editing it fatal to the run.
