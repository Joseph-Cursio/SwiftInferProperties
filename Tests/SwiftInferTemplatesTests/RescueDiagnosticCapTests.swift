import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The rescue diagnostic's name list is capped.
///
/// It shipped uncapped, and the measurement that exposed it is the reason this suite
/// exists rather than a comment: sizing what the access-level gate suppresses meant
/// seeding **every** `private` function in this repo, and the stderr line came back with
/// **853 names on it**. A diagnostic nobody can read is not a diagnostic, and stderr lands
/// mid-run where a reader cannot scroll past it.
///
/// The failure mode is invisible at fixture scale — every test that existed used two or
/// three restricted functions, so an uncapped join looked identical to a capped one. That
/// is the same lesson the catalog keeps relearning from the other direction: a synthetic
/// probe confirms the code does what you intended, and only real input says whether what
/// you intended was the shape that occurs.
@Suite("Rescue diagnostic — the name list is capped")
struct RescueDiagnosticCapTests {

    private func restricted(_ name: String, file: String = "Source.swift") -> RestrictedFunction {
        RestrictedFunction(
            summary: FunctionSummary(
                name: name,
                parameters: [],
                returnTypeText: "Void",
                isThrows: false,
                isAsync: false,
                isMutating: false,
                isStatic: false,
                location: SourceLocation(file: file, line: 1, column: 1),
                containingTypeName: nil,
                bodySignals: .empty
            ),
            restriction: .notVisibleToTests
        )
    }

    @Test("a short list is printed in full, with no elision")
    func shortListIsPrintedWhole() {
        let names = ["alpha", "beta", "gamma"]
        let rendered = TemplateRegistry.namesForDiagnostic(names.map { restricted($0) })
        #expect(rendered == "alpha, beta, gamma")
        #expect(rendered.contains("more distinct name(s)") == false)
    }

    @Test("a long list is capped and the remainder is counted, not dropped")
    func longListIsCappedAndCounted() {
        // 30 distinct names, cap 12 → 12 shown, 18 accounted for.
        let rendered = TemplateRegistry.namesForDiagnostic(
            (1...30).map { restricted("helper\(String(format: "%02d", $0))") }
        )
        #expect(rendered.hasPrefix("helper01, helper02"))
        #expect(rendered.contains("… and 18 more distinct name(s)"))
        // The whole point: bounded output. 853 names must not be able to reach stderr.
        #expect(rendered.split(separator: ",").count <= 13)
    }

    @Test("duplicate names are collapsed BEFORE the cap is applied")
    func duplicatesDoNotConsumeTheCap() {
        // The join key is `(basename, symbol)`, so one helper repeated across files is one
        // name to a reader. This corpus really does have `parse` nine times and
        // `findPackageRoot` nine times — uncollapsed, they would spend the whole cap on two
        // names and the sample would say nothing.
        let repeated = (1...9).map { restricted("parse", file: "File\($0).swift") }
        let others = ["alpha", "beta", "gamma"].map { restricted($0) }
        let rendered = TemplateRegistry.namesForDiagnostic(repeated + others)
        #expect(rendered == "alpha, beta, gamma, parse")
    }

    @Test("the count in the sentence is of DISTINCT names, not of occurrences")
    func remainderCountsDistinctNames() {
        // 20 distinct, each appearing twice: the reader should be told 8 remain, not 28.
        let doubled = (1...20).flatMap { index -> [RestrictedFunction] in
            let name = "helper\(String(format: "%02d", index))"
            return [restricted(name, file: "A.swift"), restricted(name, file: "B.swift")]
        }
        #expect(
            TemplateRegistry.namesForDiagnostic(doubled).contains("… and 8 more distinct name(s)")
        )
    }
}
