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

---

### Result — 0 of 4, and the one delivery is the conjecture I predicted

| law | predicted refutable? | tool proposed it? | holds against the code? |
|---|---|---|---|
| **G1** anchoring | yes, and *owed* — the docstring states it | **no** | holds, 7 of 7 samples |
| **G2** validity | yes, and predicted to **fail** | **no** | **fails** |
| **G3** round-trip | yes | **no** | holds 8 of 9, fails on the predicted input |
| **G4** totality | yes, role-entailed | **no** | holds |

**What the tool proposed instead: `idempotence`, score 35 (Possible)** — which the
prediction section, written before the run, says would be a false conjecture:

> `globPatternToRegex(globPatternToRegex(g))` is meaningless — the output is a
> regex, not a glob.

Its evidence is *"Type-symmetry signature: self -> Self (Self = String)"* and a
proven analog about `uppercased()`. It is the same shape as subject 1's
`highlight`: a `T -> T` read off the signature.

**To the tool's credit it says so, in the output, unprompted:** *"THIS LAW IS A
CONJECTURE — read off the shape and the name, not entailed by either, so a
CORRECT implementation can fail it."* The conjecture arrives labelled. That is
`--include-possible` working as documented, not a defect — and it is why
refutability rather than suggestion count is this walk's score.

### S0 — closed, and the fix is confirmed on the function the issue named

`globPatternToRegex` **is** in the seed manifest, as `pure-function`. It was
invisible before SwiftProjectLint#214, which called it *"the best of them"*
among the ~12 that gap was hiding. So that fix works end to end on its own
headline example. `Glob.description` is seeded too.

**First S0 row this walk has closed by measurement rather than by argument.**

### G2 — a real defect in the subject, and one prediction was wrong in an interesting way

The escape class is `[.+(){\|]`: `.`, `+`, `(`, `)`, `{`, `\`, `|`. Measured
against the real function:

| glob | regex | valid? |
|---|---|---|
| `a[b` | `^a[b$` | **no** — unterminated character class |
| `a}b` | `^a}b$` | **no** |
| `a^b` | `^a^b$` | yes, and **can never match** — two anchors |
| `a$b` | `^a$b$` | yes, and **can never match** |
| `*.swift` | `^([^/]+)?\.swift$` | yes |

**The prediction named `[` and got `}` wrong.** I wrote *"`}` alone is usually
literal"* — it is not, in ICU, and `a}b` is as invalid as `a[b`. Recorded rather
than quietly corrected: the prediction was right about the class of defect and
wrong about one member of it, which is the sort of thing writing it down first
is for.

**The consequence is smaller than predicted, and that matters.** I wrote that
`isMatching`'s `guard let regex = try? … else { return true }` turns an invalid
pattern into *matches everything*, and it does —
`"totally/unrelated.txt".isMatching(searchPattern: "a[b")` is `true`. But
**`isMatching` has no production caller**; only tests use it. The live path is
`expandGlobs`, which catches, logs *"failed to compile glob regex"*, and falls
back to `.path(path)` — so a real user's `[Aa]pp` glob silently selects **no**
files, with an error in the log, rather than every file.

So: a real defect, a loud-ish degradation on the path that runs, and a silent
always-true on a path that does not run yet. Worth fixing; not worth the alarm
the prediction implied.

### G3 — the inverse exists, is seeded, and no signature could have paired them

`Glob.description` genuinely inverts the expansion, and round-trips 8 of the 9
globs sampled. It fails on `"[^/]"` → `"?"`, which the prediction named.

**But the tool could not have proposed this pair, and that is not a catalog
gap.** A round-trip wants `A -> B` and `B -> A`. What exists is
`String -> String` (glob text to regex text) and `Glob -> String` (a `Glob`
back to glob text). Composing them means wrapping the regex text in an
`NSRegularExpression` and then in a `Glob.regex` case — two constructions the
signatures do not mention. A signature-pattern matcher is *right* to be silent
here, and a docstring is the only thing that could have said the pair exists.

Recorded as a **correction to the prediction's stage attribution**, not as an
S3 row against the catalog.

### S4 — the docstring states G1 and the contract gate does not recognise it

The advisory ran: 54 entries for this target. `globPatternToRegex` is not one
of them, and its docstring is unambiguously a contract —

> *"Translate this glob pattern into an **anchored** regular-expression string
> (`^…$`): escape regex metacharacters, then expand `?`, `**/`, `**`, and `*`."*

It names the output shape and the transformation. `DocstringAdvisor.isContract`
rejects it: checked against the live list, **the docstring matches 0 of the 59
contract cues**.

The near-misses are the finding. The list carries `converts`, `maps`, `encodes`,
`decodes`, `parses`, `normalizes`, `produces`, `yields`, `computes` — nine verbs
for "turns one thing into another" — and not `translate`, which is the word this
docstring uses and the word the function's own name implies.

**S4, and the same curated-vocabulary shape this project keeps recording.** It is
a different cause from #420, which was an arm ordering; this is the gate in front
of every arm.

### Running tally, after one subject function

| stage | rows | note |
|---|---|---|
| S0 | 0 | **closed by measurement** — #214's fix delivers its own headline example |
| S1 | 0 | seeded and reached |
| S3 | 2 | G2 (no template names "the output is a valid regex"); G4 (`input-totality` does not fire on a translation verb) |
| S4 | 1 | the contract gate does not know `translate` |
| S5–S8 | — | not reached for this function: the one suggestion is a conjecture the prediction rejects, so there is nothing worth emitting |

**G3 is deliberately not a row.** The inverse is real and the tool was right to
be silent about it; a signature cannot see a pair that composes through two
constructors. Attributing that to the catalog would be scoring the tool for
something no version of it could do.

### What the second subject says that the first could not

Subject 1's S3 was 19 rows on one repository, which its own tally called
untouched by eleven filings. That is an anecdote by this walk's stop rule. Two
rows here are not yet the three-across-two the rule wants, but they are the
*same kind* of row: **a law the code genuinely owes, that no template names.**

And the S4 row is a second, independent instance of the shape #420 fixed one arm
of — a curated vocabulary deciding whether a docstring is allowed to speak. The
first was arm ordering. This one is the gate in front of every arm, and one
missing synonym silences a function whose contract is written down in its own
first sentence.
