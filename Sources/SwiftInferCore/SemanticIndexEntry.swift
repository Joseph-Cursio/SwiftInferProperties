import Foundation

/// V1.33.A — one row of the SemanticIndex (PRD §20.1). A pure value type
/// recording an inferred property suggestion alongside the user's
/// triage decision (if any) and the first/last times the indexer saw
/// the signature.
///
/// **Schema rationale.** The PRD §20.1 sketch is `(typeId, templateId,
/// score, evidenceJson, decisionAt, lastSeenAt)`. v1.33 expands the
/// rough sketch into structured columns the rest of the codebase
/// already produces:
///   - `typeId → typeName`: the carrier type, optional for free
///     functions.
///   - `templateId → templateName`: the template's stable string id.
///   - `evidenceJson` → structured `primaryFunctionName` + `location`:
///     enough surface for human-readable output without re-loading the
///     full suggestion. The full evidence is recoverable from a fresh
///     discover run.
///   - `decisionAt` is preserved + `decision` is added so queries can
///     filter on accept/reject/skip without joining against
///     `.swiftinfer/decisions.json`.
///   - `firstSeenAt` is new: enables "what appeared since" queries.
///
/// `identityHash` is the suggestion identity hex (the V1.7.5 PRD §7.5
/// canonical-input hash) and serves as the upsert key. Two runs of
/// `swift-infer index` against the same corpus produce stable
/// identityHashes; upsert preserves `firstSeenAt` while updating the
/// rest.
public struct SemanticIndexEntry: Codable, Sendable, Equatable {

    /// Suggestion identity hex (the V1.7.5 PRD §7.5 canonical-input
    /// hash). The upsert key. Format: 16-char uppercase hex with `0x`
    /// prefix, e.g. `"0xBC43359C0574816B"`.
    public var identityHash: String

    /// Template name as it appears in discover output. One of
    /// `"round-trip"`, `"idempotence"`, `"monotonicity"`,
    /// `"commutativity"`, `"associativity"`, `"inverse-pair"`,
    /// `"identity-element"`, `"dual-style-consistency"`,
    /// `"composition"`, `"invariant-preservation"`.
    public var templateName: String

    /// Carrier type name (the suggestion's `containingTypeName`).
    /// `nil` for free functions or templates that don't have a carrier
    /// (the M1 idempotence template's no-carrier case).
    public var typeName: String?

    /// The suggestion's total score (signal sum). Useful for
    /// `--min-score` query filtering.
    public var score: Int

    /// Score tier as a human-readable string: `"Strong"`, `"Likely"`,
    /// `"Possible"`, or `"Suppressed"` (the last is rare in an index
    /// since Suppressed suggestions don't surface, but allowed for
    /// completeness).
    public var tier: String

    /// First-evidence function display name, e.g. `"exp(_:)"` or
    /// `"OrderedSet.sort()"`. Mirrors how discover renders the
    /// suggestion's first `Why suggested` line.
    public var primaryFunctionName: String

    /// `"<file>:<line>"` of the suggestion's first evidence. Mirrors
    /// the SwiftLint-friendly format the renderer uses.
    public var location: String

    /// User's triage decision recorded in `.swiftinfer/decisions.json`,
    /// or `nil` when no decision has been made yet. One of `"accept"`,
    /// `"reject"`, `"skip"`.
    public var decision: String?

    /// ISO8601 timestamp of the user's decision, copied from
    /// `.swiftinfer/decisions.json`. `nil` when no decision recorded.
    public var decisionAt: String?

    /// ISO8601 timestamp of the first `swift-infer index` run that
    /// produced this entry. Preserved across upserts so historical
    /// "when did this signature appear" queries remain accurate.
    public var firstSeenAt: String

    /// ISO8601 timestamp of the most recent `swift-infer index` run.
    /// Updated on every upsert so the user can identify entries
    /// dropped out of the current discover state (where `lastSeenAt`
    /// is older than the most recent run).
    public var lastSeenAt: String

    /// V1.47.A — JSON-encodable mirror of the carrier type's
    /// `PropertyLawCore.TypeShape` (kind + inherited types + stored
    /// members + user-init/gen flags), populated when discover sees
    /// the type's declaration in the indexed source. `nil` for stdlib
    /// raw-type carriers, `Complex<Double>`, types whose primary decl
    /// the indexer couldn't see, or entries persisted by v1.46-and-
    /// earlier `swift-infer` releases. The verify pipeline reads this
    /// to call `DerivationStrategist.strategy(for:)` without
    /// re-parsing the user's source.
    public var typeShape: IndexedTypeShape?

    /// V1.49.C — non-curated round-trip pair inverse-half name.
    /// Populated by discover when the suggestion's evidence array
    /// surfaces both pair halves (round-trip template emits
    /// `[forward, inverse]`); the verify resolver consults this
    /// field after the curated-pair lookup misses. `nil` for all
    /// non-round-trip templates and for v1.47-and-earlier persisted
    /// entries. Format: bare function name in the same shape
    /// `primaryFunctionName` carries (e.g. `"_scale(forMinimumCapacity:)"`).
    public var secondaryFunctionName: String?

    /// V1.149 — the *generator* carrier, distinct from `typeName` (which
    /// is the function's owner / call-site qualifier). For a method
    /// defined on the carrier (`extension Int { … }`) the two coincide
    /// and this stays `nil`; the verify path falls back to `typeName`.
    /// For a `static`/free function whose property flows through a
    /// parameter — e.g. `static func indent(_ s: String) -> String` on an
    /// unrelated `enum Engine` — `typeName` is `"Engine"` (the call
    /// qualifier) and `carrierTypeName` is `"String"` (the type the
    /// generated `Gen<T>` must produce). `nil` for v1.148-and-earlier
    /// persisted entries and for templates that don't expose a distinct
    /// parameter carrier.
    public var carrierTypeName: String?

    /// True when the picked function is an instance method (has a
    /// containing type and is not `static`). Emitters use this to choose
    /// the `receiver.method(...)` call shape over the static
    /// `Type.method(receiver)` shape. `false` for free/static functions
    /// and for entries persisted before this field existed.
    public var isInstanceMethod: Bool

    /// True when the picked instance method is `mutating` (or otherwise
    /// mutates in place / returns `Void`). Combined with
    /// ``isInstanceMethod`` it selects the `var copy = value;
    /// copy.method()` idempotence shape rather than the self-returning
    /// `value.method().method()` shape. `false` unless known.
    public var isMutatingMethod: Bool

    /// True when the picked function takes no parameters. Receiver-style
    /// instance-method emit shapes (`value.method()`) are only valid for
    /// nullary methods; arg-bearing methods fall back to the static shape.
    public var isNullary: Bool

    /// True when the function's return type is its own carrier type
    /// (`Self`, or the containing type up to generic arguments). Gates the
    /// non-mutating self-returning idempotence chain `value.m().m()`.
    public var returnsSelfType: Bool

    /// Recall epic #1 — this entry is a read-only computed property; the verify
    /// emitter emits `value.name` (property access) rather than `value.name()`.
    public var isComputedProperty: Bool

    /// Each parameter's type as written, in declaration order — the law's **signature**, where
    /// every other field describes only its carrier.
    ///
    /// `carrierTypeName` is singular, which is enough to state a law about `f(_ x: T)` and not
    /// enough for anything else. Measured 2026-08-03: 19 of 126 `predicate` entries failed to
    /// compile with `missing argument for parameter #2`, because the composer had one type and
    /// emitted one argument for a function that takes two.
    ///
    /// Empty means *not recorded* — an index written before this field existed, or an
    /// `Evidence` built by hand — and verify falls back to the single-carrier behaviour rather
    /// than guessing.
    public var parameterTypeNames: [String]

    /// The declaring type's full lexical path — what a stub must WRITE, as opposed
    /// to what the bare-name-keyed sidecars are keyed on. See
    /// `FunctionSummary.qualifiedContainingTypeName`. `nil` means *not recorded*
    /// and the call resolver falls back to `typeName`.
    public var qualifiedTypeName: String?

    /// Why this entry's property cannot be measured, when a discovery signal
    /// already knew. See `StructuralBlocker` — this is not a carrier-reach gap and
    /// must not be reported as one. `nil` is the normal case.
    public var structuralBlocker: String?

    /// Fingerprint of the subject's body at index time (`SubjectFingerprint`), carried so
    /// `verify` can stamp the evidence it records with the code it actually ran against.
    /// `nil` for pre-v1.149 indexes and for subjects with no readable body.
    public var subjectFingerprint: String?

    public init(
        identityHash: String,
        templateName: String,
        typeName: String? = nil,
        score: Int,
        tier: String,
        primaryFunctionName: String,
        location: String,
        decision: String? = nil,
        decisionAt: String? = nil,
        firstSeenAt: String,
        lastSeenAt: String,
        typeShape: IndexedTypeShape? = nil,
        secondaryFunctionName: String? = nil,
        carrierTypeName: String? = nil,
        isInstanceMethod: Bool = false,
        isMutatingMethod: Bool = false,
        isNullary: Bool = false,
        returnsSelfType: Bool = false,
        isComputedProperty: Bool = false,
        parameterTypeNames: [String] = [],
        qualifiedTypeName: String? = nil,
        structuralBlocker: String? = nil,
        subjectFingerprint: String? = nil
    ) {
        // Delegates to the exhaustive initializer, which is the designated one
        // — see `EveryColumn`. The direction matters: the exhaustive init is
        // what assigns the stored properties, so adding a property forces a
        // parameter onto it, which breaks every converter that calls it.
        self.init(
            everyColumn: .required,
            identityHash: identityHash,
            templateName: templateName,
            typeName: typeName,
            score: score,
            tier: tier,
            primaryFunctionName: primaryFunctionName,
            location: location,
            decision: decision,
            decisionAt: decisionAt,
            firstSeenAt: firstSeenAt,
            lastSeenAt: lastSeenAt,
            typeShape: typeShape,
            secondaryFunctionName: secondaryFunctionName,
            carrierTypeName: carrierTypeName,
            isInstanceMethod: isInstanceMethod,
            isMutatingMethod: isMutatingMethod,
            isNullary: isNullary,
            returnsSelfType: returnsSelfType,
            isComputedProperty: isComputedProperty,
            parameterTypeNames: parameterTypeNames,
            qualifiedTypeName: qualifiedTypeName,
            structuralBlocker: structuralBlocker,
            subjectFingerprint: subjectFingerprint
        )
    }

    /// Returns a copy of `self` with the upsert-mutable columns
    /// (`score`, `tier`, `primaryFunctionName`, `location`, `decision`,
    /// `decisionAt`, `lastSeenAt`, `typeShape`) replaced from `other`
    /// while preserving `firstSeenAt` from `self`. Used by
    /// `IndexStore.upsert` (V1.33.B). `identityHash`, `templateName`,
    /// `typeName` are immutable across upserts (the PRD §7.5 identity
    /// hash is a function of those fields, so they cannot change
    /// without also changing the hash). `typeShape` is upsert-mutable
    /// because the type's structural shape can evolve (e.g., a user
    /// adds a stored property between two indexer runs).
    /// Uses the **exhaustive** initializer deliberately — see `EveryColumn`. A
    /// column added to this type and forgotten here is then a compile error
    /// rather than a silent revert-to-default on the next re-index.
    /// Exhaustive initializer — **every parameter is required, deliberately.**
    /// Converters (`updated(from:)`) use this so that adding a column and
    /// forgetting it is a compile error. See `EveryColumn`.
    public init(
        everyColumn _: EveryColumn,
        identityHash: String,
        templateName: String,
        typeName: String?,
        score: Int,
        tier: String,
        primaryFunctionName: String,
        location: String,
        decision: String?,
        decisionAt: String?,
        firstSeenAt: String,
        lastSeenAt: String,
        typeShape: IndexedTypeShape?,
        secondaryFunctionName: String?,
        carrierTypeName: String?,
        isInstanceMethod: Bool,
        isMutatingMethod: Bool,
        isNullary: Bool,
        returnsSelfType: Bool,
        isComputedProperty: Bool,
        parameterTypeNames: [String],
        qualifiedTypeName: String? = nil,
        structuralBlocker: String? = nil,
        // No default, deliberately — `EveryColumn`'s whole purpose is that a new column
        // added and then forgotten by a converter is a COMPILE ERROR rather than a silent
        // revert to `nil`. A silently-nil fingerprint here would read as "cannot validate"
        // and quietly switch the check off, which is the failure mode this field exists to
        // prevent. `qualifiedTypeName` / `structuralBlocker` predate that reading.
        subjectFingerprint: String?
    ) {
        self.identityHash = identityHash
        self.templateName = templateName
        self.typeName = typeName
        self.score = score
        self.tier = tier
        self.primaryFunctionName = primaryFunctionName
        self.location = location
        self.decision = decision
        self.decisionAt = decisionAt
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.typeShape = typeShape
        self.secondaryFunctionName = secondaryFunctionName
        self.carrierTypeName = carrierTypeName
        self.isInstanceMethod = isInstanceMethod
        self.isMutatingMethod = isMutatingMethod
        self.isNullary = isNullary
        self.returnsSelfType = returnsSelfType
        self.isComputedProperty = isComputedProperty
        self.parameterTypeNames = parameterTypeNames
        self.qualifiedTypeName = qualifiedTypeName
        self.structuralBlocker = structuralBlocker
        self.subjectFingerprint = subjectFingerprint
    }

    public func updated(from other: Self) -> Self {
        Self(
            everyColumn: .required,
            identityHash: identityHash,
            templateName: templateName,
            typeName: typeName,
            score: other.score,
            tier: other.tier,
            primaryFunctionName: other.primaryFunctionName,
            location: other.location,
            decision: other.decision,
            decisionAt: other.decisionAt,
            firstSeenAt: firstSeenAt,
            lastSeenAt: other.lastSeenAt,
            typeShape: other.typeShape,
            secondaryFunctionName: other.secondaryFunctionName,
            carrierTypeName: carrierTypeName,
            isInstanceMethod: other.isInstanceMethod,
            isMutatingMethod: other.isMutatingMethod,
            isNullary: other.isNullary,
            returnsSelfType: other.returnsSelfType,
            isComputedProperty: other.isComputedProperty,
            // From `other`: a re-scan is authoritative for the signature, exactly as it is for
            // every other shape column. A parameter list that changed is a law that changed.
            parameterTypeNames: other.parameterTypeNames,
            qualifiedTypeName: other.qualifiedTypeName,
            structuralBlocker: other.structuralBlocker,
            // From `other`, and this one is load-bearing: the fingerprint's entire job is to
            // record what the body looked like at the LAST scan. Keeping `self`'s would pin
            // the index to a body that no longer exists and re-validate evidence the edit
            // should have invalidated — the defect this field closes, reintroduced one layer
            // down.
            subjectFingerprint: other.subjectFingerprint
        )
    }
}
