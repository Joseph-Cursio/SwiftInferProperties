# guard-domain's free-name gate reads syntax: +52 rows, −2 false ones

> **Status:** `measured` · **As of:** 2026-11-11

`GuardDomainReader.mentionsOnly` decides whether a guard's condition and its returned expression mention only
the parameter, so that a test can state the law. It used to scan **text** and read any identifier not preceded
by `.` as free. The #670 census (`docs/measurements/count-threshold-boundary-census.md`, *The gate A/B*) found
two ways that text scan was wrong:
- it refused sites whose every name a stub can bind;
- it admitted a law about the receiver as if it were about the argument.

It now reads the **syntax** (`Sources/SwiftInferCore/GuardDomainFreeNames.swift`):

- **Never free:** argument labels, members, key-path components, a closure's own parameters (`$0`, `{ x in … }`),
  words inside a string literal, and keywords (`unsafe`, `try`, `is`).
- **Free:** `super`, a macro (`#line`), a `$`-projection (`$user` keeps its `$`), and any other name.
- **Unchanged:** types count as names, and are allowed only in the returned expression, as before.

The writer's text rebinding (`GuardDomainRebinding`) agrees on the one case where the two could diverge. It now
scans `$user` as one unbound name, so a projection is never rebound as the parameter `user`. It already passed
labels and literals through.

## The A/B

The harness is `fixtures/count-threshold/census-run/` in `ab` mode → `fixtures/guard-domain-syntax-gate/ab-2026-11-11.json`.
It compares the shipped reader with the census harness's text-gate replica (the reader before this change) over
the same universe as the #670 census. That is 31,022 functions; 6 more than the census, because this change adds
functions to `SwiftInferCore`, which is in the universe.

| | reader rows |
|---|---|
| before (text gate) | 265 |
| after (syntax gate) | 315 |
| gained | 52, of which 33 guard-domain would propose |
| lost | 2, both template-eligible, both false |
| read differently | 0 |

**Read differently = 0** means no admitted row changed its condition, returned expression or direction. Only
the gate moved.

### The 33 gains guard-domain would propose

What the text gate tripped on:

| cause | rows | the writer binds every name |
|---|---|---|
| argument labels (`contains(anyOf:)`, `isIdentical(to:)`, `shouldTraverse(node:)`, `contains(where: { $0… })`, memberwise inits such as `ConfidenceSignal(source:weight:passed:detail:)`) | 27 | 24 |
| words inside an interpolated or multi-line literal (`"it extends \(name), which is @MainActor"`, pbt-workbook-corpus's `"\(count) item"` twice, a SwiftAssist message) | 4 | 4 |
| the `unsafe` keyword (stdlib `NativeDictionary`/`NativeSet.isEqual`) | 2 | 0 |

**The writer binds every name in 28 of the 33,** over 9 repositories, the largest SwiftAssist with 9. It binds
parameters, `self`, `Self`, and the types the signature names. It declines the other 5, naming the name:

- 3 return a type the signature does not name: GRDB's `SuffixRowAdapter`, swift-foundation's `UInt64` (also an
  `inout` subject), and SwiftProjectLint's `Int`.
- 2 contain `unsafe`, which the writer's text scan reads as a name.

Both declines are conservative and are left as they are.

**Every one of the 33 was read against its source.** Each condition and returned expression is the function's
own first statement, or its single ternary. These are characterisation laws, true by construction, as guard-domain
always says.

**Checked end to end** on pbt-workbook-corpus: `discover --include-possible` now proposes
`(count == 1) ⟹ describe(count) == "\(count) item"` for `CorrectPluralizer.describe(_:)` at **Likely (40)**,
so the gains reach default output and not only `--include-possible`.

### The 2 losses: false admissions, now refused

MacCloud_server's `File.canAccess(user:)` and `canWrite(user:)` open with `if user.id == $user.id { return true }`.
`$user` is the Fluent model's `@Parent` projection, which is state of the receiver. The text gate read it as the
parameter `user` and proposed `user.id == $user.id ⟹ canAccess(user) == true`, a law about the file rather than
about the argument. Its stub would have rebound `$user` to `$arg1`.

### Found by the prototype, fixed before shipping

The census's prototype gate admitted swift-format's `if node.arguments.count == 0 { return super.visit(node) }`,
twice, because `super` is not a `DeclReferenceExpr`. The shipped gate counts `super` as free, and those two rows
are refused (52 gained here against the prototype's 54).

## Tests

`Tests/SwiftInferCoreTests/GuardDomainSyntaxGateTests.swift` covers:
- the projection is refused;
- `super` is refused;
- a labelled call and an interpolated literal with words are admitted;
- a name inside an interpolation is still free;
- closure parameters are bound;
- helpers, types in a condition and macros are still free;
- the writer does not rebind `$user`.

`GuardDomainReader.isName` and `withoutPlainStringLiterals` went with the text scan; the `isName` test went with
them.

⚠ **The #670 census harness's `controls` mode is tied to the reader before this change.** It requires its
text-gate replica to agree with the shipped reader on guard-domain's test fixtures, and the new tests above
disagree on purpose. The census is reproduced at its own commit (`d963b5d6`), and the `ab` mode runs no
controls.
