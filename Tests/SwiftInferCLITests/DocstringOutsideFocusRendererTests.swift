import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `DocstringAdvisoryRenderer.renderOutsideFocus(_:)` — the compact block `discover --seeds` lists
/// documented contracts the manifest does not name in.
///
/// Two lines a function, no scaffold, and none of the full block's per-arm claims: those describe
/// suggestions the reader of this block is not shown, and the fallback arm's "only a determinism
/// tautology" is false for a function the manifest does not name — no determinism law is
/// synthesized for it.
@Suite("DocstringAdvisoryRenderer — documented contracts outside the seed focus")
struct DocstringOutsideFocusRendererTests {

    @Test("no items renders nothing, so the caller can append unconditionally")
    func emptyRendersNothing() {
        #expect(DocstringAdvisoryRenderer.renderOutsideFocus([]).isEmpty)
    }

    @Test("one item is a singular header, the explanation, and two lines for the item")
    func oneItemIsFourLines() {
        let rendered = DocstringAdvisoryRenderer.renderOutsideFocus([
            Self.item(name: "clip(_:_:)", doc: "The longest prefix that fits; never longer than limit.")
        ])
        let lines = rendered.components(separatedBy: "\n")

        #expect(lines.count == 4)
        #expect(lines.first == "Documented contracts outside the seed focus (1 function):")
        #expect(lines[2] == "  • clip(_:_:)  (String, Int) -> (text: String, cut: Bool)  —  Source.swift:7")
        #expect(lines[3] == "      \"The longest prefix that fits; never longer than limit.\"")
    }

    @Test("several items share one header, with no blank line between them")
    func severalItemsArePlural() {
        let rendered = DocstringAdvisoryRenderer.renderOutsideFocus([
            Self.item(name: "clip(_:_:)", doc: "Never longer than limit."),
            Self.item(name: "stoppedEarly(_:limit:)", doc: "Keeps at most limit elements.")
        ])
        let lines = rendered.components(separatedBy: "\n")

        #expect(lines.count == 6)
        #expect(lines.first == "Documented contracts outside the seed focus (2 functions):")
        #expect(lines.contains("") == false)
    }

    /// The compact block must stand alone (the full block above it can be empty) and must make
    /// none of the full block's claims.
    @Test("the compact block makes none of the full block's claims")
    func makesNoneOfTheFullBlocksClaims() {
        let rendered = DocstringAdvisoryRenderer.renderOutsideFocus([
            Self.item(name: "clip(_:_:)", doc: "Never longer than limit.")
        ])

        #expect(rendered.contains("Reference definitions from docstrings") == false)
        #expect(rendered.contains("determinism tautology") == false)
        #expect(rendered.contains("encode THAT") == false)
        #expect(rendered.contains("runnable reference oracle") == false)
        #expect(rendered.contains("run discover without --seeds"))
    }

    private static func item(name: String, doc: String) -> SwiftInferCommand.Discover.DocstringAdviceItem {
        SwiftInferCommand.Discover.DocstringAdviceItem(
            displayName: name,
            signature: "(String, Int) -> (text: String, cut: Bool)",
            location: SourceLocation(file: "Source.swift", line: 7, column: 5),
            advisory: .fallbackContract(.init(docComment: doc, redHerrings: [])),
            // A scaffold the compact form must not print even when one is supplied.
            runnableScaffold: "func clip_reference() {}"
        )
    }
}
