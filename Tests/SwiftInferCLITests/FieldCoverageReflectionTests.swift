import Foundation
import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// **The guard that does not need updating when a field is added.**
///
/// Every other parity test in this repo names its fields. That catches the
/// fields someone thought to name — and the bug this whole arc is about is a
/// field nobody thought about. `enumCases` was missing from `IndexedTypeShape`
/// for its entire life, and no test failed, because no test knew to look for a
/// field that did not exist. A field-by-field guard is a list of things we
/// already remembered.
///
/// These tests are different in kind: they ask the *type itself* what fields it
/// has, via `Mirror`, and compare that against what actually survives encoding.
/// Add a stored property to any type below and forget it in `encode(to:)`, and
/// this fails on the next run with the property's name in the message — with
/// nobody having written a new test.
///
/// **How to read a failure.** The message names the field and the direction:
///
///     `SemanticIndexEntry` has stored property `newColumn` that never reaches
///     the encoded form — add it to `encode(to:)` and `CodingKeys`.
///
/// That is the whole point. The three times this class of bug landed, the
/// symptom was a *limitation* several layers downstream — a derivation tier
/// quietly not firing, surfaced as `unsupported-carrier` or a hung verifier.
/// Here it is a named field in a failing assertion, next to the type that lost
/// it. See `docs/roadtest-self-dogfood.md` §11.3.
///
/// **Scope, honestly.** `Mirror` sees stored properties, so this covers the
/// encode side of hand-written `Codable`. It does not cover a field that is
/// encoded but dropped by a *converter* (`updated(from:)`, `init(from kitShape:)`)
/// — those are guarded field-by-field in the sibling suites, and making them
/// automatic would need either macro-generated converters or `Equatable`
/// round-trip laws over generators that populate every field, which is what
/// `IndexedTypeShapeParityPropertyTests` and `IndexProjectionParityPropertyTests`
/// do by hand.
@Suite("Road test — every stored property reaches the encoded form")
struct FieldCoverageReflectionTests {

    /// Stored-property names, as the type reports them.
    private static func storedProperties(of value: Any) -> Set<String> {
        Set(Mirror(reflecting: value).children.compactMap(\.label))
    }

    /// Top-level keys the value actually encodes to.
    private static func encodedKeys(_ value: some Encodable) throws -> Set<String> {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else { return [] }
        return Set(dictionary.keys)
    }

    /// The shared assertion. Every stored property must appear as an encoded
    /// key — so the *value under test must populate every optional*, since an
    /// `encodeIfPresent` of `nil` legitimately omits its key.
    private static func expectFullCoverage(
        _ value: some Encodable,
        _ typeName: String,
        knownAbsent: Set<String> = [],
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) throws {
        let stored = storedProperties(of: value).subtracting(knownAbsent)
        let encoded = try encodedKeys(value)
        let missing = stored.subtracting(encoded).sorted()
        #expect(
            missing.isEmpty,
            Comment(rawValue: """
                `\(typeName)` has stored propert\(missing.count == 1 ? "y" : "ies") \
                \(missing.map { "`\($0)`" }.joined(separator: ", ")) that \
                \(missing.count == 1 ? "never reaches" : "never reach") the encoded form — add \
                \(missing.count == 1 ? "it" : "them") to `encode(to:)` and \
                `CodingKeys`. (Detected by reflection, so this fires for fields nobody \
                wrote a test for — which is exactly how `enumCases` went missing.)
                """),
            sourceLocation: sourceLocation
        )
    }

    // MARK: - The persisted index types

    @Test("IndexedTypeShape encodes every stored property")
    func indexedTypeShapeCoversItsFields() throws {
        try Self.expectFullCoverage(
            IndexedTypeShape(
                name: "Outer.Kind",
                kind: .enum,
                inheritedTypes: ["String"],
                hasUserGen: true,
                storedMembers: [IndexedTypeShape.StoredMember(name: "a", typeName: "Int")],
                hasUserInit: true,
                initializers: [IndexedTypeShape.InitializerSignature(parameters: [])],
                enumCases: [IndexedTypeShape.EnumCase(name: "`struct`")]
            ),
            "IndexedTypeShape"
        )
    }

    @Test("SemanticIndexEntry encodes every stored property")
    func semanticIndexEntryCoversItsFields() throws {
        try Self.expectFullCoverage(
            SemanticIndexEntry(
                identityHash: "HASH",
                templateName: "idempotence",
                typeName: "Carrier",
                score: 80,
                tier: "Strong",
                primaryFunctionName: "normalize",
                location: "F.swift:1",
                decision: "accepted",
                decisionAt: "2026-07-26T00:00:00Z",
                firstSeenAt: "2026-01-01T00:00:00Z",
                lastSeenAt: "2026-07-26T00:00:00Z",
                typeShape: IndexedTypeShape(
                    name: "Carrier", kind: .struct, inheritedTypes: [], hasUserGen: false
                ),
                secondaryFunctionName: "denormalize",
                carrierTypeName: "Carrier",
                isInstanceMethod: true,
                isMutatingMethod: true,
                isNullary: true,
                returnsSelfType: true,
                isComputedProperty: true
            ),
            "SemanticIndexEntry"
        )
    }

    @Test("InteractionIndexEntry encodes every stored property")
    func interactionIndexEntryCoversItsFields() throws {
        try Self.expectFullCoverage(
            InteractionIndexEntry(
                identityHash: "IHASH",
                family: "idempotence",
                reducerQualifiedName: "Feature.reduce",
                stateTypeName: "State",
                actionTypeName: "Action",
                predicate: "p",
                location: "Feature.swift:1",
                moduleName: "Module",
                score: 40,
                tier: "Likely",
                decision: "accepted",
                decisionAt: "2026-07-26T00:00:00Z",
                firstSeenAt: "2026-01-01T00:00:00Z",
                lastSeenAt: "2026-07-26T00:00:00Z"
            ),
            "InteractionIndexEntry"
        )
    }

    @Test("VerifyEvidence encodes every stored property")
    func verifyEvidenceCoversItsFields() throws {
        try Self.expectFullCoverage(
            VerifyEvidence(
                identityHash: "HASH",
                template: "idempotence",
                outcome: .measuredBothPass,
                detail: "detail",
                capturedAt: Date(timeIntervalSince1970: 1_000_000),
                swiftInferVersion: "test",
                excludedActionCount: 0,
                counterexample: "x",
                shrunkCounterexample: "x",
                seed: "seed",
                regressionTestPath: "Tests/Generated/T.swift"
            ),
            "VerifyEvidence"
        )
    }

    @Test("the Index container encodes every stored property")
    func indexContainerCoversItsFields() throws {
        try Self.expectFullCoverage(
            IndexStore.Index(
                schemaVersion: 5,
                updatedAt: "2026-07-26T00:00:00Z",
                entries: [],
                typeShapes: [:],
                interactionEntries: []
            ),
            "IndexStore.Index"
        )
    }

    // MARK: - The guard's own control
    //
    // A coverage check that cannot fail is worse than none, and this one is
    // easy to write wrongly — `Mirror` on a type with no children, or an
    // `encodedKeys` that silently returns everything, would both pass every
    // assertion above while checking nothing.

    /// The check detects a deliberately lossy encoder — the exact bug shape,
    /// staged. If this ever passes, every test above is vacuous.
    @Test("the coverage check actually detects a dropped field")
    func theCheckDetectsADroppedField() throws {
        let stored = Self.storedProperties(of: Lossy(kept: "a", dropped: "b"))
        let encoded = try Self.encodedKeys(Lossy(kept: "a", dropped: "b"))
        #expect(stored == ["kept", "dropped"], "Mirror did not see both properties")
        #expect(encoded == ["kept"], "the lossy encoder did not behave as staged")
        #expect(stored.subtracting(encoded) == ["dropped"], "the check would not have caught it")
    }
}

/// Control fixture for `theCheckDetectsADroppedField` — a deliberately lossy
/// encoder, at file scope because the nesting cap forbids a third level.
private struct Lossy: Encodable {
    let kept: String
    let dropped: String

    private enum CodingKeys: String, CodingKey { case kept }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kept, forKey: .kept)
    }
}

/// The **converter** half of the field-coverage guard, which reflection cannot
/// reach — a field that encodes correctly but is dropped by `updated(from:)` or
/// `init(from kitShape:)`. That is precisely where `enumCases` died.
///
/// This is not enforced by a test. It is enforced by the **compiler**, via the
/// exhaustive initializers described in `EveryColumn`: the exhaustive init is
/// the designated one (it assigns the stored properties), the ergonomic
/// defaulted init delegates to it, and every converter calls the exhaustive
/// one. Adding a stored property therefore fails the build at the exhaustive
/// init — *"return from initializer without initializing all stored
/// properties"* — and once a parameter is added there, every converter fails
/// too until it says what the new column should do on a refresh.
///
/// Verified by staging the exact scenario on all three types (add the property,
/// add it to the ergonomic init with a default, touch nothing else) and
/// confirming the build fails each time. That check lives in the road-test
/// record rather than here, because a test cannot assert a compile error.
///
/// These tests pin the structural precondition the compile-time guard depends
/// on: that the exhaustive initializer exists, is reachable, and agrees with
/// its ergonomic sibling. If the delegation were ever flipped back — ergonomic
/// designated, exhaustive delegating — the build-time guard would silently
/// stop working while every other test still passed. That happened once during
/// development and is the reason this suite exists.
@Suite("Road test — exhaustive initializers agree with their ergonomic siblings")
struct ExhaustiveInitializerAgreementTests {

    @Test("IndexedTypeShape: both initializers produce the same value")
    func indexedTypeShapeInitializersAgree() {
        let ergonomic = IndexedTypeShape(
            name: "Outer.Kind",
            kind: .enum,
            inheritedTypes: ["String"],
            hasUserGen: true,
            storedMembers: [IndexedTypeShape.StoredMember(name: "a", typeName: "Int")],
            hasUserInit: true,
            initializers: [IndexedTypeShape.InitializerSignature(parameters: [])],
            enumCases: [IndexedTypeShape.EnumCase(name: "`struct`")]
        )
        let exhaustive = IndexedTypeShape(
            everyColumn: .required,
            name: "Outer.Kind",
            kind: .enum,
            inheritedTypes: ["String"],
            hasUserGen: true,
            storedMembers: [IndexedTypeShape.StoredMember(name: "a", typeName: "Int")],
            hasUserInit: true,
            initializers: [IndexedTypeShape.InitializerSignature(parameters: [])],
            enumCases: [IndexedTypeShape.EnumCase(name: "`struct`")]
        )
        #expect(ergonomic == exhaustive, "the two initializers disagree — the delegation is wrong")
    }

    @Test("InteractionIndexEntry: both initializers produce the same value")
    func interactionEntryInitializersAgree() {
        let ergonomic = InteractionIndexEntry(
            identityHash: "H", family: "idempotence", reducerQualifiedName: "F.reduce",
            stateTypeName: "S", actionTypeName: "A", predicate: "p", location: "F.swift:1",
            moduleName: "M", score: 40, tier: "Likely", decision: "accepted",
            decisionAt: "d", firstSeenAt: "f", lastSeenAt: "l"
        )
        let exhaustive = InteractionIndexEntry(
            everyColumn: .required,
            identityHash: "H", family: "idempotence", reducerQualifiedName: "F.reduce",
            stateTypeName: "S", actionTypeName: "A", predicate: "p", location: "F.swift:1",
            moduleName: "M", score: 40, tier: "Likely", decision: "accepted",
            decisionAt: "d", firstSeenAt: "f", lastSeenAt: "l"
        )
        #expect(ergonomic == exhaustive, "the two initializers disagree — the delegation is wrong")
    }

    /// The ergonomic initializer's defaults must still be the *same* values the
    /// exhaustive one would take explicitly — otherwise the delegation is
    /// silently changing behaviour at ~90 existing call sites.
    @Test("the ergonomic defaults match what the exhaustive initializer takes")
    func ergonomicDefaultsMatchExhaustive() {
        let defaulted = IndexedTypeShape(
            name: "T", kind: .struct, inheritedTypes: [], hasUserGen: false
        )
        let spelled = IndexedTypeShape(
            everyColumn: .required,
            name: "T", kind: .struct, inheritedTypes: [], hasUserGen: false,
            storedMembers: [], hasUserInit: false, initializers: [], enumCases: []
        )
        #expect(defaulted == spelled)
    }
}
