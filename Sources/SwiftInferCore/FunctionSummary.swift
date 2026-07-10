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
        isClockDeterministic: Bool = false
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

    public init(
        label: String?,
        internalName: String,
        typeText: String,
        isInout: Bool
    ) {
        self.label = label
        self.internalName = internalName
        self.typeText = typeText
        self.isInout = isInout
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

    public init(
        hasNonDeterministicCall: Bool,
        hasSelfComposition: Bool,
        nonDeterministicAPIsDetected: [String],
        reducerOpsReferenced: [String] = [],
        reducerOpsWithIdentitySeed: [String] = []
    ) {
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
        reducerOpsWithIdentitySeed: []
    )
}
