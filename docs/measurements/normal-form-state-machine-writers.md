# `normal-form` and `state-machine` — should either get a stub writer? (#478)

> **Status:** `measured` · **As of:** 2026-09-16

[#468](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/468) found that nine of
the eleven role-entailed templates write no stub.
[#478](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/478) split two of them
out as *needing a design first*: `normal-form`, because generating parseable text is hard,
and `state-machine`, because the carrier is often a view model with I/O. This is the
measurement those two design questions were waiting on.

**The two answers are different, and neither is the one the issue expected.**

- **`normal-form` — DECLINE the runnable writer, on a measured zero.** Its three
  highest-quality subjects are swift-foundation's ISO8601 date format styles, and the
  generator the accept path would hand them accepts **0 of 10,000 draws**. Across the whole
  real-world population — **6 rows** — five are vacuous under that generator and the sixth
  wants the *stronger* law the template's own first caveat tells the reader to prefer.
- **`state-machine` — the writer is not the binding constraint.** **5 of its 16 rows (31%)
  name a pair the code does not owe**, by three distinct mechanisms, and two of them shadow a
  correctly-named partner declared on the same type a few lines away. Fix
  `InverseMutatorPairing` first; a scaffold is cheap and uncontroversial after.

---

## 1. Instrument

| | |
|---|---|
| swift-infer | `3d5ab756`, built in a **clean detached worktree** |
| command | `discover --sources <dir> --include-possible --no-docstring-advice` |
| corpus A | the 19 repositories of [`corpus-funnel-census-2026-09-14.md`](corpus-funnel-census-2026-09-14.md), each in a **detached worktree of HEAD** |
| corpus B | the 20 resolving corpora of `fixtures/corpora/manifest.json` |
| probe | `Xoshiro`-seeded, 10,000 draws from `RawType.edgeBiasedGeneratorExpression` |
| Swift | 6.3.3-RELEASE (swift.org) |

Three choices are load-bearing and none is cosmetic.

**Detached worktrees, not the checkouts.** A `.swiftinfer/decisions.json` left by an earlier
triage run *suppresses* suggestions. The first probe of SwiftProjectLint returned 11
suggestions for its whole `Sources/` tree — a fact about a file written by the session that
filed these issues, not about the repository. `decisions.json` is gitignored, so a worktree
does not carry it.

**A clean-HEAD build, because the tree was dirty.** This session's working tree carries
uncommitted `guard-domain` work (#477). It touches neither template's path, but *"it touches
nothing relevant"* is an argument and the counts are a measurement — so the hit-bearing scan
roots were re-run against a binary built from a clean worktree at `3d5ab756`. **39 and 6,
both times.**

**Both corpus lists, because one of them could not answer.** ⚠ **This page's first draft said
`normal-form`'s real-world population was 3 rows, and it was wrong — corpus A holds no
general-purpose library.** Corpus B doubled it to 6 and supplied the three best subjects in
it. Sixth payment of *a census is only as wide as its corpus list*, and the first time the
app corpus has been the one that could not answer.

### Validation

**The unseeded whole-tree scan reproduces the corpus funnel census exactly on corpus A:
`normal-form` 39, `state-machine` 6.** The census reached those numbers through a different
harness — per-target, seeded from SwiftProjectLint, answering every interactive prompt `A` —
so the two agree on the population while sharing almost none of their machinery.

One subject has moved: `MacCloud_server` is at `7cfcd3e`, not the census's `65cdc08`. It
produces no row of either template at either revision.

**The two corpus lists overlap on three subjects** (SwiftLintRuleStudio, SwiftFormatRuleStudio,
and the home repo), so the unions below are deduplicated on `(identity, sites)` and the raw
counts are **not** summed. The pbt-workbook-sampler rows collapse into pbt-workbook-corpus's
the same way, because they are the same vendored file.

---

## 2. `normal-form` — 42 rows, and where they are

Corpus A 39 + corpus B 15 = **42 unique rows** after dedup.

| repository | rows | corpus |
|---|---:|---|
| pbt-workbook-corpus / -sampler | 25 | A — `Sources/WorkbookCorpus/Set1RoundTrips.swift`, one teaching file |
| swift-foundation | 11 | B — `Formatting/Date+…FormatStyle.swift` |
| SwiftAssist | 2 | A |
| SwiftFormatRuleStudio | 2 | A + B |
| SwiftLintRuleStudio | 1 | A + B |
| SwiftProjectLint | 1 | B |

**25 of 42 (60%) are one file.** `Set1RoundTrips.swift` is Set 1 of a property-testing
workbook: it declares a codec protocol and then four conformers, one correct and three
carrying a documented deliberate bug. That is the concentration objection that already killed
the postcondition body-guard route
([`postcondition-law-declined.md`](postcondition-law-declined.md): *9 of 13 in one file*).

### 2.1 Two thirds of the rows pair halves from different types

**29 of the 42 rows (69%) pair a parse half with a print half declared on a different type.**

Inside the teaching file, 18 of the 25 do it — and because three of the four conformers are
deliberately buggy, those are laws about composing one implementation's encoder with
another's decoder:

```
CorrectCSV.decode            ×  DashSeparatorCSV.encode
CorrectPath.serialize        ×  WrongDelimiterPath.parse
TrailingSeparatorPath.parse  ×  DropsLastSegmentPath.serialize
```

Nobody owes those. The same shape recurs at longer range in real code: SwiftAssist pairs
`WorkspaceIndexer.parseImports(from:)` with `ThinkingRecipeExtractor.deriveName(from:)` —
different types, different files, different subsystems, joined only by being
`String -> [String]` and `[String] -> String`; and swift-foundation pairs
`DateComponents.description()` with `Date.HTTPFormatStyle.parse(_:)`. This is
[row 70](../design-internal/open-threads.md)'s defect — *round-trip chooses an inverse on
type signature alone* — arriving at a second template.

**The discriminator already exists and already fires.** `NormalFormTemplate.signals` adds
`+5` for *"Both halves are declared on the same type"*, so the split is exact: **every
same-type row scores 40 and every cross-type row scores 35**, in both corpus lists. Nothing
needs to be invented to separate them; a writer gated on that signal drops all 29.

⚠ **It costs one arguably-true row.** SwiftFormatRuleStudio's
`SwiftFormatConfig.parseLine(_:)` × `Line.rendered` is a genuine `String ↔ Line` pair
declared across a nested type, and the same-type gate refuses it. It is moot here —
`parseLine` is `private static`, so it is one of the two rows #478 already counted as
unreachable — but the gate is a heuristic with a known false negative, not a fact.

**Same-type: 13 rows. Seven are the teaching file. Six are real:**

| subject | pair |
|---|---|
| swift-foundation | `Date.ISO8601FormatStyle` `format` / `parse` |
| swift-foundation | `DateComponents.ISO8601FormatStyle` `format` / `parse` |
| swift-foundation | `Date.HTTPFormatStyle` `format` / `parse` |
| SwiftFormatRuleStudio | `SwiftFormatConfig.parse` / `serialized` |
| SwiftLintRuleStudio | `YAMLConfigurationEngine.parse` / `serialize` |
| SwiftAssist | `SQLiteGraphDatabase.encodeProperties` / `decodeProperties` |

Those six are the population a writer would serve, and the swift-foundation three are as
good as a parse/print pair gets: public API, documented, genuinely owed.

### 2.2 The design question, measured

The issue names the hard part, quoting the template's own caveat: *"GENERATING PARSEABLE TEXT
IS THE HARD PART."* So: what does the generator the accept path would actually hand a
normal-form stub reach on those six?

For a top-level `String` carrier, `InteractiveTriage.chooseGenerator` falls through
`.inferredFromTests` and `.derivedCodableRoundTrip`, gets `nil` from the project-type
resolver, and lands on `LiftedTestEmitter.defaultGenerator(for: "String")` —
`RawType.edgeBiasedGeneratorExpression`, a four-arm `Gen.frequency` over 14 structural tokens
(`""`, `" "`, `"\n"`, `"\t"`, `"-"`, `"- "`, `":"`, `"#"`, `"/"`, …) mixed with alphanumeric
strings of length 0–8. ⚠ **That was read off the accept path, not off discover's output**,
which labels these rows `Generator: .derivedComposite`; the displayed label is the
strategist's and is not what the stub would carry.

10,000 draws, against each subject vendored verbatim (swift-foundation measured against the
Foundation shipped with the toolchain rather than a build of swift-foundation — same format
styles, and what is being measured is whether the draws reach the parser's language at all):

| subject | what happened |
|---|---|
| **swift-foundation** `Date.ISO8601FormatStyle.parse` | **accepted 0 of 10,000** |
| **swift-foundation** `DateComponents.ISO8601FormatStyle.parse` | **accepted 0 of 10,000** |
| **SwiftLintRuleStudio** `YAMLConfigurationEngine.parse` | accepted **254 of 10,000 (2.5%)** — and the accepted inputs are **1 distinct string, `"::"`** |
| **SwiftAssist** `encodeProperties(decodeProperties(s))` | `decodeProperties` returned the **empty dictionary on 10,000 of 10,000**. `normalize(s)` takes **1 distinct value, `"{}"`**. The law holds 10,000/10,000 |
| **SwiftFormatRuleStudio** `serialized(parse(s))` | **3,949 distinct normal forms** — genuinely non-vacuous. And the **stronger** law `serialized(parse(s)) == s` also holds **10,000/10,000** |

`Date.HTTPFormatStyle` is not public on the shipped Foundation and was not run; it is the
same grammar class as the ISO8601 pair beside it, and it is recorded as **not measured**
rather than assumed.

**Five of the six are vacuous. The sixth wants a different law.**

### 2.3 What that refutes

**The issue's own proposed mitigation is not sufficient, and is blind on the subject where it
matters most.** #478 asks that whatever ships *"count how many trials actually parsed and
fail loudly when it is near zero."* On SwiftAssist that counter reads **100%**:
`decodeProperties` never fails, it absorbs every garbage string into `[:]`. A parse-rate
guard would certify a law that checks one point. On SwiftLintRuleStudio it *would* fire at
2.5% — but the accepted set is also a single string, so the guard is neither necessary nor
sufficient.

**The statistic that separates all of them is the number of distinct normal forms** — 1 /
3,949 / 1, and 0 draws even reaching the swift-foundation parsers. Counting that means
running the subject before deciding whether to emit, which is `verify`'s job and not the
accept path's.

**And where the law is not vacuous, it is the wrong law.** `SwiftFormatConfig` is
full-fidelity, so caveat 1 of the template applies verbatim: *"IF YOUR PRINTER IS
FULL-FIDELITY, STATE THE STRONGER LAW INSTEAD."* The subject's maintainer already did. Their
`SwiftFormatConfigNormalFormPropertyTests` states both, and its header says of the weak one:
*"still true, still weak. Almost any implementation satisfies idempotent normalisation,
which is why it was the wrong law to settle for."*

### 2.4 The three options the issue lists, scored

**Seed from literals in the subject's tests or docstrings** — on the one subject that has such
a suite, the literals are *regression pins* (`"--indent 4\n   \n--enable isEmpty"`), and the
suite postdates the generator rather than supplying it. There is nothing to harvest.

**Generate the STRUCTURE and print it** — the caveat's own suggestion, and the one that looks
free and is not. `SwiftFormatConfig.Line` is
`.option(key: String, value: String, raw: String)`: only `raw` is printed, and `key`/`value`
must agree with it. A generator drawing the three fields independently produces a `Line` the
parser never produces, prints its `raw`, and reparses to a **different** `Line` — so the law
fails on a value the type forbids. That is the false-law mechanism already named in
[`module-qualified-leaf-spelling.md`](module-qualified-leaf-spelling.md) — *round-trip over a
type whose fields carry an undeclared cross-field invariant* — and it would land on the one
subject of the six where the law is real. The other structures are worse: `YAMLConfig`
carries a dozen fields including recovered layout and passthrough nodes, and `Date` is a
`Double` whose printed form is a calendar computation.

**Emit a scaffold asking for sample inputs** — the only one that survives, and it is exactly
what #478 proposes for `state-machine`.

### 2.5 What a human actually did

Worth recording, because it is the only worked answer to the design question in the corpus.
`SwiftFormatConfigNormalFormPropertyTests` hand-rolls its generator: **eight line shapes read
off `parseLine`'s branch structure** (blank, whitespace-only, comment, indented comment,
`--key value`, `--disable a,b`, `--enable x`, bare word) over an **eight-word alphabet drawn
from the subject's own vocabulary** (`indent`, `self`, `enable`, `isEmpty`, `redundantSelf`,
`x`, `4`, `remove`). It is a transcription of the parser, written by someone who had read it.
None of the three options produces it, and neither does any generator derived from types.

### 2.6 Recommendation

**Do not build a runnable `normal-form` writer.** Six real rows; on five of them any
generator-drawn stub is measured vacuous — **0 of 10,000 on the best three** — and on the
sixth the law worth writing is the stronger one the template already tells the reader to
prefer. This is not a generator problem waiting for a better generator: the law's
*statability* needs a grammar for the parser's input, the tool has none, and the population
does not pay for deriving one.

**What is worth doing is cheap.** #468 notes that *"no stub writeout available for template
'normal-form' in v1"* reads as unfinished work. It is not: it is a decision. A decline
sentence saying *this law needs a grammar for the parser's input, which swift-infer cannot
derive — see the template's caveats* costs nothing and stops the reader waiting for a writer.
A scaffold in the `replay-idempotence` shape is defensible on those six rows, and should be
gated on the same-type signal so it never writes one of the 29.

**What would reopen this:** a subject whose parse half is partial *and* whose accepted
language the shipped generator reaches — a row where distinct-normal-forms is large and the
stronger law is false. None of the 42 is that.

---

## 3. `state-machine` — 16 rows, and 5 are wrong

Corpus A 6 + corpus B 13 = **16 unique rows** after dedup. Hand-checked exhaustively; this is
the whole population, not a sample.

| # | repository | forward / backward | verdict |
|---|---|---|---|
| 1 | SwiftAssist | `addAvoidPattern(_:)` / `removeAvoidPattern(_:)` | ✅ |
| 2 | SwiftLintRuleStudio | `addToRecentWorkspaces(_:)` / `removeFromRecentWorkspaces(_:)` | ✅ |
| 3 | SwiftUMLStudio | `pushType(_:genericParams:)` / `popType()` | ✅ |
| 4 | pbt-book | `select(_:)` / `deselect()` | ✅ |
| 5 | SwiftInferProperties | `pushType(_:memberBlock:)` / `popType()` | ✅ |
| 6 | swift-foundation | `push(value:)` / `popValue()` | ✅ |
| 7–8 | GRDB | `add(transactionObserver:extent:)` / `remove(transactionObserver:)` ×2 | ✅ |
| 9 | GRDB | `add(function:)` / `remove(function:)` | ✅ |
| 10–11 | swift-nio | `addHandler(_:name:position:)` / `removeHandler(…)` ×2 | ✅ |
| 12 | SwiftFormatRuleStudio | `addRule(_:to:)` / **`removeOption(key:)`** | ❌ **Rule vs Option** |
| 13 | SwiftLintRuleStudio | `addDisabledRuleIfNeeded(to:)` / **`removeOptInRuleIfPresent(from:)`** | ❌ **Disabled vs OptIn** |
| 14–15 | SwiftPM | **`addOrUpdate(for:user:password:persist:)`** / `remove(for:)` ×2 | ❌ **an upsert is not an add** |
| 16 | swiftlang-swift | `add(_: AnyObject)` / **`removeObject(at: Int)`** | ❌ **adds a value, removes an index** |

**5 of 16 (31%) name a pair the code does not owe**, by three distinct mechanisms.

### 3.1 Two of them shadow a right pair in the same file

- `SwiftFormatConfig+Editing.swift:77` declares **`removeRule(_:from:)`** — the actual
  inverse of the `addRule(_:to:)` at line 63. The tool paired line 63 with `removeOption` at
  line 34 instead.
- `RuleDetailViewModel+ConfigMutation.swift:88` declares
  **`removeDisabledRuleIfPresent(from:)`** — the actual inverse of
  `addDisabledRuleIfNeeded(to:)` at line 50.

Both partners are on the **same type** (`extension SwiftFormatConfig`,
`extension RuleDetailViewModel`) and a few lines away. Nothing about visibility or scope
prevented the right pairing.

### 3.2 And the rule can emit at most one pair per type, so it loses true laws

`InverseMutatorPairing.candidates` does two things that together produce all of this:

```swift
private static func matches(_ name: String, _ stem: String) -> Bool {
    name.lowercased().hasPrefix(stem)          // the VERB only
}
…
guard let forward  = members.first(where: { matches($0.name, rule.forward) }),
      let backward = members.first(where: { matches($0.name, rule.backward) }),
```

**`hasPrefix` on a verb cannot bound a compound name** — verbatim the mechanism
[#476](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/476) settled for
`filter-subset` three weeks ago, recorded in
[`subset-name-contract-gate.md`](subset-name-contract-gate.md). Same shape, second site. Rows
12 and 13 are that; row 14–15's `addOrUpdate` is the **connective tail** the same issue
already rejects for `…Then…` / `…And…`; row 16 is a third kind, where the two moves do not
even take the same *kind* of argument.

**And `first(where:)` on both sides caps the template at one pair per (type, rule).** Two
measured exhibits, one in app code and one in a library:

- `RuleDetailViewModel` declares **three** genuine add/remove pairs — Disabled, OptIn, Only.
  The tool emits **one** row, and it is the wrong one.
- `GRDB.Database` declares **two** — `add(function:)`/`remove(function:)` at 777/783 and
  `add(collation:)`/`remove(collation:)` at 804/823. The tool emits one. Source order makes
  the emitted one correct here, so this cap costs a true law without producing a false one.

The template's own doc comment says this is the one template that keys on names and *"has
to"*, and that the convention is *"recorded as a first-class field so a reader can see which
convention fired and reject it."* That is honest about the risk, and it is still the risk:
the reader is shown `enterExit` and asked to audit a pairing the rule got wrong five times in
sixteen.

### 3.3 The fix has a measured constraint corpus A alone would have hidden

The shape is two changes to `InverseMutatorPairing.candidates` — **require the noun to agree,
not just the verb**, and **emit every matching pair rather than the first**. Scoring a naive
"the remainder after the stem must match" gate against all 16 rows:

- it **rejects all five** false rows, including `addOrUpdate` (remainder `OrUpdate`) and
  `add(_:)` × `removeObject(at:)` (`""` vs `Object`);
- but it also **rejects two true ones**, and both are in corpus B or would have been missed:
  `addToRecentWorkspaces` / `removeFromRecentWorkspaces` differ by the direction prepositions
  the conventions already imply, and swift-foundation's `push(value:)` / `popValue()` carries
  its noun in the **argument label** on one side and in the **name** on the other;
- and GRDB's `add(transactionObserver:)` / `remove(transactionObserver:)` has an **empty name
  remainder on both sides** — the noun is entirely in the label. A gate reading only the name
  admits it for the wrong reason, and would equally admit `add(function:)` ×
  `remove(collation:)`.

So the gate must strip direction prepositions, and must read `argumentLabels` as well as the
name. **Corpus A contains no example of either**: every noun there is in the name. This is
the constraint #476's own doc warns about — *"the transform list is deliberately short,
because a wrong entry withdraws a real law"* — arriving as a measurement rather than as
caution.

### 3.4 Recommendation

**Fix the pairing before writing the scaffold.** A scaffold writer built today would emit 11
honest scaffolds and 5 that name a pair the code does not owe, and would still never reach
the true laws the `first(where:)` cap hides. That is #466's failure mode — a stub whose
header states a law the reader then has to disbelieve — arriving through the pairing rather
than through the label.

⚠ **The fix is not proposed as shipped here and its cost is not fully measured.** 16 rows is
not a rate, and what the gate does to rows this scan did not reach is unmeasured. The A/B
#476 ran is the template for it: *same binary both sides, count the rows moved, and name the
one row the trim is evidence for.*

---

## 4. What this says about #468's direction

#468's closing line is *"Writers for `normal-form` and `comparator` first — highest entailed
count with a clear stub shape."* The count is the thing to be careful with. `normal-form`'s
39 on corpus A is **25 rows of one teaching file, 29 cross-type pairings across both lists,
and 6 real same-type rows** — of which five are measured vacuous. A declined-suggestion count
is an upper bound on what a writer frees, and this repo's own rule is to **state a gain as
rows moved, never laws gained**, at a measured ~5:1 against. Here it is worse than 5:1 before
a line is written.

**The measurement that would have said so is the one this page ran: look at the rows, on more
than one corpus list.** Both halves of #478 turned on reading the actual subjects — 60%
concentration in one file, five of sixteen pairs wrong, and 0 of 10,000 draws reaching the
best parser in the population — and none of that is visible from a count.
