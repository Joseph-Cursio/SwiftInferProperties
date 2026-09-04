import Foundation
@testable import SwiftInferCore
import Testing

/// The cross-repository contract for `role` in the seed manifest.
///
/// SwiftProjectLint produces the field and this tool consumes it, from two repositories that are
/// versioned independently and pin a shared dependency at *different* revisions. There is no
/// compiler between them, so a mismatch is silent by default — and the failure mode is not a crash
/// but a wrong law proposed against correct code, which is the one outcome `Refutability` exists to
/// prevent.
///
/// These tests are the substitute for that compiler. They pin three things:
///
/// 1. **Every role the producer can emit decodes here** — one case per
///    `PureClosureCandidateVisitor.Kind` plus the two kernel shapes.
/// 2. **The entailment claim agrees with `Refutability`** — the producer's
///    `PBTSeedRole.impliesEntailedLaw` asserts that `comparator`, `predicate` and `partition` are
///    laws a correct implementation cannot fail. If this tool ever demotes one, that assertion
///    becomes a lie. It should break here.
/// 3. **An unknown role degrades safely** — never entailed, and never silently swallowed.
@Suite("Seed manifest — the role contract with the linter")
struct SeedRoleContractTests {

    /// Exactly what SwiftProjectLint's `PBTSeedRole` can emit today. Adding a case there without
    /// adding it here is the drift this suite exists to catch: the new role would arrive as
    /// `.unrecognised` and be silently dropped from every listing.
    private static let producerVocabulary: [String] = [
        // PureClosureCandidateVisitor.Kind — one per case.
        "comparator", "predicate", "transform", "reducer",
        // ExtractableTotalKernelVisitor — the two kernel shapes.
        "partition", "normalizer"
    ]

    private func decodeRole(_ raw: String) throws -> SeedRole {
        let json = Data("""
        {"file":"A.swift","line":1,"symbol":"f","kind":"extractable-kernel","role":"\(raw)",
          "rule": "Pure Function Property-Test Candidate"}
        """.utf8)
        return try #require(JSONDecoder().decode(SeedManifest.Seed.self, from: json).role)
    }

    // MARK: - 1. Every producer role decodes

    @Test("every role the linter can emit round-trips", arguments: producerVocabulary)
    func producerRolesDecode(raw: String) throws {
        let role = try decodeRole(raw)
        #expect(role.rawValue == raw)
        if case .unrecognised = role {
            Issue.record("`\(raw)` is in the linter's vocabulary but this build does not know it")
        }
    }

    @Test("every known role can state its law", arguments: producerVocabulary)
    func producerRolesHaveALawSentence(raw: String) throws {
        // The listing sentence is the entire payoff of carrying the role on a kernel seed, which
        // can never be analysed. A role that decodes but says nothing is the field arriving and
        // still being useless.
        #expect(try decodeRole(raw).lawSentence != nil)
    }

    // MARK: - 2. The entailment claim matches Refutability

    /// The load-bearing test. `entailedTemplateName` is this tool's half of a claim the producer
    /// also makes; the two are only consistent if every template named here is one `Refutability`
    /// actually treats as role-entailed.
    @Test("a role's entailed template is one Refutability agrees is entailed", arguments: producerVocabulary)
    func entailedTemplatesAreReallyEntailed(raw: String) throws {
        guard let template = try decodeRole(raw).entailedTemplateName else { return }
        // If this fails, SwiftProjectLint's `PBTSeedRole.impliesEntailedLaw` is now lying: it
        // advertises `\(raw)` as a law correct code cannot fail, and this tool no longer agrees.
        #expect(Refutability.roleEntailedTemplates.contains(template))
    }

    @Test("exactly the three entailed roles claim a template")
    func onlyEntailedRolesClaimATemplate() throws {
        var claiming: Set<String> = []
        for raw in Self.producerVocabulary
        where try decodeRole(raw).entailedTemplateName != nil {
            claiming.insert(raw)
        }
        // Mirrors PBTSeedRole.impliesEntailedLaw. A conjectured law must NOT be advertised as
        // entailed: proposing one that correct code fails costs more trust than proposing nothing.
        #expect(claiming == ["comparator", "predicate", "partition"])
    }

    // MARK: - 3. Unknown roles degrade safely

    @Test("a role from a newer linter is carried, not dropped")
    func unknownRoleIsCarried() throws {
        let role = try decodeRole("bifunctor")
        #expect(role == .unrecognised("bifunctor"))
        #expect(role.rawValue == "bifunctor", "the raw spelling must survive so it can be reported")
    }

    @Test("an unknown role is never treated as entailed")
    func unknownRoleIsNeverEntailed() throws {
        // The asymmetry from `SeedKind.unrecognised`, applied to roles. Guessing "entailed" for a
        // role this build cannot interpret would propose a law nobody verified.
        #expect(try decodeRole("bifunctor").entailedTemplateName == nil)
        #expect(try decodeRole("bifunctor").lawSentence == nil)
    }

    // MARK: - Backward compatibility

    /// The producer's fourth kind, added when it turned out the linter was marking 316 of 468
    /// seeds analysable while naming functions no test could call. An older build of this tool
    /// would read it as `.unrecognised` — not analysable, and said out loud — which is the correct
    /// degradation, but this build should name it properly.
    @Test("the restricted-function kind decodes and IS analysable")
    func restrictedFunctionKindIsUnderstood() throws {
        let json = Data("""
        {"file":"A.swift","line":1,"symbol":"hidden","kind":"restricted-function","role":"predicate",
          "rule": "Pure Function Property-Test Candidate"}
        """.utf8)
        let seed = try JSONDecoder().decode(SeedManifest.Seed.self, from: json)
        #expect(seed.kind == .restrictedFunction)
        // This asserted `false` when the case first shipped, grouping it with `extractableKernel`.
        // That conflated two obstacles: a kernel has no symbol at all, while a restricted function
        // has a name and a signature and lacks only VERIFIABILITY from another module. Since
        // `analysableSeeds` is what `synthesizeGenericLaws` keys on, the false silently disabled
        // the seeded-private rescue in `SeededPrivateFunctionTests`.
        #expect(seed.kind.isAnalysable)
        #expect(seed.kind.rawValue == "restricted-function")
        // The role still arrives — an access level is the obstacle, not the classification.
        #expect(seed.role == .predicate)
    }

    @Test("restricted seeds are analysable; only kernels are refactor-pending")
    func onlyKernelsArePending() {
        // Access level decides what must happen before a law can be VERIFIED. Purity, shape and
        // role decide whether a law is worth proposing. Only the second question gates analysis.
        let manifest = SeedManifest(seeds: [
            SeedManifest.Seed(file: "A.swift", line: 1, symbol: "open", kind: .pureFunction),
            SeedManifest.Seed(file: "A.swift", line: 9, symbol: "hidden", kind: .restrictedFunction),
            SeedManifest.Seed(file: "A.swift", line: 20, symbol: "trapped", kind: .extractableKernel)
        ])
        #expect(manifest.analysableSeeds.map(\.symbol) == ["open", "hidden"])
        #expect(manifest.refactorPendingSeeds.map(\.symbol) == ["trapped"])
    }

    @Test("a manifest with no role field still decodes")
    func absentRoleIsNil() throws {
        let json = Data("""
        {"file":"A.swift","line":1,"symbol":"f","kind":"pure-function", "rule": "Pure Function Property-Test Candidate"}
        """.utf8)
        #expect(try JSONDecoder().decode(SeedManifest.Seed.self, from: json).role == nil)
    }

    /// `role` is optional and `kind` is not, and the asymmetry is the point. An absent role is
    /// honestly unknown — no consumer acts on it. An absent kind would have to be GUESSED, and the
    /// guess decides whether this tool narrows discovery onto the seed, so there is no safe
    /// default. A seed carrying a role but no kind is still rejected.
    @Test("a role does not excuse a missing kind")
    func roleDoesNotExcuseMissingKind() {
        let json = Data("""
        {"file":"A.swift","line":1,"symbol":"f","role":"comparator", "rule": "Pure Function Property-Test Candidate"}
        """.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SeedManifest.Seed.self, from: json)
        }
    }
}
