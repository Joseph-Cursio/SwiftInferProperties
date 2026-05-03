import Foundation
import Testing
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates

/// PRD §16 #1 allowlist hard-guarantees — M6 / M7 / M8 writeout paths
/// must never escape `Tests/Generated/SwiftInfer*/` or
/// `.swiftinfer/decisions.json`. Adjacent suite to
/// `HardGuaranteeTests` which covers the §16 #6 reproducibility +
/// §14 telemetry pieces.
@Suite("Hard guarantees — PRD §16 #1 writeout allowlist (M6/M7/M8)")
struct HardGuaranteeAllowlistTests {

    @Test("--interactive accept writes only under Tests/Generated/SwiftInfer/")
    func interactiveAcceptWritesOnlyUnderGeneratedTests() throws {
        let directory = try makeAllowlistM6Fixture(named: "InteractiveAcceptAllowlist")
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("Sources").appendingPathComponent("Lib")
        let before = try fileSet(of: directory)
        try SwiftInferCommand.Discover.run(
            directory: target,
            interactive: true,
            promptInput: HGScriptedPromptInput(scriptedLines: ["A"]),
            output: HGSilentOutput(),
            diagnostics: HGSilentDiagnosticOutput()
        )
        let after = try fileSet(of: directory)
        let added = after.subtracting(before)
        // Two paths added: the property-test stub + the decisions.json
        // record. Both match the M6 plan's allowlist.
        for path in added {
            #expect(
                path.hasPrefix("/Tests/Generated/SwiftInfer/")
                    || path.hasPrefix("/.swiftinfer/decisions.json"),
                "M6 --interactive accept wrote outside the allowlist: \(path)"
            )
        }
        // Source files untouched.
        let sourceBefore = before.filter { $0.hasPrefix("/Sources/") }
        let sourceAfter = after.filter { $0.hasPrefix("/Sources/") }
        #expect(sourceBefore == sourceAfter)
    }

    @Test("--interactive B accept writes only under Tests/Generated/SwiftInferRefactors/")
    func interactiveBAcceptWritesOnlyUnderRefactorsAllowlist() throws {
        let directory = try makeAllowlistM7Fixture(named: "BridgeAllowlist")
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("Sources").appendingPathComponent("Lib")
        let before = try fileSet(of: directory)
        try SwiftInferCommand.Discover.run(
            directory: target,
            interactive: true,
            promptInput: HGScriptedPromptInput(scriptedLines: ["B", "s", "s", "s"]),
            output: HGSilentOutput(),
            diagnostics: HGSilentDiagnosticOutput()
        )
        let after = try fileSet(of: directory)
        let added = after.subtracting(before)
        for path in added {
            #expect(
                path.hasPrefix("/Tests/Generated/SwiftInferRefactors/")
                    || path.hasPrefix("/.swiftinfer/decisions.json"),
                "M7 --interactive B accept wrote outside the allowlist: \(path)"
            )
        }
        // The file written must follow the per-PRD §16 #1 path convention.
        let conformancePath = added.first {
            $0.hasPrefix("/Tests/Generated/SwiftInferRefactors/")
        }
        #expect(conformancePath != nil, "RefactorBridge B accept did not write a conformance file")
        if let path = conformancePath {
            #expect(path.contains("/Bag/Semigroup.swift") || path.contains("/Bag/Monoid.swift"))
        }
        let sourceBefore = before.filter { $0.hasPrefix("/Sources/") }
        let sourceAfter = after.filter { $0.hasPrefix("/Sources/") }
        #expect(sourceBefore == sourceAfter)
    }

    @Test("M8 --interactive B accept honors the SwiftInferRefactors/ allowlist for every new arm")
    func interactiveBAcceptOnEachM8ArmHonorsAllowlist() throws {
        // Builds a fixture corpus where each of the four M8 promotion
        // arms (CommutativeMonoid / Group / Semilattice / Ring) fires
        // on a distinct type. Runs `--interactive` with scripted "B"
        // inputs for every prompt, then asserts every added file is
        // under the SwiftInferRefactors/ allowlist + decisions.json.
        let directory = try makeAllowlistM8Fixture(named: "M8AllArmsAllowlist")
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("Sources").appendingPathComponent("Lib")
        let before = try fileSet(of: directory)
        let script = Array(repeating: "B", count: 10) + Array(repeating: "s", count: 30)
        try SwiftInferCommand.Discover.run(
            directory: target,
            interactive: true,
            promptInput: HGScriptedPromptInput(scriptedLines: script),
            output: HGSilentOutput(),
            diagnostics: HGSilentDiagnosticOutput()
        )
        let after = try fileSet(of: directory)
        let added = after.subtracting(before)
        for path in added {
            let isInfer = path.hasPrefix("/Tests/Generated/SwiftInfer/")
            let isRefactors = path.hasPrefix("/Tests/Generated/SwiftInferRefactors/")
            let isDecisions = path == "/.swiftinfer/decisions.json"
            #expect(
                isInfer || isRefactors || isDecisions,
                "M8 --interactive accept wrote outside the allowlist: \(path)"
            )
        }
        // At least one Refactors writeout must exist.
        let refactorsPaths = added.filter {
            $0.hasPrefix("/Tests/Generated/SwiftInferRefactors/")
        }
        #expect(!refactorsPaths.isEmpty, "expected at least one M8 conformance writeout")
        let m8Protocols = ["CommutativeMonoid", "Group", "Semilattice", "Numeric", "SetAlgebra"]
        let firedM8Arm = refactorsPaths.contains { path in
            m8Protocols.contains { path.contains("/\($0).swift") }
        }
        #expect(firedM8Arm, "expected at least one of \(m8Protocols) to surface; got: \(refactorsPaths)")
        for path in refactorsPaths {
            let parts = path.components(separatedBy: "/").suffix(2)
            #expect(parts.count == 2,
                "expected /Tests/Generated/SwiftInferRefactors/<TypeName>/<ProtocolName>.swift; got: \(path)")
            #expect(path.hasSuffix(".swift"),
                "expected .swift extension; got: \(path)")
        }
        let sourceBefore = before.filter { $0.hasPrefix("/Sources/") }
        let sourceAfter = after.filter { $0.hasPrefix("/Sources/") }
        #expect(sourceBefore == sourceAfter)
    }

    @Test("--update-baseline writes only .swiftinfer/baseline.json under packageRoot")
    func updateBaselineWritesOnlyToConventionalPath() throws {
        let directory = try makeAllowlistM6Fixture(named: "UpdateBaselineAllowlist")
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("Sources").appendingPathComponent("Lib")
        let before = try fileSet(of: directory)
        try SwiftInferCommand.Discover.run(
            directory: target,
            updateBaseline: true,
            output: HGSilentOutput(),
            diagnostics: HGSilentDiagnosticOutput()
        )
        let after = try fileSet(of: directory)
        let added = after.subtracting(before)
        #expect(added == ["/.swiftinfer/baseline.json"])
    }
}

// MARK: - Allowlist-fixture helpers

/// Build a Package.swift-rooted fixture with one `Sources/Lib/`
/// target so the M6 `--interactive` / `--update-baseline` writeouts
/// have a real package boundary to anchor at.
private func makeAllowlistM6Fixture(named name: String) throws -> URL {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("SwiftInferM6Guarantee-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    try Data("// swift-tools-version: 6.1\n".utf8).write(
        to: base.appendingPathComponent("Package.swift")
    )
    let target = base.appendingPathComponent("Sources").appendingPathComponent("Lib")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try """
    struct Sanitizer {
        func normalize(_ value: String) -> String {
            return normalize(normalize(value))
        }
    }
    """.write(
        to: target.appendingPathComponent("Source.swift"),
        atomically: true,
        encoding: .utf8
    )
    return base
}

/// Package fixture with a `Bag` type that fires the M2 associativity
/// + identity-element templates. The orchestrator (M7.5) aggregates
/// those signals into a Monoid proposal on `Bag`.
private func makeAllowlistM7Fixture(named name: String) throws -> URL {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("SwiftInferM7Bridge-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    try Data("// swift-tools-version: 6.1\n".utf8).write(
        to: base.appendingPathComponent("Package.swift")
    )
    let target = base.appendingPathComponent("Sources").appendingPathComponent("Lib")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try """
    struct Bag: Equatable {
        static let empty = Bag()
        static func merge(_ first: Bag, _ second: Bag) -> Bag { first }
    }
    """.write(
        to: target.appendingPathComponent("Bag.swift"),
        atomically: true,
        encoding: .utf8
    )
    return base
}

/// M8.6 fixture exercising each new orchestrator promotion arm on a
/// distinct type: Tally → CommutativeMonoid, AdditiveInt → Group,
/// MaxInt → Semilattice, Money → Ring (Numeric).
private func makeAllowlistM8Fixture(named name: String) throws -> URL {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("SwiftInferM8MultiArm-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    try Data("// swift-tools-version: 6.1\n".utf8).write(
        to: base.appendingPathComponent("Package.swift")
    )
    let target = base.appendingPathComponent("Sources").appendingPathComponent("Lib")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    // M2.5's IdentityElementTemplate requires explicit `: T` type
    // annotation on identity-candidate declarations — every static let
    // below carries an explicit annotation.
    try """
    struct Tally: Equatable {
        static let empty: Tally = Tally()
        static func merge(_ lhs: Tally, _ rhs: Tally) -> Tally { lhs }
    }

    struct AdditiveInt: Equatable {
        static let zero: AdditiveInt = AdditiveInt()
        static func plus(_ lhs: AdditiveInt, _ rhs: AdditiveInt) -> AdditiveInt { lhs }
        static func negate(_ value: AdditiveInt) -> AdditiveInt { value }
    }

    struct MaxInt: Equatable {
        static let minimum: MaxInt = MaxInt()
        static func combine(_ lhs: MaxInt, _ rhs: MaxInt) -> MaxInt { lhs }
    }

    struct Money: Equatable {
        static let zero: Money = Money()
        static let one: Money = Money()
        static func add(_ lhs: Money, _ rhs: Money) -> Money { lhs }
        static func multiply(_ lhs: Money, _ rhs: Money) -> Money { lhs }
    }
    """.write(
        to: target.appendingPathComponent("M8Arms.swift"),
        atomically: true,
        encoding: .utf8
    )
    return base
}
