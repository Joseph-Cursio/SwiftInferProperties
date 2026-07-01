import Foundation
import Testing

@testable import SwiftInferCLI

// V1.149 — `mergedImports` renders a `@testable `-prefixed extra entry as a
// `@testable import`, so a verify stub can reach a user module's `internal`
// symbols. Plain entries stay plain `import`.
@Suite("SeededStubEmitter.mergedImports — V1.149 @testable rendering")
struct MergedImportsTestableTests {

    @Test("a @testable-prefixed extra renders as `@testable import`")
    func testablePrefixRenders() {
        let block = IdempotenceStubEmitter.mergedImports(
            base: ["Foundation", "PropertyBased"],
            extra: ["@testable MyModule"]
        )
        let lines = block.split(separator: "\n").map(String.init)
        #expect(lines.contains("@testable import MyModule"))
        // The module must NOT also appear as a plain `import MyModule` line.
        #expect(lines.contains("import MyModule") == false)
    }

    @Test("plain extras stay plain `import` (no behavior change)")
    func plainEntriesUnchanged() {
        let block = IdempotenceStubEmitter.mergedImports(
            base: ["Foundation"],
            extra: ["MyModule"]
        )
        let lines = block.split(separator: "\n").map(String.init)
        #expect(lines.contains("import MyModule"))
        #expect(block.contains("@testable") == false)
    }
}
