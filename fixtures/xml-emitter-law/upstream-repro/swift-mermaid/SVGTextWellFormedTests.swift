// Drop into Tests/MermaidTests/ and run `swift test --filter SVGTextWellFormedTests`.
// On `main`, every test but the control fails: XMLParser rejects the SVG.
import Foundation
import XCTest
@testable import Mermaid

final class SVGTextWellFormedTests: XCTestCase {

    private func assertWellFormedSVG(_ source: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let svg = try Mermaid.render(source).svgString()
        XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse(), "SVG is not well-formed XML", file: file, line: line)
    }

    func testControlCharacterInFlowchartLabel() throws {
        try assertWellFormedSVG("flowchart LR\n  A[a\u{1}b] --> B[ok]")
    }

    /// A terminal colour code pasted into a label: ESC (U+001B).
    func testEscapeCharacterInFlowchartLabel() throws {
        try assertWellFormedSVG("flowchart LR\n  A[a \u{1B}[1mb\u{1B}[0m] --> B[ok]")
    }

    func testNoncharacterInFlowchartLabel() throws {
        try assertWellFormedSVG("flowchart LR\n  A[a\u{FFFE}b] --> B[ok]")
    }

    func testBellInSequenceMessage() throws {
        try assertWellFormedSVG("sequenceDiagram\n  Alice->>Bob: hi\u{7}there")
    }

    /// `<` followed by U+0301 COMBINING ACUTE ACCENT is one Character, and it is not "<", so `escapeText`
    /// writes the `<` raw. The same holds for `&`.
    func testLessThanFollowedByCombiningMark() throws {
        try assertWellFormedSVG("flowchart LR\n  A[a <\u{301} b] --> B[ok]")
    }

    func testAmpersandFollowedByCombiningMark() throws {
        try assertWellFormedSVG("flowchart LR\n  A[a &\u{301} b] --> B[ok]")
    }

    /// Every character XML 1.0 forbids.
    func testEscapeTextWritesNoCharacterXMLForbids() {
        let forbidden = (0x01...0x1F).filter { ![0x09, 0x0A, 0x0D].contains($0) } + [0xFFFE, 0xFFFF]
        for value in forbidden {
            let escaped = escapeText("a" + String(Unicode.Scalar(UInt32(value))!) + "b")
            let document = "<text>\(escaped)</text>"
            XCTAssertTrue(XMLParser(data: Data(document.utf8)).parse(), "U+\(String(value, radix: 16, uppercase: true))")
        }
    }

    /// Control: what `escapeText` handles today.
    func testPredefinedEntitiesInLabel() throws {
        try assertWellFormedSVG("flowchart LR\n  A[a & b < c] --> B[ok]")
    }
}
