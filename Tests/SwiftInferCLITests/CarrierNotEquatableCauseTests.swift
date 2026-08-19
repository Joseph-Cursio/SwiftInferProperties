import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

/// A law that compares with `==` against a carrier that has no `==` gets its own cause.
///
/// ## Why a third answer
///
/// Measured on GRDB (`plans/inverse-pair-identity-element-composers-scope.md`): 31 rows
/// reported `unsupported-template` for `inverse-pair` and `identity-element`, and **both
/// available labels were wrong**.
///
/// `unsupported-template` says *a gap in swift-infer; nothing you write unblocks these* — true
/// of the composer, and it misses that **no composer would help**. `inverse-pair` fires
/// precisely WHEN the carrier is non-Equatable, because `round-trip` vetoes exactly there, so
/// a composer for it would chase a law that cannot be written.
///
/// `unsupported-carrier` is worse, because its remedy says *add a `gen()`* — and a generator
/// changes nothing. That is the `Gen<T>` mistake again: advice that cannot work, on the
/// most-shown channel.
///
/// ## The direction of doubt
///
/// **Silence unless certain.** A wrong "not Equatable" relabels a row whose real blocker is
/// the composer — hiding a gap that CAN close behind one that cannot. So the gate fires only
/// when a shape was actually scanned and lists no equality-implying conformance. Four of the
/// seven arms below are that fallback.
@Suite("Equality-shaped laws report a carrier with no equality as its own cause")
struct CarrierNotEquatableCauseTests {

    private func entry(template: String, carrier: String) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "0xA1",
            templateName: template,
            typeName: carrier,
            score: 25,
            tier: "possible",
            primaryFunctionName: "f(_:)",
            location: "/tmp/Subject.swift:1",
            firstSeenAt: "2026-08-14T00:00:00Z",
            lastSeenAt: "2026-08-14T00:00:00Z",
            carrierTypeName: carrier
        )
    }

    private func shape(_ name: String, conformances: [String]) -> IndexedTypeShape {
        IndexedTypeShape(
            everyColumn: .required,
            name: name,
            kind: .struct,
            inheritedTypes: conformances,
            hasUserGen: false,
            storedMembers: [],
            hasUserInit: false,
            initializers: [],
            enumCases: []
        )
    }

    private func cause(
        template: String,
        carrier: String,
        shapes: [String: IndexedTypeShape]
    ) -> UnverifiableCause {
        do {
            _ = try SwiftInferCommand.Verify.buildStubBundle(
                entry: entry(template: template, carrier: carrier),
                budget: .small,
                allShapes: shapes
            )
            return .unrecognised
        } catch let error as VerifyError {
            return UnverifiableCause.classify(
                detail: SwiftInferCommand.Verify.detail(for: error)
            )
        } catch {
            return .unrecognised
        }
    }

    // MARK: - The relabelling

    @Test("inverse-pair on a non-Equatable carrier reports carrier-not-equatable")
    func inversePairOnNonEquatableCarrier() {
        // GRDB's shape: a struct conforming to something that is not equality-implying.
        let shapes = ["Aggregate": shape("Aggregate", conformances: ["Refinable"])]
        #expect(cause(template: "inverse-pair", carrier: "Aggregate", shapes: shapes)
            == .carrierNotEquatable)
    }

    @Test("identity-element on a non-Equatable carrier reports carrier-not-equatable")
    func identityElementOnNonEquatableCarrier() {
        let shapes = ["Aggregate": shape("Aggregate", conformances: ["Refinable"])]
        #expect(cause(template: "identity-element", carrier: "Aggregate", shapes: shapes)
            == .carrierNotEquatable)
    }

    // MARK: - Silence unless certain

    @Test("an Equatable carrier keeps the composer gap")
    func equatableCarrierKeepsTemplateCause() {
        // The row that matters for the future: if such a population ever appears, its blocker
        // really IS the missing composer, and relabelling it would hide a closable gap.
        let shapes = ["Money": shape("Money", conformances: ["Equatable"])]
        #expect(cause(template: "inverse-pair", carrier: "Money", shapes: shapes)
            == .unsupportedTemplate)
    }

    @Test("Hashable and Comparable each imply equality and keep the composer gap")
    func equalityImplyingConformancesAreHonoured() {
        for conformance in ["Hashable", "Comparable"] {
            let shapes = ["Key": shape("Key", conformances: [conformance])]
            #expect(
                cause(template: "inverse-pair", carrier: "Key", shapes: shapes)
                    == .unsupportedTemplate,
                Comment(rawValue: "\(conformance) implies Equatable and must not be relabelled")
            )
        }
    }

    @Test("an unscanned carrier makes no claim")
    func unknownCarrierMakesNoClaim() {
        // No shape means no evidence. A stdlib type, an unscanned module, a conformance added
        // where we did not read — all must fall through to the previous behaviour.
        #expect(cause(template: "inverse-pair", carrier: "String", shapes: [:])
            == .unsupportedTemplate)
    }

    @Test("a template whose law does not compare with == is untouched")
    func nonEqualityTemplateIsUntouched() {
        // The curation is the safeguard: only templates whose emitted law was read and seen to
        // use `==` are in the set. A composer gap on anything else stays a composer gap.
        let shapes = ["Aggregate": shape("Aggregate", conformances: ["Refinable"])]
        #expect(cause(template: "some-future-template", carrier: "Aggregate", shapes: shapes)
            == .unsupportedTemplate)
    }

    @Test("the new cause carries a remedy that does not send the reader to write a gen()")
    func remedyDoesNotPrescribeAGenerator() {
        // The specific wrong advice this cause exists to stop.
        let remedy = UnverifiableCause.carrierNotEquatable.remedy
        #expect(!remedy.contains("gen()") || remedy.contains("changes it"))
        #expect(remedy.contains("Equatable"))
        #expect(!UnverifiableCause.carrierNotEquatable.label.isEmpty)
    }
}
