import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// `UnequatableResultGate` — a law that compares two RESULTS is not written over a scanned type
/// nothing makes `Equatable`, and only then.
///
/// The type universe is scanned from source and folded the way discover folds it
/// (`TypeShapeBuilder.shapes`, keyed by the qualified name; `inheritedTypesIndex`, keyed by the
/// bare one), because the gate's whole difficulty is that the two maps key nested types
/// differently.
@Suite("UnequatableResultGate — `==` over a result nothing makes Equatable")
struct UnequatableResultGateTests {

    struct Scan {
        let shapes: [String: TypeShape]
        let inherited: [String: Set<String>]
    }

    static func scan(_ files: [String: String]) -> Scan {
        let decls = files.flatMap { FunctionScanner.scanCorpus(source: $0.value, file: $0.key).typeDecls }
        let shapes = TypeShapeBuilder.shapes(from: decls)
        return Scan(
            shapes: Dictionary(uniqueKeysWithValues: shapes.map { ($0.name, $0) }),
            inherited: ProtocolCoverageMap.inheritedTypesIndex(from: decls)
        )
    }

    static func reason(_ result: String, owner: String? = "Fixer", in scan: Scan) -> String? {
        UnequatableResultGate.declineReason(
            display: "fix(_:)",
            returnTypeText: result,
            owner: owner,
            typeShapesByName: scan.shapes,
            inheritedTypesByName: scan.inherited
        )
    }

    static let plainSource = """
        struct Fixer {}
        struct FixResult { let text: String }
        enum Outcome { case fixed(String), skipped }
        enum Level { case low, high }
        """

    static let plain = scan(["Fix.swift": plainSource])

    // MARK: - Declined

    @Test("a scanned type with no conformance, however the result wraps it", arguments: [
        "FixResult", "[FixResult]", "FixResult?", "(FixResult, Int)"
    ])
    func aScannedUnconformingTypeDeclines(result: String) throws {
        let reason = try #require(Self.reason(result, in: Self.plain))
        #expect(reason == "fix(_:) returns \(result), and no scanned declaration makes FixResult Equatable, "
            + "so `==` cannot compare two results")
    }

    @Test func anEnumWithAPayloadAndNoConformanceDeclines() throws {
        let reason = try #require(Self.reason("Outcome", in: Self.plain))
        #expect(reason.contains("makes Outcome Equatable"))
    }

    /// `Inner` written inside `Outer` is `Outer.Inner` in the scan's keys.
    @Test func aBareNestedSpellingIsResolvedThroughTheUniverse() throws {
        let scan = Self.scan(["Outer.swift": "struct Outer {\n    struct Inner { let x: Int }\n}"])
        let reason = try #require(Self.reason("[Inner]", owner: "Outer", in: scan))
        #expect(reason.contains("makes Outer.Inner Equatable"))
    }

    @Test func selfIsJudgedAsTheOwner() throws {
        let scan = Self.scan(["Counter.swift": "struct Counter { var count: Int }"])
        let reason = try #require(Self.reason("Self?", owner: "Counter", in: scan))
        #expect(reason.contains("returns Self?"))
        #expect(reason.contains("makes Counter Equatable"))
    }

    // MARK: - Written

    @Test func aConformanceDeclaredInAnotherFileCounts() {
        let scan = Self.scan([
            "FixResult.swift": "struct FixResult { let text: String }",
            "FixResult+Equatable.swift": "extension FixResult: Equatable {}"
        ])
        #expect(scan.shapes["FixResult"]?.inheritedTypes.isEmpty == true, "the shape alone cannot see it")
        #expect(Self.reason("FixResult", in: scan) == nil)
    }

    @Test("a refining protocol counts", arguments: ["Hashable", "Comparable", "Swift.Equatable"])
    func aRefiningProtocolCounts(conformance: String) {
        let scan = Self.scan(["Key.swift": "struct Key: \(conformance) { let raw: Int }"])
        #expect(Self.reason("[Key]", in: scan) == nil)
    }

    /// The conformance index is keyed by the name a declaration or extension SPELLS, while the
    /// shapes are keyed by the qualified name — so both must be read. `extension Outer.Inner` is
    /// indexed under `Outer.Inner`, and a nested declaration's own clause is in its shape; the bare
    /// read is for an extension written through a file-scope alias, which Swift accepts (`swiftc`,
    /// Swift 6.4) and the index records under the alias's name alone. (A bare
    /// `extension Inner: Equatable {}` with no alias does not compile: *cannot find type 'Inner'*.)
    @Test func aConformanceRecordedUnderTheBareNestedNameCounts() {
        let scan = Self.scan([
            "Outer.swift": "struct Outer {\n    struct Inner { let x: Int }\n}",
            "Inner+Equatable.swift": "typealias Inner = Outer.Inner\nextension Inner: Equatable {}"
        ])
        #expect(scan.inherited["Inner"]?.contains("Equatable") == true)
        #expect(scan.inherited["Outer.Inner"] == nil)
        #expect(Self.reason("Inner", owner: "Outer", in: scan) == nil)
    }

    /// The qualified extension needs no bare read: the index records it under `Outer.Inner`.
    @Test func aConformanceOnTheQualifiedExtensionCounts() {
        let scan = Self.scan([
            "Outer.swift": "struct Outer {\n    struct Inner { let x: Int }\n}",
            "Inner+Equatable.swift": "extension Outer.Inner: Equatable {}"
        ])
        #expect(scan.inherited["Outer.Inner"]?.contains("Equatable") == true)
        #expect(Self.reason("[Inner]", owner: "Outer", in: scan) == nil)
    }

    /// Swift synthesises `Equatable` for an enum without payloads; no declaration says so.
    @Test func anEnumWithoutPayloadsIsImplicitlyEquatable() {
        #expect(Self.reason("Level", in: Self.plain) == nil)
    }

    /// A conformance that leaves the scan is not evidence of anything: `NSObject` and
    /// `AdditiveArithmetic` both supply `==`, and neither is on the refiner list (`swiftc`).
    @Test("a chain that leaves the scan is left to the compiler", arguments: [
        "struct Result: AdditiveArithmetic { var cents: Int }",
        "final class Result: NSObject {}",
        "protocol Amount: AdditiveArithmetic {}\nstruct Result: Amount { var cents: Int }",
        "struct Result: Hashable & Codable { let raw: Int }"
    ])
    func aChainLeavingTheScanIsNotDeclined(source: String) {
        let scan = Self.scan(["Result.swift": source])
        #expect(Self.reason("Result", in: scan) == nil)
    }

    /// The other side: a chain that ends only in names known to stop short of `Equatable` is
    /// evidence, and a scanned superclass is followed.
    @Test("a chain of known non-Equatable names still declines", arguments: [
        "struct Result: Sendable, Codable { let raw: Int }",
        "class Base {}\nfinal class Result: Base {}",
        "protocol Labelled: CustomStringConvertible {}\nstruct Result: Labelled { var description: String }"
    ])
    func aChainOfKnownNamesDeclines(source: String) {
        let scan = Self.scan(["Result.swift": source])
        #expect(Self.reason("Result", in: scan)?.contains("makes Result Equatable") == true)
    }

    @Test("a type the scan never saw is never declined", arguments: [
        "URL", "[String: Int]", "Result<Int, Error>", "Int?"
    ])
    func anUnscannedTypeIsLeftAlone(result: String) {
        #expect(Self.reason(result, in: Self.plain) == nil)
    }

    // MARK: - The accept gate

    @Test func onlyADeterminismLawIsGated() throws {
        let evidence = try SubjectCallPlanTests.evidence(
            "struct Fixer {\n    static func fix(_ source: String) -> FixResult { fatalError() }\n}",
            named: "fix"
        )
        let law = SubjectCallPlanBothSidesTests.suggestion(for: evidence)
        let reason = UnequatableResultGate.declineReason(
            for: law, typeShapesByName: Self.plain.shapes, inheritedTypesByName: Self.plain.inherited
        )
        #expect(reason?.hasPrefix("fix(_:) returns FixResult") == true)
        var predicate = law
        predicate.templateName = "predicate"
        #expect(UnequatableResultGate.declineReason(
            for: predicate, typeShapesByName: Self.plain.shapes, inheritedTypesByName: Self.plain.inherited
        ) == nil)
    }
}
