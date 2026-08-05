import SwiftEffectInference

/// Structured record produced by `FunctionScanner` for every function
/// declaration found in a Swift source file. Carries the header info the
/// scoring engine (M1.3+) needs to evaluate templates against, plus a
/// small set of body-derived signals computed by the M1.2 scanner via
/// type-flow lite (PRD §5.3).
///
/// `FunctionSummary` is intentionally textual — types and return signatures
/// are captured as their source representation. Full semantic resolution
/// (canonical type names, generic substitution) lives in v1.1's
/// constraint-engine upgrade per PRD §20.2.
public struct FunctionSummary: Sendable, Equatable {

    /// Function name as written, without the parameter-label suffix
    /// (e.g. `"normalize"`, not `"normalize(_:)"`).
    public let name: String

    /// Parameters in declaration order.
    public let parameters: [Parameter]

    /// Trimmed source representation of the return type, or `nil` when the
    /// declaration omits a return clause (implicit `Void`). `Void` written
    /// explicitly is preserved as `"Void"`.
    public let returnTypeText: String?

    /// `true` when the declaration carries `throws` or `rethrows`.
    public let isThrows: Bool

    /// `true` when the declaration carries `async`.
    public let isAsync: Bool

    /// `true` when the declaration carries `mutating`.
    public let isMutating: Bool

    /// `true` when the declaration carries `static` or `class` (the latter
    /// being class-method static).
    public let isStatic: Bool

    /// File-relative source location of the function's `func` keyword.
    public let location: SourceLocation

    /// Name of the innermost containing type, or `nil` for top-level
    /// functions. Extension declarations contribute the `extendedType`
    /// (e.g. `"Array"` for `extension Array`); nested types stack so the
    /// innermost wins.
    public let containingTypeName: String?

    /// Body-derived type-flow signals (PRD §5.3).
    public let bodySignals: BodySignals

    /// Group identifier from a `@Discoverable(group: "...")` attribute on
    /// the function decl, when the user has tagged it. `nil` when the
    /// function carries no `@Discoverable` attribute or the attribute
    /// has no `group:` argument. PRD §5.7 + §4.1: SwiftInferProperties
    /// recognizes the attribute *by name match* during the SwiftSyntax
    /// walk — no runtime dep on `PropertyLawMacro`. Two functions sharing
    /// the same non-nil `discoverableGroup` earn a `+35` cross-pair
    /// signal at the round-trip-template scoring layer.
    /// Defaults to `nil` so M1–M4 call sites that don't yet populate
    /// the field compile unchanged.
    public let discoverableGroup: String?

    /// Keypath text from a `@CheckProperty(.preservesInvariant(\.foo))`
    /// attribute on the function decl, when the user has tagged it. `nil`
    /// when the function carries no such attribute or the attribute's
    /// argument isn't a well-formed key-path literal. PRD §5.2 +
    /// M7.2 plan row: SwiftInferProperties recognizes the attribute by
    /// name match (same posture as `discoverableGroup`); the keypath is
    /// captured opaquely as source text per M7 plan open decision #5(a).
    /// `InvariantPreservationTemplate` fires only when this field is
    /// non-nil — there is no naming/type-pattern fallback. Defaults to
    /// `nil` so call sites that don't yet populate the field compile
    /// unchanged.
    public let invariantKeypath: String?

    /// `true` when `SoundPurity` infers this function is `Effect.pure` —
    /// referentially transparent (no side effects, deterministic, total).
    /// Computed once at scan time, where the `FunctionDeclSyntax` is live,
    /// and consumed by the advisory channel that recommends a
    /// `/// @lint.effect pure` annotation (`DiscoverArtifacts.effectAnnotations`).
    /// Defaults to `false` so call sites that don't populate it compile
    /// unchanged.
    public let isInferredPure: Bool

    /// `true` when the declaration carries SwiftEffectInference's
    /// clock-determinism marker (`/// @lint.determinism clock_deterministic`
    /// or `@ClockDeterministic`) — a user-declared claim that this `async`
    /// function is deterministic given an injected `Clock`. Computed once at
    /// scan time like `isInferredPure`, and consumed by the async-veto
    /// relaxation (collections/async workplan Phase 4 deferral close-out):
    /// vetoes relax only on the *conjunction* of this claim with the local
    /// gates staying quiet. Content-blind — presence is a claim the emitted
    /// determinism law then checks, not an analysis result. Defaults to
    /// `false` so call sites that don't populate it compile unchanged.
    public let isClockDeterministic: Bool

    /// Recall-widening epic #1 — true when this summary was synthesized from a
    /// read-only COMPUTED PROPERTY (`var conjugate: Self`), modelled as a nullary
    /// `self -> T` method. The verify emitter reads it to emit a property access
    /// (`value.conjugate`) rather than a call (`value.conjugate()`).
    public let isComputedProperty: Bool

    /// Case 7 Part 2 — true when this summary was synthesized from an
    /// **initializer** (`init?(base64Encoded: String)`), modelled as the decode
    /// half of a codec: a function `paramType -> Self`. Set only on the
    /// synthetic summaries `InitializerDecodeSynthesizer` feeds into the
    /// round-trip pairing input — never on a scanned declaration — so the
    /// general per-summary template pass never sees them. `RoundTripTemplate`
    /// reads it to fire the label-stem name signal and to disclose that a
    /// failable initializer's round-trip law is `decode(encode(x)) == .some(x)`.
    /// Defaults to `false`.
    public let isInitializer: Bool

    /// The function's leading documentation comment, reflowed to plain prose —
    /// `///` line markers and `/** */` fences stripped, lines joined — or `nil`
    /// when the declaration carries no doc comment. Captured verbatim and left
    /// **unclassified**: whether the text states a refutable *contract*
    /// ("returns the nearest multiple, ties upward") or merely *narrates*
    /// ("a helper for the retry loop") is decided downstream by the docstring
    /// advisory, next to `Refutability`, not here — `FunctionSummary` stays
    /// textual by design (see the type header). The advisory reads this as a
    /// candidate **reference definition**: the sentence a `predicate` law owes,
    /// the spec a lifted example test needs, or the only contract on a function
    /// the templates could offer nothing but a tautology for. Defaults to `nil`
    /// so call sites that don't populate it compile unchanged.
    public let docComment: String?

    /// The idempotency effect the *author* declared, via either spelling of
    /// SwiftIdempotency's vocabulary — the attribute form (`@Idempotent`,
    /// `@NonIdempotent`, `@Observational`, `@ExternallyIdempotent(by:)`,
    /// `@Pure`) or the dependency-free doc-comment form
    /// (`/// @lint.effect idempotent`). `nil` when the declaration carries no
    /// claim, which is the overwhelmingly common case.
    ///
    /// **Read, not inferred.** This is a human's assertion about their own
    /// code, in the same posture as `isClockDeterministic` above: presence is
    /// a claim a law can then check, never an analysis result. It is
    /// deliberately the *whole* `Effect` rather than a pair of booleans,
    /// because the tiers are a retry-safety lattice and a consumer that wants
    /// "is this idempotent" must also be able to see `externallyIdempotent`,
    /// which asserts idempotence **only** through a caller-supplied dedup key
    /// — a distinction this repo previously had no way to express at all.
    ///
    /// Parsed by `EffectAnnotationParser`, which SwiftInferCore already
    /// depends on and until now called for exactly one thing
    /// (`isClockDeterministic`). Note the two are separate axes and the
    /// parser keeps them apart: `@lint.determinism` is a determinism claim,
    /// `@lint.effect` a retry-safety one.
    public let declaredEffect: Effect?

    /// The retry-hostile effect resolved from this function's **body**, when
    /// `EffectResolver` ran and found one — a `@NonIdempotent` callee makes its
    /// caller non-idempotent, and nothing on this declaration says so.
    ///
    /// **Never populated by the scan**, and `nil` on every default-path run: the
    /// pass that fills it is opt-in (`discover --resolve-effects`) because it
    /// re-parses the whole tree. Distinct from `declaredEffect` rather than
    /// merged into it, because the two are different evidence and the templates
    /// treat them differently — a declaration is the author denying the law, an
    /// inference is a fact about a callee, which is one step removed from the
    /// law's own subject.
    ///
    /// Only ever `nonIdempotent` or `externallyIdempotent`: an inferred
    /// `pure`/`idempotent` is the *lub* of what a body calls and says nothing
    /// about the caller (`f(x) = g(x) + 1` with pure `g` infers pure and is not
    /// idempotent), so `EffectResolver` discards it rather than manufacture
    /// corroboration from an absence.
    public let inferredEffect: Effect?

    /// The three-state purity verdict, where `isInferredPure` above is its
    /// two-state collapse. `.refuted` for a summary nobody computed one for.
    ///
    /// `isInferredPure` is `purityVerdict == .pure` and stays the field every
    /// current consumer reads — the `/// @lint.effect pure` advisory is the only
    /// one, and it must not change. What this adds is the state that collapse
    /// destroys: **`.pureButPartial`**, a function that is deterministic and
    /// side-effect-free but raises its own errors, so it is pure over the inputs
    /// it accepts and simply not total.
    ///
    /// Measured 2026-08-04 on this repo: 2,206 `.pure`, **35 `.pureButPartial`**,
    /// 259 `.refuted` of 2,500. Small, and previously invisible — `isPure`
    /// answered `false` for all 294 non-pure functions alike, so nothing
    /// downstream could tell "reads the clock" from "throws its own error".
    public let purityVerdict: PurityVerdict

    public init(
        name: String,
        parameters: [Parameter],
        returnTypeText: String?,
        isThrows: Bool,
        isAsync: Bool,
        isMutating: Bool,
        isStatic: Bool,
        location: SourceLocation,
        containingTypeName: String?,
        bodySignals: BodySignals,
        discoverableGroup: String? = nil,
        invariantKeypath: String? = nil,
        isInferredPure: Bool = false,
        isClockDeterministic: Bool = false,
        isComputedProperty: Bool = false,
        isInitializer: Bool = false,
        docComment: String? = nil,
        declaredEffect: Effect? = nil,
        inferredEffect: Effect? = nil,
        purityVerdict: PurityVerdict = .refuted
    ) {
        self.name = name
        self.parameters = parameters
        self.returnTypeText = returnTypeText
        self.isThrows = isThrows
        self.isAsync = isAsync
        self.isMutating = isMutating
        self.isStatic = isStatic
        self.location = location
        self.containingTypeName = containingTypeName
        self.bodySignals = bodySignals
        self.discoverableGroup = discoverableGroup
        self.invariantKeypath = invariantKeypath
        self.isInferredPure = isInferredPure
        self.isClockDeterministic = isClockDeterministic
        self.isComputedProperty = isComputedProperty
        self.isInitializer = isInitializer
        self.docComment = docComment
        self.declaredEffect = declaredEffect
        self.inferredEffect = inferredEffect
        self.purityVerdict = purityVerdict
    }
}

/// One parameter of a `FunctionSummary`. Captures the label/name distinction
/// Swift parameters carry: an external label (or no-label `_`) and an
/// internal binding name.
public struct Parameter: Sendable, Equatable {

    /// External argument label as the caller writes it. `nil` when the
    /// declaration uses `_` to suppress the label.
    public let label: String?

    /// Internal binding name used inside the function body.
    public let internalName: String

    /// Trimmed source representation of the parameter's type, with any
    /// `inout` specifier stripped. `inout` is captured separately in
    /// `isInout`.
    public let typeText: String

    /// `true` when the parameter is declared `inout`.
    public let isInout: Bool

    /// `true` when the declaration supplies a default value
    /// (`func formatted(using format: BasicFormat = BasicFormat())`).
    ///
    /// The distinction this records is **operand vs configuration**. A
    /// defaulted parameter is one the caller may omit, so `x.formatted()` is a
    /// legal call and the method reads as a unary transform of `self` that
    /// happens to be configurable. A required parameter is part of the
    /// operation's arity and cannot be elided.
    ///
    /// Added for the erased-self-form arm of `IdempotenceTemplate`
    /// (`docs/parsing-catalog-gap.md` §4/§5): `SyntaxProtocol.formatted(using:)`
    /// was rejected partly because the self-form gate required
    /// `parameters.isEmpty`, which a *configuration* parameter should not
    /// trip. Defaults to `false` so every existing call site — including the
    /// hand-built `Parameter`s across the test suites — compiles unchanged.
    public let hasDefault: Bool

    public init(
        label: String?,
        internalName: String,
        typeText: String,
        isInout: Bool,
        hasDefault: Bool = false
    ) {
        self.label = label
        self.internalName = internalName
        self.typeText = typeText
        self.isInout = isInout
        self.hasDefault = hasDefault
    }
}

/// File-relative source location. `file` is the path passed to
/// `FunctionScanner.scan(source:file:)`; `line` and `column` are 1-based.
public struct SourceLocation: Sendable, Equatable, Hashable {

    public let file: String
    public let line: Int
    public let column: Int

    public init(file: String, line: Int, column: Int) {
        self.file = file
        self.line = line
        self.column = column
    }
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

    public init(
        hasNonDeterministicCall: Bool,
        hasSelfComposition: Bool,
        nonDeterministicAPIsDetected: [String],
        reducerOpsReferenced: [String] = [],
        reducerOpsWithIdentitySeed: [String] = [],
        equalityBodyShape: EqualityBodyShape? = nil,
        idempotenceReturnShape: IdempotenceReturnShape? = nil
    ) {
        self.equalityBodyShape = equalityBodyShape
        self.idempotenceReturnShape = idempotenceReturnShape
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
