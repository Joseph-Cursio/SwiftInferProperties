import Foundation
import SwiftInferCore
import Testing

/// `ProtocolCoverageMap` is a hand-kept subset of PropertyLawKit, and nothing kept the two
/// in step. This suite is that mechanism.
///
/// **Why it exists.** The map models 13 protocols; the kit ships **44** `check…PropertyLaws`
/// suites. That gap produced three findings in one study before anyone went looking for a
/// fourth:
///
/// 1. `Sequence` / `Collection` — 96 swift.org sites verdicted as catalog gaps until someone
///    checked the kit and found `checkCollectionPropertyLaws`. Epistemic only.
/// 2. `LosslessStringConvertible` — the float parse/print law, undeclinable. Epistemic only.
/// 3. **`Strideable` — a live double-report.** The kit runs
///    `"Strideable.distanceRoundTrip"`, `first.advanced(by: first.distance(to: second)) ==
///    second` (`StrideableLaws.swift:72`). `discover` independently proposes
///    `distance(to:)` × `advanced(by:)` as a `round-trip` on `stdlib/public/core`. Same law,
///    reported twice, which is exactly what `protocolCoveredProperty` exists to prevent —
///    *"re-reporting another tool's finding teaches people the tools disagree."*
///
/// The first two were harmless. The third is not, and it was found by building this test
/// rather than by using the tool — which is the argument for the test.
///
/// **What it asserts:** every kit law suite has a recorded `Disposition`. It does not require
/// coverage — plenty of suites legitimately have none — it requires a *decision*. A new kit
/// suite lands as unclassified and fails here, which is the drift this could not previously
/// detect.
@Suite("Kit coverage drift — every PropertyLawKit suite has a recorded disposition")
struct KitCoverageDriftTests {

    /// What we have decided about a kit law suite.
    enum Disposition {
        /// `ProtocolCoverageMap` has an entry; the veto can suppress a redundant suggestion.
        case covered
        /// Not a Swift protocol a carrier can conform to — a kit-invented law shape
        /// (`ValueSemantic`, `InteractionInvariant`) or a data-structure suite (`Heap`).
        /// There is no conformance to key a veto on, so coverage is not applicable.
        case notAConformance
        /// A real Swift protocol, uncovered, and **no template proposes its laws** — so
        /// nothing is double-reported today. Recorded, not urgent.
        case uncoveredNoSymptom(String)
        /// A real Swift protocol, uncovered, and a template **does** propose its law, so the
        /// toolchain reports the same finding twice. A live defect.
        case uncoveredDoubleReports(String)
    }

    /// The decision for each of the kit's 44 suites, at SwiftPropertyLaws 3.21.0.
    static let dispositions: [String: Disposition] = [
        // — covered —
        "AdditiveArithmetic": .covered, "Codable": .covered, "CommutativeMonoid": .covered,
        "Comparable": .covered, "Equatable": .covered, "Group": .covered,
        "Hashable": .covered, "Monoid": .covered, "Numeric": .covered,
        "Semigroup": .covered, "Semilattice": .covered, "SetAlgebra": .covered,
        "SignedNumeric": .covered,

        // — no conformance to key on —
        "ActionIdempotenceInvariant": .notAConformance,
        "InteractionInvariant": .notAConformance,
        "DefensiveCopy": .notAConformance,
        "ValueSemantic": .notAConformance,
        "StableIdentity": .notAConformance,
        "OrderPreservation": .notAConformance,
        "Transformation": .notAConformance,
        "DequeSymmetry": .notAConformance,
        "Heap": .notAConformance,
        "Ring": .notAConformance,

        // — LIVE DEFECT —
        "Strideable": .uncoveredDoubleReports(
            "The kit runs Strideable.distanceRoundTrip; `round-trip` independently proposes "
                + "`distance(to:)` x `advanced(by:)` on stdlib/public/core. Same law, twice."
        ),

        // — uncovered, no template proposes these laws today —
        "Sequence": .uncoveredNoSymptom("96 swift.org witnesses; no collection template"),
        "Collection": .uncoveredNoSymptom("as Sequence"),
        "BidirectionalCollection": .uncoveredNoSymptom("as Sequence"),
        "RandomAccessCollection": .uncoveredNoSymptom("as Sequence"),
        "MutableCollection": .uncoveredNoSymptom("as Sequence"),
        "RangeReplaceableCollection": .uncoveredNoSymptom("as Sequence"),
        "IteratorProtocol": .uncoveredNoSymptom("as Sequence"),
        "AsyncSequence": .uncoveredNoSymptom("async is admitted only via @ClockDeterministic"),
        "TimedAsyncSequence": .uncoveredNoSymptom("as AsyncSequence"),
        "LosslessStringConvertible": .uncoveredNoSymptom(
            "the round-trip law is unreachable anyway — initializerPairAdmissible rejects the "
                + "protocol's own unlabelled `init?(_ description: String)`"
        ),
        "StringProtocol": .uncoveredNoSymptom("no template keys on it"),
        "CaseIterable": .uncoveredNoSymptom("caseiterable-* templates emit their own laws"),
        "Identifiable": .uncoveredNoSymptom("no template keys on it"),
        "RawRepresentable": .uncoveredNoSymptom("no template keys on it"),
        "BinaryInteger": .uncoveredNoSymptom("numeric hierarchy; Numeric is covered"),
        "FixedWidthInteger": .uncoveredNoSymptom("as BinaryInteger"),
        "SignedInteger": .uncoveredNoSymptom("as BinaryInteger"),
        "UnsignedInteger": .uncoveredNoSymptom("as BinaryInteger"),
        "FloatingPoint": .uncoveredNoSymptom("as BinaryInteger"),
        "BinaryFloatingPoint": .uncoveredNoSymptom("as BinaryInteger")
    ]

    /// The kit's suites, read from the resolved checkout rather than hard-coded — a
    /// hard-coded list could not detect the drift this suite exists to detect.
    ///
    /// Located by walking up from `#filePath` to the package root, so it does not depend on
    /// the working directory `swift test` was invoked from.
    static func kitSuiteNames(file: String = #filePath) -> [String]? {
        var directory = URL(fileURLWithPath: file).deletingLastPathComponent()
        while directory.path != "/" {
            let checkout = directory
                .appendingPathComponent(".build/checkouts/SwiftPropertyLaws/Sources")
            if FileManager.default.fileExists(atPath: checkout.path) {
                var names: Set<String> = []
                let pattern = try? NSRegularExpression(
                    pattern: #"func check([A-Z][A-Za-z]*)PropertyLaws"#
                )
                guard let enumerator = FileManager.default.enumerator(
                    at: checkout, includingPropertiesForKeys: nil
                ) else { return nil }
                for case let url as URL in enumerator where url.pathExtension == "swift" {
                    guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                    let range = NSRange(text.startIndex..., in: text)
                    pattern?.enumerateMatches(in: text, range: range) { match, _, _ in
                        guard let match, let captured = Range(match.range(at: 1), in: text) else {
                            return
                        }
                        names.insert(String(text[captured]))
                    }
                }
                return names.isEmpty ? nil : names.sorted()
            }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }

    @Test("every kit law suite has a recorded disposition")
    func everyKitSuiteIsClassified() {
        // Skipped rather than failed when the checkout is absent: this asserts a property of
        // the DEPENDENCY, and an environment without it should not turn red for that reason.
        // The skip is loud in the message so a permanently-skipped run is noticeable.
        guard let suites = Self.kitSuiteNames() else {
            let skipped = "SKIPPED: .build/checkouts/SwiftPropertyLaws not found, so kit "
                + "drift could not be checked. Only meaningful after a resolved build."
            Issue.record(Comment(rawValue: skipped))
            return
        }
        let unclassified = suites.filter { Self.dispositions[$0] == nil }
        let complaint = "PropertyLawKit gained law suite(s) with no recorded disposition: "
            + "\(unclassified.joined(separator: ", ")). Add each to `dispositions` — "
            + "`.covered` if ProtocolCoverageMap should suppress it, or a recorded reason."
        #expect(unclassified.isEmpty, Comment(rawValue: complaint))
    }

    @Test("every suite marked .covered really is in ProtocolCoverageMap")
    func coveredClaimsAreTrue() {
        for (name, disposition) in Self.dispositions {
            guard case .covered = disposition else { continue }
            #expect(
                ProtocolCoverageMap.protocolCoverage[name] != nil,
                Comment(rawValue: "\(name) is marked .covered but has no ProtocolCoverageMap entry")
            )
        }
    }

    @Test("every ProtocolCoverageMap entry is a suite the kit actually ships")
    func coverageEntriesAreNotStale() {
        guard let suites = Self.kitSuiteNames() else { return }
        let known = Set(suites)
        // A map entry naming a suite the kit dropped would silently veto forever.
        for name in ProtocolCoverageMap.protocolCoverage.keys where !known.contains(name) {
            let stale = "ProtocolCoverageMap covers '\(name)' but the kit ships no "
                + "check\(name)PropertyLaws — the veto may suppress on a law nobody runs."
            Issue.record(Comment(rawValue: stale))
        }
    }

    /// Pins the live defect so it cannot be quietly forgotten, and so closing it turns this
    /// test red — which is the signal to delete the entry.
    @Test("the known double-report is still exactly one, and still Strideable")
    func liveDefectIsPinned() {
        let live = Self.dispositions.compactMap { name, disposition -> String? in
            if case .uncoveredDoubleReports = disposition { return name }
            return nil
        }
        let drifted = "The set of known double-reports changed to \(live). If Strideable was "
            + "fixed, remove it from `dispositions` and update the suite doc; if a new one "
            + "appeared, it is a live defect and wants its own fix."
        #expect(live == ["Strideable"], Comment(rawValue: drifted))
    }
}
