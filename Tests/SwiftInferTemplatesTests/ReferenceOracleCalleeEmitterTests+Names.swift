import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The `@Test` function's name is an identifier whatever the owner is spelled as.
extension ReferenceOracleCalleeEmitterTests {

    /// N. An owner spelled with sugar or generic arguments — `extension [Bead]`, `extension
    /// Array<String>`, `extension Dictionary<String, Int>` — keeps only its identifier characters,
    /// each run of the others becoming one `_`. Replacing `.` alone printed
    /// `@Test func [Bead]_totalWeight_matchesReferenceDefinition()`, which does not parse
    /// (*expected identifier in function declaration*). A dotted owner reads as before.
    @Test func anOwnerSpelledWithSugarOrGenericArgumentsGivesAnIdentifierTestName() {
        let expected = [
            "[Bead]": "Bead_totalWeight_matchesReferenceDefinition",
            "Array<String>": "Array_String_totalWeight_matchesReferenceDefinition",
            "Dictionary<String, Int>": "Dictionary_String_Int_totalWeight_matchesReferenceDefinition",
            "[String: Int?]": "String_Int_totalWeight_matchesReferenceDefinition",
            "NS.Outer": "NS_Outer_totalWeight_matchesReferenceDefinition",
            "Scip_Occurrence": "Scip_Occurrence_totalWeight_matchesReferenceDefinition"
        ]
        for (owner, name) in expected {
            let scaffold = Self.emit(
                .init(
                    callee: CalleeReference(bareName: "totalWeight", argumentLabels: ["plus"], isInstanceMethod: true),
                    owner: owner,
                    parameters: [Self.parameter("plus", "bonus", "Int")],
                    returnTypeText: "Int", isAsync: false, isThrows: false
                ),
                [owner, "Int"]
            )
            #expect(scaffold.contains("@Test func \(name)() async {\n"), "owner \(owner)")
        }
    }
}
