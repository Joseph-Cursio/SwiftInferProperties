import Foundation
@testable import SwiftInferCLI
@testable import SwiftInferCore
import Testing

/// Guards the Unverifiable cause breakdown, added 2026-08-13 after `report` told a reader that
/// every Unverifiable pick was one `static func gen()` away when that cause accounted for
/// **1 of 18** rows (`docs/measurements/exploratory-swiftformatrulestudio.md` §5.1).
@Suite("Unverifiable cause attribution")
struct UnverifiableCauseTests {

    // MARK: - Classification

    @Test(
        "each detail prefix classifies to its own cause",
        arguments: [
            ("unsupported-template: input-totality", UnverifiableCause.unsupportedTemplate),
            ("unsupported-carrier: ConfigModel", .unsupportedCarrier),
            ("unsupported-pair: encode(_:)", .unsupportedPair),
            ("not-a-candidate: no test can name the subject: it is `private`", .subjectNotVisible),
            ("instance-method-shape-not-supported", .instanceMethodShape),
            ("monotonicity-domain-not-comparable: Money", .monotonicityDomainNotComparable)
        ]
    )
    func classifies(detail: String, expected: UnverifiableCause) {
        #expect(UnverifiableCause.classify(detail: detail) == expected)
    }

    @Test("an unknown detail is unrecognised, NOT folded into a known cause")
    func unknownIsNotFolded() {
        // The load-bearing arm. Bucketing an unrecognised detail under the largest known cause
        // is precisely how the original defect read as true — a confident wrong attribution
        // instead of an admitted gap.
        #expect(UnverifiableCause.classify(detail: "something-new: X") == .unrecognised)
        #expect(UnverifiableCause.classify(detail: nil) == .unrecognised)
        #expect(UnverifiableCause.classify(detail: "") == .unrecognised)
    }

    @Test("every cause has a distinct, non-empty label and remedy")
    func everyCaseIsSpoken() {
        // Parameterised over `CaseIterable` so a cause added later cannot ship with an empty
        // or duplicated line — the same shape as `everyFamilyMarksItsCheck`.
        for cause in UnverifiableCause.allCases {
            #expect(!cause.label.isEmpty)
            #expect(!cause.remedy.isEmpty)
        }
        #expect(Set(UnverifiableCause.allCases.map(\.label)).count
            == UnverifiableCause.allCases.count)
        #expect(Set(UnverifiableCause.allCases.map(\.remedy)).count
            == UnverifiableCause.allCases.count)
    }

    @Test("the `gen()` remedy is claimed for the carrier cause and NOTHING else")
    func genHookIsScoped() {
        // The whole defect in one assertion: `gen()` was prescribed for all six causes and
        // unblocks exactly one.
        let claiming = UnverifiableCause.allCases.filter { $0.remedy.contains("static func gen()") }
        #expect(claiming == [.unsupportedCarrier])
    }

    @Test("the two causes the reader CANNOT fix say so")
    func toolGapsAreAdmitted() {
        // Prescribing work that cannot move the number is worse than admitting the gap,
        // because only the admission stops the reader doing it.
        #expect(UnverifiableCause.unsupportedTemplate.remedy.contains("not in your code"))
        #expect(UnverifiableCause.instanceMethodShape.remedy.contains("not in your code"))
    }

    // MARK: - Rendering

    @Test("the measured 18-row population renders every cause with its own count")
    func rendersMeasuredPopulation() throws {
        // The exact split measured on SwiftFormatRuleStudioCore: 9 / 6 / 2 / 1.
        let details =
            Array(repeating: "unsupported-template: input-totality", count: 9)
            + Array(repeating: "not-a-candidate: it is `private`", count: 6)
            + Array(repeating: "instance-method-shape-not-supported", count: 2)
            + ["unsupported-carrier: ConfigModel"]

        let rendered = GenHookHint.lines(details: details).joined(separator: "\n")

        #expect(rendered.contains("no composer for the template 9"))
        #expect(rendered.contains("subject not visible to tests 6"))
        #expect(rendered.contains("instance-method shape 2"))
        #expect(rendered.contains("no generator for the carrier 1"))
        // Ordered by count, so the biggest lever reads first.
        let composerIndex = try #require(rendered.range(of: "no composer for the template"))
        let carrierIndex = try #require(rendered.range(of: "no generator for the carrier"))
        #expect(composerIndex.lowerBound < carrierIndex.lowerBound)
        // And the `gen()` advice is now attached to a line that says it covers ONE row.
        #expect(rendered.contains("1 — add `static func gen()"))
    }

    @Test("counts are conserved — every row lands in exactly one cause")
    func countsAreConserved() {
        // A breakdown that drops rows would understate a gap while looking precise, which is
        // the failure mode one level along from the one being fixed.
        let details: [String?] = [
            "unsupported-template: predicate", "unsupported-carrier: X",
            "totally-unknown-detail", nil
        ]
        let rendered = GenHookHint.lines(details: details).joined(separator: "\n")
        let counted = rendered
            .components(separatedBy: "\n")
            .dropFirst()
            .compactMap { line in line.components(separatedBy: " — ").first }
            .compactMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: " ·"))) }
            .reduce(0, +)
        #expect(counted == details.count)
        // The unknown and the nil collapse into one `unrecognised` bucket of 2, and it is
        // SHOWN rather than silently dropped.
        #expect(rendered.contains("unrecognised 2"))
    }

    @Test("no Unverifiable rows renders nothing at all")
    func emptyRendersNothing() {
        #expect(GenHookHint.lines(details: []).isEmpty)
    }

    // MARK: - The producers

    @Test("the prefixes this reads are the ones the verify path writes")
    func prefixesMatchProducers() throws {
        // The coupling this design accepts, made checkable. `detail` is a human-readable
        // string and this parses it, so a producer renaming a prefix would silently reclassify
        // a whole population to `unrecognised` — a user-facing count degrading with every test
        // still green. Asserted against the real source rather than a copy of it.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftInferCLITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
        let producers = [
            "Sources/SwiftInferCLI/VerifyCommand+AllFromIndexRecords.swift",
            "Sources/SwiftInferCLI/VerifyCommand+ArchitecturalPendingDetail.swift"
        ]
        let corpus = try producers
            .map { try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }
            .joined()

        // Not vacuous: assert the corpus was actually read before asserting things about it.
        #expect(corpus.count > 1_000)
        for (prefix, cause) in UnverifiableCause.prefixes {
            #expect(
                corpus.contains("\"\(prefix)"),
                "no producer writes the `\(prefix)` prefix that \(cause) classifies on"
            )
        }
    }
}
