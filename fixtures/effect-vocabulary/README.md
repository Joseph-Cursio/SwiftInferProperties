# The attribute-grammar join, made checkable

`swiftidempotency-peer-macros.json` is the cross-repo half of open item 4.

## The problem it closes

swift-infer recognises SwiftIdempotency's annotations **by name** — `@Idempotent`,
`@NonIdempotent`, `@ExternallyIdempotent` — and deliberately does **not** depend on that
package: the doc-comment spelling needs no dependency, and the attribute is matched as a string.
So the two vocabularies are joined by nothing a compiler can see.

That was tolerable while swift-infer only *read* one word. It stopped being tolerable when
[#78](https://github.com/Joseph-Cursio/SwiftInferProperties/pull/78) made `IdempotenceTemplate`
**veto** on these names: a rename upstream no longer fails loudly, it silently stops suppressing a
false law — and a suggestion that was suppressed and now is not looks exactly like a codebase that
never annotated anything.

`EffectVocabularyContractTests` already pins the spellings *this* repo is keyed to. What it could
not do is assert they equal what SwiftIdempotency actually ships. That is this file.

## Why the rule is derivable rather than curated

The macro set splits **structurally**, so nothing here rests on judgement:

| attachment | macros | is it effect vocabulary? |
|---|---|---|
| `@attached(peer)` | `ClockDeterministic`, `EffectUnknown`, `ExternallyIdempotent`, `Idempotent`, `NonIdempotent`, `Observational`, `Pure` | **yes** — this manifest |
| `@attached(extension, names: arbitrary)` | `IdempotencyTests` | no — generates tests |
| `@freestanding(expression)` | `assertIdempotent` | no — a call-site helper |

A hand-written list of "the ones that count" would drift by opinion. `@attached(peer)` is a fact
about the declaration.

## What the test asserts, and why it is an EQUALITY

`EffectVocabularyCrossRepoTests` checks that swift-infer's recognised set equals the manifest's
peer macros **minus a named exclusion list**. Equality, not subset, because the two directions fail
differently and both matter:

- a name **disappearing** upstream is the rename that silently disarms the veto;
- a name **appearing** upstream is a vocabulary swift-infer does not read.

The second is not hypothetical. **Item 20 is exactly that case**: SwiftIdempotency shipped
`@EffectUnknown` and no tool distinguishes it from an unannotated declaration. A test of this shape
would have said so the day it landed, instead of it being noticed later and filed by hand.

## Regenerating

```bash
python3 - <<'PY'
import re, json, subprocess, pathlib
root = pathlib.Path("../SwiftIdempotency/Sources")
sha = subprocess.run(['git','-C','../SwiftIdempotency','rev-parse','HEAD'],
                     capture_output=True, text=True).stdout.strip()
peers = sorted({m.group(1)
                for f in root.rglob("*.swift")
                for m in re.finditer(r'@attached\(peer\)\s*\npublic macro (\w+)', f.read_text())})
pathlib.Path("fixtures/effect-vocabulary/swiftidempotency-peer-macros.json").write_text(
    json.dumps({"_comment": "DERIVED, not hand-written. Regenerate with the script in README.md.",
                "repo": "SwiftIdempotency", "sha": sha, "capturedAt": "<today>",
                "rule": "@attached(peer) public macro — the effect-annotation vocabulary",
                "peerMacros": peers}, indent=2) + "\n")
PY
```

## The honest limit

**A checked-in manifest can go stale, which is the failure mode it exists to prevent.** Two things
bound that, neither perfect:

1. **The freshness test re-derives from `../SwiftIdempotency` when that checkout exists** and fails
   if it disagrees with this file. On a machine with the siblings checked out — which is where this
   toolchain is developed — a rename is caught the next time the suite runs.
2. **`make docs-drift` already watches sibling movement** and reports SwiftIdempotency commits since
   a recorded SHA. It is the standing detector for "the manifest may be stale".

Without the sibling checkout the freshness half cannot run, and the suite says so rather than
passing quietly. That is a real gap, not a solved one: it means CI alone would not catch an upstream
rename.
