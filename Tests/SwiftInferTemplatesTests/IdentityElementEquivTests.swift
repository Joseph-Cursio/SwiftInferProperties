import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("IdentityElementTemplate non-lifted — V1.40.F wrapper-pattern equivalence")
struct IdentityElementEquivTests {

    private static let loc = SourceLocation(file: "T.swift", line: 1, column: 1)

    @Test("V1.40.F — IdentityElement non-lifted: wrapper preserves no-space identity-evidence rendering")
    func wrapperPreservesNoSpaceRendering() throws {
        let pair = makeIdentityElementPair(
            opName: "+",
            paramTypes: ("Int", "Int"),
            returnType: "Int",
            identityName: "zero",
            identityType: "Int"
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(for: pair))
        // Identity-evidence row should be `"zero: Int — Test.swift:5"` (no space
        // between "zero" and ":"). The runner's canonical assembly would emit
        // `"zero : Int — Test.swift:5"` (with space), which the wrapper bypasses.
        let identityLine = suggestion.explainability.whySuggested.first { $0.contains("zero") }
        #expect(identityLine != nil)
        #expect(!(identityLine?.contains("zero :") ?? true), "wrapper should preserve no-space rendering")
        #expect(identityLine?.contains("zero:") == true)
    }
}
