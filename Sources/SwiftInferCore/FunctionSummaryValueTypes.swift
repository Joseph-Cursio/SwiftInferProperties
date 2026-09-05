import Foundation

// The two value types a `FunctionSummary` is built from, split out when that
// file hit SwiftLint's 400-line cap. They travel together: `SourceLocation` is
// where a declaration is, `BodySignals` is what its body does, and both are
// consumed only through a summary.

/// File-relative source location. `file` is the path passed to
/// `FunctionScanner.scan(source:file:)`; `line` and `column` are 1-based.
public struct SourceLocation: Sendable, Equatable, Hashable, Comparable, CustomStringConvertible {

    public let file: String
    public let line: Int
    public let column: Int

    public init(file: String, line: Int, column: Int) {
        self.file = file
        self.line = line
        self.column = column
    }

    /// Source order: by file, then line, then column.
    ///
    /// Five comparators across the template pairings spelled this out by hand, each as a ladder of
    /// `if lhs.x.location.file != rhs.x.location.file { … }`. Beyond being the chain the Law of
    /// Demeter rule names, every one of them stopped at `line` and ignored `column` — so two
    /// declarations on the same line compared *equal*, and their relative order in the generated
    /// output fell to `sorted(by:)`. Swift does not guarantee that sort is stable, so nothing
    /// pinned the order of a tie in a file people read as a diff.
    ///
    /// Including `column` makes the order total over distinct locations, which is what the callers
    /// were reaching for. It is stated once here rather than five times, and
    /// `SourceLocationOrderingTests` holds it to the strict-weak-ordering laws a comparator handed
    /// to `sorted(by:)` has to satisfy.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.file, lhs.line, lhs.column) < (rhs.file, rhs.line, rhs.column)
    }

    /// The location `Slicer` emits when it has no `SourceLocationConverter` —
    /// `<test-body>:0`. Declared here, and referenced by both the producer
    /// (`Slicer.location(of:)`) and the consumer that must recognise it
    /// (`LiftedSuggestion.makeExplainability`), so the two cannot drift into
    /// disagreeing about what "unknown" looks like.
    ///
    /// **A placeholder that reaches a user is a bug**, and this one did: every
    /// lifted row rendered `Lifted from <test-body>:0` while source-derived rows
    /// carried `file.swift:line`. That is what let the package-wide test-lifting
    /// defect hide — a row citing `render(suggestion)` on `SwiftInferKitEvidence`
    /// is only obviously wrong if it names the file it came from
    /// (`docs/measurements/roadtest-self-dogfood-2026-08-08.md` §7.4).
    public static let testBodyPlaceholder = Self(file: "<test-body>", line: 0, column: 0)

    /// Whether this location can be shown to a user as provenance. False for the
    /// slicer placeholder and for the corpus-level `<corpus>` origin, both of which
    /// name no file a reader could open.
    public var isResolvable: Bool {
        line > 0 && !file.hasPrefix("<")
    }

    /// `file:line` — the provenance string a reader sees.
    ///
    /// Forty-one call sites built this by hand as `"\(x.location)"`, which
    /// is both the chain the Law of Demeter rule names and a format this type already treats as
    /// load-bearing: the `testBodyPlaceholder` doc above records a real defect where lifted rows
    /// rendered `<test-body>:0` while source-derived rows carried `file.swift:line`, and the
    /// mismatch is what let a package-wide bug hide.
    ///
    /// A format that matters that much belongs on the type rather than at forty-one call sites.
    ///
    /// **Not the same thing as a join key.** `Discover+CaveatPostProcessing.coordinate(of:)` builds
    /// `file#line` deliberately, for matching rather than display, and is left alone.
    public var description: String { "\(file):\(line)" }
}

/// Type-flow-lite signals computed from a function's body. Empty / all-false
/// when the function declaration has no body (e.g. protocol requirements).
public struct BodySignals: Sendable, Equatable {

    /// `true` when the body invokes any API in the curated
    /// non-deterministic list (PRD §4.1's -∞ counter-signal). Drives
    /// the structural disqualifier for idempotence and most algebraic
    /// claims (Appendix B.3).
    public let hasNonDeterministicCall: Bool

    /// `true` when the body contains a self-composition pattern of the form
    /// `f(f(x))` where `f` is the function's own name. Feeds the
    /// idempotence type-flow signal (PRD §5.3, +20).
    public let hasSelfComposition: Bool

    /// Distinct callee texts that matched the non-deterministic list,
    /// preserved for explainability rendering (M1.3+). Sorted alphabetically
    /// for deterministic output.
    public let nonDeterministicAPIsDetected: [String]

    /// Distinct function names referenced as the closure-position argument
    /// of `.reduce(_, X)` calls in this body (e.g. `xs.reduce(0, add)` or
    /// `xs.reduce(into: 0, MyType.combine)` records `add` and `combine`).
    /// Feeds the associativity template's reducer/builder-usage signal
    /// (PRD §5.3, +20). Sorted alphabetically for deterministic output;
    /// the corpus-level union is computed at template-discovery time.
    public let reducerOpsReferenced: [String]

    /// Subset of `reducerOpsReferenced` whose `.reduce(seed, op)` call site
    /// uses an identity-shaped seed — `0`, `0.0`, `""`, `[]`, `[:]`, `nil`,
    /// `false`, or a member-access reference whose leaf name is in the
    /// curated identity list (`.empty`, `.zero`, `.identity`, `.none`,
    /// `.default`). Feeds the identity-element template's
    /// accumulator-with-empty-seed signal (PRD §5.3, +20). Sorted
    /// alphabetically for deterministic output.
    public let reducerOpsWithIdentitySeed: [String]

    /// What a `static func ==` body actually does, when this summary IS one.
    /// `nil` for every other function — the classification is only computed for
    /// `==`, so the scan cost is paid once per Equatable conformance rather than
    /// once per function.
    ///
    /// `fixtures/equatable-signal` measured that conformance does not predict
    /// refutability and the **body shape** does; this is that measurement made
    /// available to templates.
    public let equalityBodyShape: EqualityBodyShape?

    /// What a `T -> T` function's returned expression does to its input, when
    /// this summary IS one. `nil` for every other shape — classifying every body
    /// would pay a walk per function for a signal one template reads, the same
    /// bargain `equalityBodyShape` above makes.
    ///
    /// Read `IdempotenceReturnShape` for why the RETURN expression alone decides
    /// it: a body-wide scan calls `quoted` a normalizer (it calls
    /// `replacingOccurrences` before wrapping) and calls a dedup an extender (it
    /// appends while filtering). Both readings are wrong and both come from
    /// looking in the wrong place.
    public let idempotenceReturnShape: IdempotenceReturnShape?

    /// A dedup gate (early-return / fetch-then-insert) in a side-effecting
    /// handler's body, when this summary IS one. `nil` for every other shape —
    /// computed only for `throws`/`async` functions (the M2 gate), the same
    /// pay-the-walk-only-where-read bargain `idempotenceReturnShape` above makes.
    /// Read by `ReplayIdempotenceTemplate`'s Branch C.
    public let dedupGateShape: DedupGateShape?

    /// The body constructs an `IdempotencyKey(…)` — the key-from-entity builder
    /// shape (M6). Read by `ReplayIdempotenceTemplate`'s key-builder branch; the
    /// property is that the built value is stable across invocations.
    public let buildsIdempotencyKey: Bool

    /// The body calls an idempotent-write primitive (`upsert`, `firstOrCreate`, …)
    /// — idempotent by the operation's guarantee (M10). Read by
    /// `ReplayIdempotenceTemplate`'s idempotent-write branch.
    public let callsIdempotentWrite: Bool

    public init(
        hasNonDeterministicCall: Bool,
        hasSelfComposition: Bool,
        nonDeterministicAPIsDetected: [String],
        reducerOpsReferenced: [String] = [],
        reducerOpsWithIdentitySeed: [String] = [],
        equalityBodyShape: EqualityBodyShape? = nil,
        idempotenceReturnShape: IdempotenceReturnShape? = nil,
        dedupGateShape: DedupGateShape? = nil,
        buildsIdempotencyKey: Bool = false,
        callsIdempotentWrite: Bool = false
    ) {
        self.equalityBodyShape = equalityBodyShape
        self.idempotenceReturnShape = idempotenceReturnShape
        self.dedupGateShape = dedupGateShape
        self.buildsIdempotencyKey = buildsIdempotencyKey
        self.callsIdempotentWrite = callsIdempotentWrite
        self.hasNonDeterministicCall = hasNonDeterministicCall
        self.hasSelfComposition = hasSelfComposition
        self.nonDeterministicAPIsDetected = nonDeterministicAPIsDetected
        self.reducerOpsReferenced = reducerOpsReferenced
        self.reducerOpsWithIdentitySeed = reducerOpsWithIdentitySeed
    }

    /// Empty signals — used for functions without bodies.
    public static let empty = Self(
        hasNonDeterministicCall: false,
        hasSelfComposition: false,
        nonDeterministicAPIsDetected: [],
        reducerOpsReferenced: [],
        reducerOpsWithIdentitySeed: [],
        equalityBodyShape: nil
    )
}
