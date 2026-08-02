import Foundation
@testable import SwiftInferCore
import Testing

/// The **law-level** half of the kit-coverage join, split from `KitCoverageDriftTests` on
/// 2026-08-02 when adding it took that file past the 400-line cap.
///
/// The split is the right seam, not an arithmetic one. `KitCoverageDriftTests` asks a
/// *suite*-granularity question — does the kit ship a `check<X>PropertyLaws` for every map
/// key, is every suite dispositioned. This file asks the *law*-granularity one: does that
/// suite actually run the specific laws the key claims. All four suite-level assertions
/// passed green through 13 false `(key, law)` pairs, because none of them opened the
/// `Set<KnownProperty>` on the value side.
extension KitCoverageDriftTests {

    // MARK: - Law-level join (2026-08-02)

    /// Each `KnownProperty` mapped to the kit law identifier(s) that actually implement it.
    ///
    /// **This is the join the four suite-level tests below never checked.** They assert that a
    /// map KEY names a real `check<X>PropertyLaws`; nothing opened the `Set<KnownProperty>` on
    /// the value side. `SetAlgebra` is a real suite and is in the map, so all four passed green
    /// while it claimed `setUnionAssociative` — a law the kit does not ship — and while four
    /// keys claimed the `Equatable` triple their entrypoints never run. 13 of 56 `(key, law)`
    /// pairs were false. See `docs/protocol-coverage-law-drift.md`.
    ///
    /// **The mapping is not 1:1**, which is why this could not be a string comparison:
    /// `.distributivity` is two kit laws, `.comparableTotalOrder` is three, and
    /// `.multiplicativeInverse` is deliberately zero — the enum carries it "for symmetry with
    /// `additiveInverse`" and no kit law implements it, so no map value may claim it.
    ///
    /// An entry here is a claim that the named laws EXIST in the kit. Whether a given map key
    /// actually reaches them is `coverageClaimsNameLawsTheKitRuns` below, and that is where
    /// delegation matters.
    static let kitLawsByProperty: [KnownProperty: [String]] = [
        .additiveAssociative: ["AdditiveArithmetic.additionAssociativity"],
        .additiveCommutative: ["AdditiveArithmetic.additionCommutativity"],
        .additiveIdentityZero: ["AdditiveArithmetic.zeroAdditiveIdentity"],
        .additiveInverse: ["SignedNumeric.additiveInverse"],
        .multiplicativeAssociative: ["Numeric.multiplicationAssociativity"],
        .multiplicativeCommutative: ["Numeric.multiplicationCommutativity"],
        .multiplicativeIdentityOne: ["Numeric.oneMultiplicativeIdentity"],
        // Intentionally empty — see the doc above. A non-empty value here would be a false claim.
        .multiplicativeInverse: [],
        .distributivity: ["Numeric.leftDistributivity", "Numeric.rightDistributivity"],
        .setUnionCommutative: ["SetAlgebra.unionCommutativity"],
        .setIntersectionCommutative: ["SetAlgebra.intersectionCommutativity"],
        .setSymmetricDifferenceCommutative: ["SetAlgebra.symmetricDifferenceCommutativity"],
        .setUnionEmptyIdentity: ["SetAlgebra.emptyIdentity"],
        .setUnionIdempotent: ["SetAlgebra.unionIdempotence"],
        .setIntersectionIdempotent: ["SetAlgebra.intersectionIdempotence"],
        .equatableReflexive: ["Equatable.reflexivity"],
        .equatableSymmetric: ["Equatable.symmetry"],
        .equatableTransitive: ["Equatable.transitivity"],
        .comparableTotalOrder: [
            "Comparable.antisymmetry", "Comparable.transitivity", "Comparable.totality"
        ],
        .hashableConsistency: ["Hashable.equalityConsistency"],
        .strideableDistanceRoundTrip: ["Strideable.distanceRoundTrip"],
        .losslessStringRoundTrip: ["LosslessStringConvertible.roundTrip"],
        .iteratorTerminationStability: ["IteratorProtocol.terminationStability"],
        .codableRoundTrip: ["Codable.roundTripFidelity"],
        .monoidIdentity: ["Monoid.combineLeftIdentity", "Monoid.combineRightIdentity"],
        .groupInverse: ["Group.combineLeftInverse", "Group.combineRightInverse"],
        .semilatticeIdempotence: ["Semilattice.combineIdempotence"]
    ]

    /// Law identifiers the kit declares, keyed by suite, read from the resolved checkout.
    ///
    /// The regex deliberately does not require a closing quote: `Codable`'s identifier is
    /// `"Codable.roundTripFidelity[\(codec)]"`, interpolated, and a stricter pattern silently
    /// dropped it — which would have read as "the kit does not ship a Codable law".
    static func kitLawIdentifiers(file: String = #filePath) -> [String: Set<String>]? {
        guard let sources = kitSourcesDirectory(file: file) else { return nil }
        let pattern = try? NSRegularExpression(pattern: #""([A-Z][A-Za-z]*)\.([a-zA-Z]+)"#)
        guard let enumerator = FileManager.default.enumerator(
            at: sources, includingPropertiesForKeys: nil
        ) else { return nil }
        var laws: [String: Set<String>] = [:]
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let whole = NSRange(text.startIndex..., in: text)
            pattern?.enumerateMatches(in: text, range: whole) { match, _, _ in
                guard let match,
                      let suite = Range(match.range(at: 1), in: text),
                      let law = Range(match.range(at: 2), in: text) else { return }
                laws[String(text[suite]), default: []].insert(String(text[law]))
            }
        }
        return laws.isEmpty ? nil : laws
    }

    /// `check<Suite>PropertyLaws` -> the parent suites it delegates to via
    /// `await check<Parent>PropertyLaws`.
    ///
    /// **Delegation must be READ, not assumed from Swift's conformance graph.** The map
    /// hand-baked transitive coverage on the theory that a protocol's suite runs its parent's
    /// laws; exactly two kit files do (`ComparableLaws`, `HashableLaws`), and
    /// `AdditiveArithmetic` / `SetAlgebra` do not. Deriving this from protocol inheritance
    /// would reproduce the bug inside its own guard.
    static func kitDelegations(file: String = #filePath) -> [String: Set<String>]? {
        guard let sources = kitSourcesDirectory(file: file) else { return nil }
        let defines = try? NSRegularExpression(
            pattern: #"public func check([A-Z][A-Za-z]*)PropertyLaws"#
        )
        let calls = try? NSRegularExpression(
            pattern: #"await check([A-Z][A-Za-z]*)PropertyLaws"#
        )
        guard let enumerator = FileManager.default.enumerator(
            at: sources, includingPropertiesForKeys: nil
        ) else { return nil }
        var edges: [String: Set<String>] = [:]
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            var defined: Set<String> = []
            defines?.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match, let captured = Range(match.range(at: 1), in: text) else { return }
                defined.insert(String(text[captured]))
            }
            guard let owner = defined.first, defined.count == 1 else { continue }
            calls?.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match, let captured = Range(match.range(at: 1), in: text) else { return }
                let parent = String(text[captured])
                if parent != owner { edges[owner, default: []].insert(parent) }
            }
        }
        return edges
    }

    /// Every law `check<suite>PropertyLaws` runs, following delegation transitively.
    static func effectiveLaws(
        of suite: String,
        laws: [String: Set<String>],
        delegations: [String: Set<String>],
        seen: Set<String> = []
    ) -> Set<String> {
        guard !seen.contains(suite) else { return [] }
        var result = Set((laws[suite] ?? []).map { "\(suite).\($0)" })
        for parent in delegations[suite] ?? [] {
            result.formUnion(
                effectiveLaws(
                    of: parent, laws: laws, delegations: delegations, seen: seen.union([suite])
                )
            )
        }
        return result
    }

    private static func kitSourcesDirectory(file: String) -> URL? {
        var directory = URL(fileURLWithPath: file).deletingLastPathComponent()
        while directory.path != "/" {
            let checkout = directory
                .appendingPathComponent(".build/checkouts/SwiftPropertyLaws/Sources")
            if FileManager.default.fileExists(atPath: checkout.path) { return checkout }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }

    @Test("every KnownProperty has a recorded kit-law mapping")
    func everyKnownPropertyIsMapped() {
        let unmapped = KnownProperty.allCases.filter { Self.kitLawsByProperty[$0] == nil }
        #expect(
            unmapped.isEmpty,
            Comment(rawValue: "KnownProperty case(s) with no kit-law mapping: "
                + "\(unmapped.map(\.rawValue).sorted()). Add each to `kitLawsByProperty` — "
                + "`[]` if the kit ships no such law, which also forbids any map value "
                + "claiming it.")
        )
    }

    @Test("every mapped kit law identifier actually exists in the kit")
    func mappedLawsExist() {
        guard let laws = Self.kitLawIdentifiers() else { return }
        for (property, identifiers) in Self.kitLawsByProperty {
            for identifier in identifiers {
                let parts = identifier.split(separator: ".", maxSplits: 1).map(String.init)
                let exists = laws[parts[0]]?.contains(parts[1]) ?? false
                #expect(
                    exists,
                    Comment(rawValue: "`\(property.rawValue)` maps to `\(identifier)`, which "
                        + "the kit does not ship. Either the kit dropped the law or the "
                        + "mapping was wrong from the start.")
                )
            }
        }
    }

    /// **The guard the suite-level tests could not be.** For every `(key, law)` claim in
    /// `ProtocolCoverageMap`, assert `check<key>PropertyLaws` really runs it — following
    /// delegation, because that is where the hand-baked transitive coverage was wrong.
    ///
    /// A failure here means `discover` is fully suppressing a suggestion on the grounds that
    /// PropertyLawKit checks the law, when it does not. The law then ends up checked by
    /// nothing, and the silence looks exactly like nothing to report.
    @Test("every ProtocolCoverageMap claim names a law that key's suite actually runs")
    func coverageClaimsNameLawsTheKitRuns() {
        guard let laws = Self.kitLawIdentifiers(), let delegations = Self.kitDelegations() else {
            return
        }
        for (key, properties) in ProtocolCoverageMap.protocolCoverage {
            let reachable = Self.effectiveLaws(of: key, laws: laws, delegations: delegations)
            guard !reachable.isEmpty else { continue }
            for property in properties.sorted(by: { $0.rawValue < $1.rawValue }) {
                let expected = Self.kitLawsByProperty[property] ?? []
                let missing = expected.filter { !reachable.contains($0) }
                #expect(
                    missing.isEmpty,
                    Comment(rawValue: "`ProtocolCoverageMap[\"\(key)\"]` claims "
                        + "`\(property.rawValue)`, but `check\(key)PropertyLaws` does not run "
                        + "\(missing.sorted()). The veto suppresses a law nothing checks.")
                )
                #expect(
                    !expected.isEmpty,
                    Comment(rawValue: "`ProtocolCoverageMap[\"\(key)\"]` claims "
                        + "`\(property.rawValue)`, which maps to NO kit law at all.")
                )
            }
        }
    }
}
