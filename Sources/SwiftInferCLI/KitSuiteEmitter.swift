import Foundation
import PropertyLawCore
import SwiftInferCore

/// **Codegen for the laws PropertyLawKit covers but nothing writes.**
///
/// Measured on this repo: the kit's suites cover **996 laws over 299 carriers**, of which
/// **5 execute**. The gap was never a missing capability — `ProtocolCoverageMap`'s veto
/// suppresses each of those laws with a message that *names* the call
/// (`"checked by PropertyLawKit's check<Protocol>PropertyLaws"`) and generates nothing. It
/// tells you the test exists and leaves you to type ~299 call sites.
///
/// Seeing the tests is worth something on its own, separately from running them: a law you
/// can read is a claim you can disagree with, and `Equatable`'s laws passing on a *broken*
/// type is exactly the case `fixtures/equatable-signal` measured. So this emits source, for
/// a human to read and keep or discard — never applied, per the standing posture.
///
/// ## Derivability is the constraint, and it was measured before this was built
///
/// `check<Protocol>PropertyLaws` takes `using generator:` with **no default**, so every
/// emitted suite needs a `Generator<Value, _>`. `DerivationStrategist` derives one for
/// **180 of 351** covered carriers (51%), covering **598 of 1,153** laws.
///
/// The other half emit too, **commented out**, carrying the kit's own `.todo` reason — which
/// already ends with the exact signature to provide. Emitting them live would produce a file
/// that does not compile; omitting them silently would report half the work as all of it,
/// the "no silent caps" failure. Commented-out is the only option that is both honest and
/// compilable.
///
/// ## What this does not guarantee
///
/// That the live half compiles. `check<Protocol>PropertyLaws` requires `Value: Sendable`,
/// which a `TypeShape` cannot always tell us, and a carrier may be `private` or nested
/// beyond `@testable`'s reach. The output is a **draft for review**, which is why nothing
/// writes it into a build without the author asking.
public enum KitSuiteEmitter {

    /// The four numbers the header reports, bundled so `assemble` stays within the
    /// five-parameter cap.
    struct Counts {
        let liveCarriers: Int
        let blockedCarriers: Int
        let liveLaws: Int
        let blockedLaws: Int
    }

    public struct Emission: Equatable {
        public let source: String
        /// Carriers whose generator derived — emitted as live code.
        public let liveCarriers: Int
        /// Carriers needing a hand-written `gen()` — emitted commented out.
        public let blockedCarriers: Int
        public let liveLaws: Int
        public let blockedLaws: Int
    }

    /// Emit one Swift test file covering every carrier the kit's suites reach.
    ///
    /// - Parameter moduleName: the module under test, for `@testable import`. Carriers are
    ///   frequently `internal`, so a plain `import` would not see them.
    public static func emit(
        findings: [ProtocolCoverageAudit.Finding],
        shapes: [String: PropertyLawCore.TypeShape],
        moduleName: String
    ) -> Emission {
        var live: [String] = []
        var blocked: [String] = []
        var liveCarriers = 0, blockedCarriers = 0, liveLaws = 0, blockedLaws = 0

        for finding in findings.sorted(by: { $0.typeName < $1.typeName }) {
            guard let shape = shapes[finding.typeName] else { continue }
            let suites = suiteConformances(for: finding)
            guard !suites.isEmpty else { continue }
            let strategy = DerivationStrategist.strategy(for: shape)
            let generator = GeneratorExpressionEmitter.expression(
                typeName: finding.typeName, strategy: strategy
            )
            if case .todo(let reason) = strategy {
                blockedCarriers += 1
                blockedLaws += finding.coveredLaws.count
                blocked.append(blockedBlock(finding, suites: suites, reason: reason))
            } else {
                liveCarriers += 1
                liveLaws += finding.coveredLaws.count
                live.append(
                    liveBlock(
                        finding, suites: suites, generator: generator,
                        isCaseIterable: strategy == .caseIterable
                    )
                )
            }
        }

        return Emission(
            source: assemble(
                live: live,
                blocked: blocked,
                moduleName: moduleName,
                counts: Counts(
                    liveCarriers: liveCarriers, blockedCarriers: blockedCarriers,
                    liveLaws: liveLaws, blockedLaws: blockedLaws
                )
            ),
            liveCarriers: liveCarriers,
            blockedCarriers: blockedCarriers,
            liveLaws: liveLaws,
            blockedLaws: blockedLaws
        )
    }

    /// The conformances worth emitting a suite for, with subsumed ones dropped.
    ///
    /// **`Hashable`'s law set already contains `Equatable`'s** — `ProtocolCoverageMap` bakes
    /// transitive coverage in, so emitting both would run reflexivity, symmetry and
    /// transitivity twice and read as two findings where there is one. A conformance is
    /// dropped when its laws are a strict subset of another declared conformance's, which
    /// needs no model of Swift's protocol hierarchy — the sets already encode it.
    static func suiteConformances(for finding: ProtocolCoverageAudit.Finding) -> [String] {
        let declared = finding.declaredCoveringConformances
        let kept = declared.filter { candidate in
            guard let mine = ProtocolCoverageMap.protocolCoverage[candidate], !mine.isEmpty else {
                return false
            }
            return !declared.contains { other in
                guard other != candidate,
                      let theirs = ProtocolCoverageMap.protocolCoverage[other] else { return false }
                return mine.isStrictSubset(of: theirs)
            }
        }
        return kept.sorted()
    }

    // MARK: - Blocks

    static func liveBlock(
        _ finding: ProtocolCoverageAudit.Finding,
        suites: [String],
        generator: String,
        isCaseIterable: Bool
    ) -> String {
        suites.map { conformance in
            """
                /// `\(finding.typeName)` conforms to `\(conformance)`, so the kit checks \
            these laws.
                @Test("\(finding.typeName) — \(conformance) laws")
                func \(functionName(finding.typeName, conformance))() async throws {
                    let results = try await check\(conformance)PropertyLaws(
                        for: \(finding.typeName).self,
                        using: \(generator)\(options(conformance, isCaseIterable: isCaseIterable))
                    )
                    // Strict-tier only, matching `EnforcementMode.default` — which the kit
                    // already enforces by throwing. A blanket `allSatisfy { .passed }` is
                    // STRICTER THAN THE KIT INTENDS and fails on advisory findings: measured
                    // here, `Hashable.distribution` (Heuristic) fails for every CaseIterable
                    // enum, because 25 cases cannot fill 1000 trials with unique hashes. No
                    // generator fixes that; the domain is the type.
                    #expect(results.allSatisfy { $0.tier != .strict || $0.outcome == .passed })
                    // Feeds the verdicts back to `discover`, which demotes `==`-shaped laws
                    // about a carrier whose equality the kit refuted.
                    try KitEvidenceRecorder.record(
                        results, for: "\(finding.typeName)", packageRoot: Self.packageRoot
                    )
                }
            """
        }
        .joined(separator: "\n\n")
    }

    static func blockedBlock(
        _ finding: ProtocolCoverageAudit.Finding,
        suites: [String],
        reason: String
    ) -> String {
        let calls = suites.map { conformance in
            "    //     _ = try await check\(conformance)PropertyLaws("
                + "for: \(finding.typeName).self, using: \(finding.typeName).gen())"
        }
        .joined(separator: "\n")
        return """
            // \(finding.typeName) — \(finding.coveredLaws.count) law(s), \
        BLOCKED on a generator.
            // \(reason)
        \(calls)
        """
    }

    /// Skip `Hashable.distribution` for a `CaseIterable` enum, and nothing else.
    ///
    /// **Measured, not anticipated.** Running the first generated file, `KnownProperty` and
    /// `TemplateName` were the only two failures of 126: *"1000 samples produced only 25
    /// unique hashValues (ratio 0.025)"*. The law is right and the type is right — the
    /// generator draws from `allCases`, so the domain is the case list and 1000 trials
    /// cannot produce more distinct hashes than there are cases. No generator fixes it.
    ///
    /// Scoped to `.caseIterable` deliberately. On a wide domain a bad `hash(into:)` really
    /// does show up as clustering, so suppressing `distribution` everywhere would trade a
    /// real signal for a green run — the exact bargain `fixtures/toolchain-coverage` warns
    /// against when it says a reader who narrows a generator "should not widen it to silence
    /// the distribution law".
    ///
    /// The kit records a swift-testing Issue for a Heuristic violation even though
    /// `EnforcementMode.default` does not throw, so an assertion tightened to Strict is not
    /// enough on its own — the suppression is what keeps the emitted suite green.
    static func options(_ conformance: String, isCaseIterable: Bool) -> String {
        guard isCaseIterable, conformance == "Hashable" else { return "" }
        return """
        ,
                        options: LawCheckOptions(suppressions: [
                            // A CaseIterable domain cannot fill 1000 trials with distinct
                            // hashes; the law is degenerate here by construction, not failing.
                            .skip(
                                LawIdentifier(protocolName: "Hashable", lawName: "distribution"),
                                reason: "domain is `allCases` — fewer values than trials"
                            )
                        ])
        """
    }

    /// `VerifyHarness.LookupResult` + `Equatable` → `verifyHarnessLookupResultEquatable`.
    /// Nested types are the common case here and a dot is not legal in an identifier.
    static func functionName(_ typeName: String, _ conformance: String) -> String {
        let parts = typeName.split(separator: ".").map(String.init)
        let head = parts.first.map { $0.prefix(1).lowercased() + $0.dropFirst() } ?? ""
        let tail = parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return head + tail.joined() + conformance
    }
}
