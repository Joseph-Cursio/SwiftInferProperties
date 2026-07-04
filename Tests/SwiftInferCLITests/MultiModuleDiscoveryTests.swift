import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Multi-module reducer discovery — scanning more than one `--target`, tagging
/// candidates by module, and matching a module-qualified `--reducer` pin so a
/// reducer in one module is disambiguated from a same-named reducer in another.
/// The `multi-module-discovery-corpus` fixture puts an identical `CounterReducer`
/// (same type / State / Action names) in both `Sources/Alpha/` and
/// `Sources/Beta/`.
@Suite("Multi-module discovery — cross-module reducer disambiguation")
struct MultiModuleDiscoveryTests {

    static let corpusRoot: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferCLITests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("multi-module-discovery-corpus")
    }()

    static let fixedDate = ISO8601DateFormatter().date(from: "2026-07-04T10:00:00Z")!

    @Test("two modules with a same-named reducer both surface (module tagging beats dedupe)")
    func twoModulesBothSurface() throws {
        let suggestions = try SwiftInferCommand.DiscoverInteraction.collectSuggestions(
            targets: ["Alpha", "Beta"],
            workingDirectory: Self.corpusRoot,
            firstSeenAt: Self.fixedDate
        )
        // Without module tagging, dedupe-by-(State, Action) would collapse the
        // two identical CounterReducers into one. Tagged, both survive.
        let locations = suggestions.map(\.reducerLocation)
        #expect(locations.contains { $0.contains("/Alpha/") })
        #expect(locations.contains { $0.contains("/Beta/") })
    }

    @Test("a module-qualified pin selects only that module's reducer")
    func modulePinDisambiguates() throws {
        let suggestions = try SwiftInferCommand.DiscoverInteraction.collectSuggestions(
            targets: ["Alpha", "Beta"],
            pinRaw: "Beta.CounterReducer.reduce",
            workingDirectory: Self.corpusRoot,
            firstSeenAt: Self.fixedDate
        )
        #expect(suggestions.isEmpty == false)
        #expect(suggestions.allSatisfy { $0.reducerLocation.contains("/Beta/") })
        #expect(suggestions.allSatisfy { $0.reducerLocation.contains("/Alpha/") == false })
    }

    // MARK: - ReducerPin.matches module semantics (unit)

    private func candidate(module: String?) -> ReducerCandidate {
        ReducerCandidate(
            location: "Sources/\(module ?? "X")/R.swift:1",
            enclosingTypeName: "CounterReducer",
            functionName: "reduce",
            signatureShape: .stateActionReturnsState,
            stateTypeName: "State",
            actionTypeName: "Action",
            moduleName: module
        )
    }

    @Test("module-qualified pin matches only the same-module candidate when tagged")
    func pinMatchesTaggedModule() throws {
        let pin = try ReducerPin.parse("Beta.CounterReducer.reduce")
        #expect(pin.matches(candidate(module: "Beta")) == true)
        #expect(pin.matches(candidate(module: "Alpha")) == false)
    }

    @Test("module-qualified pin stays a redundant qualifier against an untagged candidate")
    func pinRedundantWhenUntagged() throws {
        // Single-target runs leave candidates untagged (moduleName nil); a
        // module-qualified pin must still match — backward compatibility.
        let pin = try ReducerPin.parse("AnyModule.CounterReducer.reduce")
        #expect(pin.matches(candidate(module: nil)) == true)
    }
}
