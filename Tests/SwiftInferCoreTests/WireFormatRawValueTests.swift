import PropertyLawCore
@testable import SwiftInferCore
import Testing

/// The raw values of every enum whose value outlives the process, pinned in one place.
///
/// Each enum here is `String`-backed and `Codable`, so its raw value *is* its on-disk spelling:
/// `.swiftinfer/decisions.json`, `baseline.json`, `index.json`, `kit-evidence.json` (written by the
/// recorder inside the user's test run and read back by `discover`), the interaction and
/// post-acceptance files, and the `pbt-seeds` manifest SwiftProjectLint produces. A case whose raw
/// value is implicit takes its name, so renaming it compiles, passes every round-trip test, and
/// makes existing files fail to decode or silently stop matching.
///
/// Explicit raw values would say the same thing in the source, but SwiftLint's default
/// `redundant_string_enum_value` rejects a value equal to the case name. So the spelling is
/// pinned here instead: this fails on a renamed implicit case and on an edited explicit value
/// alike. `.swiftprojectlint.yml` excludes these files from Implicit Codable Raw Value on the
/// strength of this test — keep the two in step.
///
/// Where a raw value is copied into another file as a plain string (`TemplateName` into
/// `index.json` and the decisions' `template` field), that copy is covered too, since code compares
/// the stored strings against these raw values.
@Suite("Wire formats — pinned raw values of persisted enums")
struct WireFormatRawValueTests {

    // MARK: - decisions.json, baseline.json, index.json

    @Test func decision() {
        #expect(Decision.allCases.map(\.rawValue) == ["accepted", "acceptedAsConformance", "rejected", "skipped"])
    }

    @Test func tier() {
        #expect(Tier.allCases.map(\.rawValue) == ["verified", "strong", "likely", "possible", "suppressed", "advisory"])
    }

    @Test func templateName() {
        #expect(TemplateName.allCases.map(\.rawValue) == [
            "round-trip", "codable-round-trip", "idempotence", "commutativity", "associativity",
            "idempotence-lifted", "dual-style-consistency", "monotonicity", "involution",
            "binary-idempotence", "homomorphism", "multiplicative-homomorphism", "measure-non-negativity",
            "role-postcondition", "differential-equivalence", "predicate", "inverse-pair",
            "identity-element", "composition", "invariant-preservation", "replay-idempotence"
        ])
    }

    /// Not this repo's enum: the kit's, copied into `index.json` as `StoredMember.accessLevel`. A
    /// renamed case there would make a stored `private` read back as the implicit level.
    @Test func storedMemberAccessLevel() {
        #expect(PropertyLawCore.AccessLevel.allCases.map(\.rawValue)
            == ["private", "fileprivate", "internal", "package", "public", "open"])
    }

    @Test func indexedTypeShapeKind() {
        let kinds: [IndexedTypeShape.Kind] = [.struct, .class, .enum, .actor]
        #expect(kinds.map(\.rawValue) == ["struct", "class", "enum", "actor"])
    }

    // MARK: - Interaction files

    @Test func interactionDecision() {
        #expect(InteractionDecision.allCases.map(\.rawValue) == [
            "accepted", "accepted-as-conformance", "rejected", "skipped"
        ])
    }

    @Test func interactionInvariantFamily() {
        #expect(InteractionInvariantFamily.allCases.map(\.rawValue) == [
            "conservation", "idempotence", "cardinality", "referential-integrity", "biconditional",
            "determinism", "unknown-action-is-no-op", "output-determinism"
        ])
    }

    @Test func postAcceptanceOutcomeKind() {
        #expect(PostAcceptanceOutcomeKind.allCases.map(\.rawValue) == [
            "still-passes", "now-fails", "obsolete", "error"
        ])
    }

    // MARK: - kit-evidence.json (written in the user's test process, read by discover)

    @Test func kitLawOutcome() {
        let outcomes: [KitLawOutcome.Outcome] = [.passed, .failed, .expectedViolation, .suppressed]
        #expect(outcomes.map(\.rawValue) == ["passed", "failed", "expectedViolation", "suppressed"])
    }

    @Test func kitLawTier() {
        let tiers: [KitLawOutcome.Tier] = [.strict, .conventional, .heuristic]
        #expect(tiers.map(\.rawValue) == ["strict", "conventional", "heuristic"])
    }

    // MARK: - pbt-seeds manifest (produced by SwiftProjectLint)

    @Test func seedEffectTier() {
        let tiers: [SeedEffect.Tier] = [.pure, .idempotent, .observational, .externallyIdempotent, .nonIdempotent]
        #expect(tiers.map(\.rawValue) == [
            "pure", "idempotent", "observational", "externally_idempotent", "non_idempotent"
        ])
    }

    @Test func seedEffectProvenance() {
        let provenances: [SeedEffect.Provenance] = [.declared, .inferredUpward, .inferredDownward]
        #expect(provenances.map(\.rawValue) == ["declared", "inferred-upward", "inferred-downward"])
    }

    @Test func seedEffectAnchor() {
        let anchors: [SeedEffect.Anchor] = [.declaration, .heuristic]
        #expect(anchors.map(\.rawValue) == ["declaration", "heuristic"])
    }
}
