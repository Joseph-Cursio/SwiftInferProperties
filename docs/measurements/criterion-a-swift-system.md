# Criterion A on `swift-system` — the ratified bar, answered

> **Status:** `measured` · **As of:** 2026-08-21

Subject: **`swift-system` @ `6a63f08`** (release/1.7.0). Genuinely unmet — **zero mentions
in `fixtures/corpora/manifest.json` and zero across all of `docs/`**, checked before use.
Re-derivable: `swift-infer index --target System` then `verify --all-from-index`.

**Criterion A FAILS. Not one of 41 emitted laws executes, so no law can kill any mutant.**

Unlike the first attempt, this is a clean answer rather than an invalid one: **no mutant
was needed.** When nothing runs, no choice of defect can change the result.

---

## 1. The result

| outcome | rows |
|---|---:|
| `unsupported-carrier` | **36** |
| `unsupported-template` | 4 |
| `not-a-candidate` | 1 |
| **`build-failed`** | **0** |
| **laws that ran** | **0 of 41** |

**Discovery looked healthy.** 41 suggestions across seven templates — `idempotence` 18,
`predicate` 9, `round-trip` 5, `monotonicity` 4, `inverse-pair` 2, `input-totality` 2,
`measure-non-negativity` 1 — with **one `Strong` and four `Likely`**. That is a far better
spread than `swift-http-types`, which was 91% `idempotence` and had no `Strong` row at all.

**None of it executed.**

---

## 2. The emitter fixes held, and that is what exposed the real blocker

`criterion-a-unmet-subject.md` measured **145 of 163 laws failing to compile (89%)** on
the previous subject, from three emitter defects. Those are fixed, and here
**`build-failed` is zero**.

That is worth stating precisely, because it is easy to read as a win: **fixing the 89%
bought no executing laws.** It converted build failures into honest declines — better,
because a decline is information and a build failure is noise — and revealed that the
binding constraint underneath was always the carrier.

---

## 3. The cause: the tool cannot construct the subject's principal type

Of the 36 `unsupported-carrier` rows:

| carrier | rows |
|---|---:|
| **`FilePath`** | **15** |
| (no carrier recorded) | 12 |
| `FileDescriptor` | 3 |
| `_RawBuffer` | 2 |
| `FilePermissions`, `Request`, `Trace`, `_Lexer` | 1 each |

`FilePath` is swift-system's central value type and the natural home of its normalisers.
**Fifteen suggestions rest on it and not one can run.**

### And `FilePath` is trivially constructible

```swift
extension FilePath: ExpressibleByStringLiteral { … }   // FilePathString.swift:291
public init(platformString: String) { … }              // FilePathString.swift:58
```

**A carrier that is `ExpressibleByStringLiteral` needs no derivation at all** — a `String`
generator and a `map` produce it. No memberwise initialiser to find, no conformance to
prove, no element type to resolve.

**`ExpressibleByStringLiteral` appears nowhere in `Sources/`.** The codebase consults
`ExpressibleByArrayLiteral` in four places — `OrderedCarrierDiscriminator`,
`StdlibConformances`, `ProtocolCoverageMap`, `BulkIncrementalPairing` — and has never
looked at the string one.

**So the carrier gap here is not inherent. It is an unexploited conformance**, and it is
the cheapest generator route this project has left on the table.

---

## 4. What this answers, and what it does not

**Answers A on this subject: it fails, and the reason is reach rather than law quality.**
No mutant was planted, and none was needed — a law that does not execute cannot kill
anything, whatever defect it is offered.

**Does not measure whether the laws are any good.** The 41 suggestions may be true,
false, or vacuous; nothing here says. That question needs laws that run.

**Does not generalise from one subject.** `planted-defect-arm`'s rule holds in this
direction too: this is an existence check that came back negative on one package, not a
rate.

**One instrument caveat.** 12 of the 36 rows record no carrier at all, and this document
does not diagnose them. They may be a distinct defect or the same one reported without a
name; unmeasured.

---

## 5. What follows

**Build the `ExpressibleByStringLiteral` generator route.** It is a conformance check and
a `map`, it needs nothing the tool must prove, and on this subject alone it addresses 15
of 41 suggestions. It is the first concrete, cheap thing criterion A has pointed at.

**Then re-take A here.** With `FilePath` constructible, the 15 rows become executable and
A becomes answerable on its merits — with a defect chosen to *violate* a law rather than
chosen for realism, which is the rule `fixtures/branch-reaching-generator/` §3 earned.

**Do not treat this failure as the tool's verdict.** Two subjects have now been tried and
neither reached the point where law quality could be judged: the first was blocked by
emitter defects, the second by carrier construction. **A has still never been evaluated on
a law that ran.**
