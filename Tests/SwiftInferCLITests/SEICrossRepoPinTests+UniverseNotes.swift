import Foundation
import Testing

/// The construction-universe clauses' half of `guardIsCapableOfChecking`: this package's copies
/// must exist, and a sibling that carries none of one is SAID — the `.enabled(if:)` skip on each
/// comparison announces itself, and this says why.
extension SEICrossRepoPinTests {

    static func noteUniverseClauses(linterRoot: URL) {
        let ownTableExists = FileManager.default.fileExists(atPath: Self.ownUniverseTable.path)
        #expect(ownTableExists, "docs/construction-universe.tsv is missing")
        if Self.linterUniverseTable == nil {
            print(
                """
                NOTE — cross-repo construction-universe comparison SKIPPED: SwiftProjectLint at \
                \(linterRoot.path) carries no \(Self.linterUniverseTablePath). Equal SEI pins over \
                unequal universes are one oracle configured two ways, and this run did not check.
                """
            )
        }
        let ownCasesExist = FileManager.default.fileExists(atPath: Self.ownUniverseCases.path)
        #expect(ownCasesExist, "docs/construction-universe-cases.json is missing")
        if Self.linterUniverseCases == nil {
            print(
                """
                NOTE — cross-repo construction-universe CASES comparison SKIPPED: SwiftProjectLint \
                at \(linterRoot.path) carries no \(Self.linterUniverseCasesPath). The two manifest \
                readers and build orders were not compared on this run.
                """
            )
        }
        let ownClosureExists = FileManager.default.fileExists(atPath: Self.ownNestedPackages.path)
        #expect(ownClosureExists, "Sources/SwiftInferCore/ConstructionUniverse+NestedPackages.swift is missing")
        if Self.linterNestedPackages == nil {
            print(
                """
                NOTE — cross-repo nested-package CLOSURE comparison SKIPPED: SwiftProjectLint at \
                \(linterRoot.path) carries no \(Self.linterNestedPackagesPath). The two closures that \
                bound one root's nested packages were not compared on this run.
                """
            )
        }
    }
}
