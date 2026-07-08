import Foundation
@testable import SwiftInferCLI
import Testing

/// V1.146 — best-effort stdlib-type-usage scan for `known-properties --target`.
@Suite("StdlibTypeUsage — V1.146 target scoping")
struct StdlibTypeUsageTests {

    private static let candidates: Set<String> = ["Int", "Double", "Bool", "String", "Array", "Set"]

    private func used(_ source: String) -> Set<String> {
        StdlibTypeUsage.typesUsed(in: [source], among: Self.candidates)
    }

    @Test("V1.146 — detects word-token types and array syntax; excludes unused")
    func detectsUsedTypes() {
        let source = """
        struct Tags {
            var seen: Set<String> = []
            func total(_ counts: [Int]) -> Int { counts.reduce(0, +) }
        }
        """
        let found = used(source)
        #expect(found.contains("Set"))
        #expect(found.contains("String"))
        #expect(found.contains("Int"))
        #expect(found.contains("Array"))   // [Int] is array-type syntax
        #expect(!found.contains("Double"))
        #expect(!found.contains("Bool"))
    }

    @Test("V1.146 — Array matches [T] literal/type, not dictionaries or subscripts")
    func arrayHeuristic() {
        #expect(used("let xs: [Int] = []").contains("Array"))       // [Type] annotation
        #expect(used("let xs = [1, 2, 3]").contains("Array"))       // comma literal
        // A dictionary type/literal must NOT read as Array (colon present).
        #expect(!used("let d: [String: Int] = [:]").contains("Array"))
        // A bare subscript must NOT read as Array.
        #expect(!used("let first = queue[0]").contains("Array"))
    }

    @Test("V1.146 — word boundaries avoid false positives inside identifiers")
    func noSubstringFalsePositives() {
        // 'Int' inside 'Point', 'Set' inside 'Settings' must not match.
        let found = used("struct Point { var settingsSetup = 0 }")
        #expect(!found.contains("Int"))
        #expect(!found.contains("Set"))
    }

    @Test("V1.146 — Bool and Double detected when actually present")
    func detectsBoolDouble() {
        let found = used("let flag: Bool = true; let ratio: Double = 1.5")
        #expect(found.contains("Bool"))
        #expect(found.contains("Double"))
    }
}
