import Foundation
@testable import SwiftInferCore
import Testing

/// A caseless enum is a namespace, not a value — so `unsupported-carrier` is the wrong
/// answer for it. That reads as a generator gap and sends a reader to write
/// `static func gen() -> Generator<Namespace, _>`, a function that cannot return.
///
/// Swift forbids adding cases to an enum in an extension, so "enum with no cases" is a
/// provable statement about inhabitants rather than a guess about what the scan missed.
@Suite("Caseless enum carriers — a namespace has no values")
struct CaselessEnumCarrierTests {

    private func shape(
        _ name: String,
        kind: IndexedTypeShape.Kind,
        cases: [IndexedTypeShape.EnumCase] = [],
        members: [IndexedTypeShape.StoredMember] = []
    ) -> IndexedTypeShape {
        IndexedTypeShape(
            name: name,
            kind: kind,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: members,
            hasUserInit: false,
            initializers: [],
            enumCases: cases
        )
    }

    /// The measured case: `SamplingSeed` is `enum SamplingSeed { struct Value …; static func … }`.
    @Test("a caseless enum is blocked, and the reason names it")
    func caselessEnumIsBlocked() {
        let reason = StructuralBlocker.caselessEnumCarrier(shape("SamplingSeed", kind: .enum))
        #expect(reason?.contains("SamplingSeed") == true)
        #expect(reason?.contains("caseless enum") == true)
    }

    /// **The arm that must not fire.** An enum WITH cases is an ordinary carrier the
    /// strategist derives via the Tier 4 `enumCases` path.
    @Test("an enum with cases is not blocked")
    func enumWithCasesIsNotBlocked() {
        let withCases = shape("Tier", kind: .enum, cases: [.init(name: "strong"), .init(name: "likely")])
        #expect(StructuralBlocker.caselessEnumCarrier(withCases) == nil)
    }

    /// A struct with no stored members is still a value — `struct Empty {}` has exactly one
    /// inhabitant. Only enums have the no-inhabitants property.
    @Test(
        "an empty struct, class or actor is NOT blocked — emptiness is not caselessness",
        arguments: [IndexedTypeShape.Kind.struct, .class, .actor]
    )
    func emptyNonEnumsAreNotBlocked(kind: IndexedTypeShape.Kind) {
        #expect(StructuralBlocker.caselessEnumCarrier(shape("Empty", kind: kind)) == nil)
    }

    /// No shape at all means no claim — an external carrier is a different question.
    @Test("a missing shape is not blocked")
    func missingShapeIsNotBlocked() {
        #expect(StructuralBlocker.caselessEnumCarrier(nil) == nil)
    }

    // MARK: - The one re-attributed shape: `(T) -> T` both ways

    private func half(
        _ name: String,
        _ signature: String,
        parameters: [String],
        isInstanceMethod: Bool = false,
        generic: Bool = false,
        inoutFirst: Bool = false
    ) -> Evidence {
        Evidence(
            displayName: name,
            signature: signature,
            location: SourceLocation(file: "/Toy/Sources/Toy/Codec.swift", line: 1, column: 1),
            isInstanceMethod: isInstanceMethod,
            parameterTypeNames: parameters,
            genericParameters: generic ? [.init(name: "T", constraint: nil)] : [],
            inoutParameterIndices: inoutFirst ? [0] : []
        )
    }

    private func domain(
        _ evidence: [Evidence],
        owner: IndexedTypeShape? = nil,
        template: String = "round-trip",
        shapes: [String: IndexedTypeShape] = [:]
    ) -> String? {
        StructuralBlocker.endomorphicNamespaceRoundTripDomain(
            templateName: template,
            ownerShape: owner ?? shape("Slug", kind: .enum),
            evidence: evidence
        ) { shapes[$0] }
    }

    /// The toy reproduction: `enum Slug { static func encode(_: String) -> String; static func
    /// decode(_: String) -> String }`. Suggestion mode measured this over `String`; the survey
    /// declined it as a caseless enum.
    @Test("a (String) -> String pair on a namespace re-attributes to String")
    func endomorphicPairReattributes() {
        let pair = [
            half("encode(_:)", "(String) -> String", parameters: ["String"]),
            half("decode(_:)", "(String) -> String", parameters: ["String"]),
        ]
        #expect(domain(pair) == "String")
    }

    /// A non-namespace project type is a carrier too — the rule is about the shape, not `String`.
    @Test("a (Token) -> Token pair re-attributes to a scanned struct")
    func endomorphicPairOverAStruct() {
        let pair = [
            half("encode(_:)", "(Token) -> Token", parameters: ["Token"]),
            half("decode(_:)", "(Token) -> Token", parameters: ["Token"]),
        ]
        #expect(domain(pair, shapes: ["Token": shape("Token", kind: .struct)]) == "Token")
    }

    /// **The general case keeps declining**, as `caselessEnumCarrier`'s doc says: `A -> B` has
    /// two candidate carriers. This is `SamplingSeed`'s shape, the measured case.
    @Test("a T -> U pair on a namespace still declines")
    func crossTypePairStillDeclines() {
        let pair = [
            half("encode(_:)", "(String) -> Data", parameters: ["String"]),
            half("decode(_:)", "(Data) -> String", parameters: ["Data"]),
        ]
        #expect(domain(pair) == nil)
    }

    @Test(
        "throwing or async halves still decline",
        arguments: ["(String) throws -> String", "(String) async -> String"]
    )
    func effectfulSignaturesStillDecline(signature: String) {
        let pair = [
            half("encode(_:)", signature, parameters: ["String"]),
            half("decode(_:)", "(String) -> String", parameters: ["String"]),
        ]
        #expect(domain(pair) == nil)
    }

    /// The scanner strips `inout ` from a parameter's type, so the signature cannot show it;
    /// `inoutParameterIndices` is where it is recorded.
    @Test("an inout half still declines")
    func inoutHalfStillDeclines() {
        let pair = [
            half("encode(_:)", "(String) -> String", parameters: ["String"], inoutFirst: true),
            half("decode(_:)", "(String) -> String", parameters: ["String"]),
        ]
        #expect(domain(pair) == nil)
    }

    /// A caseless enum has no instances, so an instance-method half cannot be called as written;
    /// whatever produced it, it is not the `static (T) -> T` shape the rule re-attributes.
    @Test("an instance-method half still declines")
    func instanceMethodHalfStillDeclines() {
        let pair = [
            half("encode(_:)", "(String) -> String", parameters: ["String"], isInstanceMethod: true),
            half("decode(_:)", "(String) -> String", parameters: ["String"]),
        ]
        #expect(domain(pair) == nil)
    }

    @Test("a generic half still declines")
    func genericHalfStillDeclines() {
        let pair = [
            half("encode(_:)", "(String) -> String", parameters: ["String"], generic: true),
            half("decode(_:)", "(String) -> String", parameters: ["String"]),
        ]
        #expect(domain(pair) == nil)
    }

    /// `T` that is itself a namespace (or the owner, spelled `Self` or by name) would only move
    /// the decline from one type with no values to another.
    @Test("a namespace T still declines", arguments: ["Self", "Slug", "Other"])
    func namespaceDomainStillDeclines(domainName: String) {
        let pair = [
            half("encode(_:)", "(\(domainName)) -> \(domainName)", parameters: [domainName]),
            half("decode(_:)", "(\(domainName)) -> \(domainName)", parameters: [domainName]),
        ]
        #expect(domain(pair, shapes: ["Other": shape("Other", kind: .enum)]) == nil)
    }

    /// Empty `parameterTypeNames` means *not recorded* — an index written before the field.
    @Test("an unrecorded parameter list still declines")
    func unrecordedParametersStillDecline() {
        let pair = [
            half("encode(_:)", "(String) -> String", parameters: []),
            half("decode(_:)", "(String) -> String", parameters: []),
        ]
        #expect(domain(pair) == nil)
    }

    /// The owner must be the namespace: an enum WITH cases, or a struct, keeps its own carrier
    /// untouched, and another template is not this rule's business.
    @Test("a non-namespace owner, or another template, is left alone")
    func onlyNamespaceRoundTripsAreTouched() {
        let pair = [
            half("encode(_:)", "(String) -> String", parameters: ["String"]),
            half("decode(_:)", "(String) -> String", parameters: ["String"]),
        ]
        #expect(domain(pair, owner: shape("Codec", kind: .struct)) == nil)
        #expect(domain(pair, owner: shape("Mode", kind: .enum, cases: [.init(name: "on")])) == nil)
        #expect(domain(pair, template: "idempotence") == nil)
    }
}
