# Reading a ternary into guard-domain — built, and it catches what it was built for

> **Status:** `measured` · **As of:** 2026-09-25

`law-blind-mutants.md` named the cheapest real law behind the mutation check's missed bugs: two mutants
swapped a literal in a function whose whole body is a ternary — `name == "*" ? "[*]" : name`,
`raw.isEmpty ? "relates" : raw` — and passed their idempotence law. The owed law is `guard-domain`'s own,
`cond ⟹ f(x) == literal`, and `GuardDomainReader` never saw it: it read a leading `guard` or `if`, never
a ternary. A second hole sat in front of it.

## Two changes, committed and measured separately

1. **A word inside quotes is not a free name.** `mentionsOnly` scanned text, so `"relates"` read as the
   identifier `relates` and every guard returning a word literal was refused. Plain literals are emptied
   before the scan; a literal that interpolates keeps its text, since `"\(name)"` does reach `name`.
2. **A body that is one ternary yields its law** — the then-branch firing when the condition holds, or,
   when the then-branch is the parameter itself (`cond ? x : literal`), the else-branch firing when it
   does not. The unfolded parse leaves `a ? b : c` as a sequence with an unresolved ternary in it; only a
   single top-level ternary is read, and the condition and returned branch pass the same `mentionsOnly`
   gates as the statement forms.

**Measured over 33,150 functions** (the 20 resolving manifest corpora plus the 19 funnel repositories,
`Sources/` only, every function through the reader): the statement form reads **211 → 232** guards with
the literal fix, and ternaries add **32**. Most are the intended shape — `colorScheme == .dark ⟹ .dark`,
`name.hasPrefix("$") ⟹ String(name.dropFirst())`. ⚠ One, `_offset`, slips the reader's recorded
underscore hole (`_base` is not counted as a free name); that hole is unchanged and affects the statement
form equally, and the stub writer declines such a name downstream.

**A full `make test` stayed green** — no recorded corpus baseline asserts the guard-domain count, so none
had to be re-taken.

## It catches the two mutants

The stubs `discover --interactive` writes for SwiftUMLStudio's two subjects, run with Xcode's toolchain:

| subject | law | original | recorded mutant | before (idempotence) | now |
|---|---|---|---|---|---|
| `StateScript.renderStateToken` | `name == "*" ⟹ f(name) == "[*]"` | passes | `name == ""` | DIVERGED, passed | **KILLED** at input `"*"` |
| `ERScript.sanitizeLabel` | `raw.isEmpty ⟹ f(raw) == "relates"` | passes | `raw.isEmpty ? "" : raw` | DIVERGED, passed | **KILLED** at input `""` |

Neither reports NOT APPLIED, so the draws enter each guard. The `"*"` counterexample is a subject literal,
drawn since kit 4.8.0; the `""` is an edge token.

⚠ **This is a characterisation law** (`Refutability.characterisationTemplates`): a pass says the guarded
answer is what the code returns today, not that it is right. It catches an edit that changes that answer,
which is exactly what both mutants were.
