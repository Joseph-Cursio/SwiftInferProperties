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

    /// The full lexical type path — `"SwiftInferCommand.Scaffold"` where
    /// `containingTypeName` is `"Scaffold"`. `nil` for top-level functions.
    ///
    /// **Why both.** The bare-name sidecars are keyed on the innermost frame, so
    /// it cannot change without changing every key — but that frame is not always
    /// a name that RESOLVES: a stub writing `Inner.method(…)` for a lexically
    /// nested type gets *cannot find 'Inner' in scope*, while the same type
    /// written as `extension Outer.Inner` records the dotted path. The old
    /// behaviour was **spelling-dependent**, the family `assumedCoverageSignal`'s
    /// `"Self"` belongs to.
    public let qualifiedContainingTypeName: String?

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

    /// The author declared the effect **cannot be determined** (`@EffectUnknown`
    /// / `/// @lint.effect unknown`).
    ///
    /// Separate from `declaredEffect` because `unknown` is **not** an `Effect` —
    /// incomparable to `nonIdempotent`, so SEI reads it with its own predicate
    /// rather than admitting it to a linear chain. Same orthogonal-axis posture
    /// as `isClockDeterministic`. **Not a weaker `@NonIdempotent`**: that denies
    /// the law and vetoes; this claims nothing about it. See
    /// `IdempotenceTemplate.unknownEffectCaveat`.
    public let declaresUnknownEffect: Bool

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
    ///
    /// **Two warnings before you count `.refuted` rows.** First, `.refuted` is
    /// still three cases wearing one: re-measured 2026-08-17, **54% of it names
    /// nothing in the source at all** and is the analyzer reporting its own
    /// blindness (`docs/measurements/purity-refuted-bucket-census.md`). Second,
    /// and worse for a count — *"`.refuted` for a summary nobody computed one
    /// for"* above is not a rare edge: `makeSummary(fromComputedProperty:)`
    /// passes no verdict, so **every** read-only computed property lands here by
    /// default while carrying `isInferredPure == true`, which is the exact
    /// combination this field's first paragraph says cannot happen. 180 of them
    /// under `Sources/`. Filter on `isComputedProperty` before reading this.
    public let purityVerdict: PurityVerdict

    /// Fingerprint of this function's BODY, for validating verify evidence against the code
    /// it was measured on. `nil` for summaries built without a body (a protocol requirement,
    /// or one of the many hand-built summaries in tests).
    ///
    /// Deliberately **not** part of `SuggestionIdentity`: identity must survive refactors
    /// (PRD §7.5 skip markers, §16 #1), and this must not. See `SubjectFingerprint`.
    public let bodyFingerprint: String?

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
        qualifiedContainingTypeName: String? = nil,
        discoverableGroup: String? = nil,
        invariantKeypath: String? = nil,
        isInferredPure: Bool = false,
        isClockDeterministic: Bool = false,
        declaresUnknownEffect: Bool = false,
        isComputedProperty: Bool = false,
        isInitializer: Bool = false,
        docComment: String? = nil,
        declaredEffect: Effect? = nil,
        inferredEffect: Effect? = nil,
        purityVerdict: PurityVerdict = .refuted,
        bodyFingerprint: String? = nil
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
        self.qualifiedContainingTypeName = qualifiedContainingTypeName ?? containingTypeName
        self.discoverableGroup = discoverableGroup
        self.invariantKeypath = invariantKeypath
        self.isInferredPure = isInferredPure
        self.isClockDeterministic = isClockDeterministic
        self.declaresUnknownEffect = declaresUnknownEffect
        self.isComputedProperty = isComputedProperty
        self.isInitializer = isInitializer
        self.docComment = docComment
        self.declaredEffect = declaredEffect
        self.inferredEffect = inferredEffect
        self.purityVerdict = purityVerdict
        self.bodyFingerprint = bodyFingerprint
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
    /// (`docs/measurements/parsing-catalog-gap.md` §4/§5): `SyntaxProtocol.formatted(using:)`
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
