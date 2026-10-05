import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `DocstringAdvisoryRenderer.render(_:)` — the full block's per-item tail.
///
/// An item carries a scaffold, a decline, or neither. A decline takes the scaffold's place as one
/// line, so a reader who used to be handed code that could not compile is told why instead; the
/// other two render exactly as they did.
@Suite("DocstringAdvisoryRenderer — a scaffold, a decline line, or neither")
struct DocstringAdvisoryRendererTests {

    private static let marker = "    ── runnable reference oracle (fill the stub, then run it) ──"
    private static let doc = "Delay is capped at the ceiling and never negative."

    private static func item(
        scaffold: String? = nil,
        decline: String? = nil
    ) -> SwiftInferCommand.Discover.DocstringAdviceItem {
        var item = SwiftInferCommand.Discover.DocstringAdviceItem(
            displayName: "backoffDelay(_:_:)",
            signature: "(Int, Int) -> Int",
            location: SourceLocation(file: "Source.swift", line: 7, column: 5),
            advisory: .fallbackContract(.init(docComment: doc, redHerrings: [])),
            runnableScaffold: scaffold
        )
        item.oracleDecline = decline
        return item
    }

    /// The header, the bullet, the location and the fallback arm's three lines, shared by all.
    private static let entryLines = [
        "Reference definitions from docstrings (1 function):",
        "  A property is the code checked against a definition you state in one sentence. Where you already "
            + "wrote that sentence, here it is next to the law it defines.",
        "",
        "  • backoffDelay(_:_:)  (Int, Int) -> Int",
        "    Source.swift:7",
        "    the templates could offer only a determinism tautology here (f(x) == f(x), which no wrong code "
            + "fails). Your docstring is the one refutable contract on this function:",
        "      \"\(doc)\"",
        "    encode THAT sentence; it is the law the templates could not name."
    ]

    @Test func aDeclinedItemRendersOneLineInPlaceOfTheScaffold() {
        let rendered = DocstringAdvisoryRenderer.render([
            Self.item(decline: "Apply.twice(_:to:) takes a function-typed parameter")
        ])
        #expect(rendered.components(separatedBy: "\n") == Self.entryLines + [
            "    ── no runnable reference oracle: Apply.twice(_:to:) takes a function-typed parameter"
        ])
        #expect(rendered.contains(Self.marker) == false)
    }

    @Test func aScaffoldItemRendersItsMarkerAndLinesAsBefore() {
        let rendered = DocstringAdvisoryRenderer.render([
            Self.item(scaffold: "func backoffDelay_reference() {\n\n}")
        ])
        #expect(rendered.components(separatedBy: "\n") == Self.entryLines + [
            Self.marker, "    func backoffDelay_reference() {", "    ", "    }"
        ])
        #expect(rendered.contains("no runnable reference oracle") == false)
    }

    @Test func anItemWithNeitherRendersNoTail() {
        #expect(DocstringAdvisoryRenderer.render([Self.item()]).components(separatedBy: "\n") == Self.entryLines)
    }
}
