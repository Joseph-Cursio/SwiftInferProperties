// Drop into Tests/MermaidRenderTests/ and run `swift test --filter SVGLabelWellFormedTests`.
// On `main`, every test but the control fails: XMLParser rejects the SVG.
#if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
import XCTest
import MermaidLayout
@testable import MermaidRender

final class SVGLabelWellFormedTests: XCTestCase {

    private let theme = DiagramTheme(prefersDark: false)

    private func assertWellFormedSVG(_ source: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let svg = try XCTUnwrap(MermaidRenderer.svg(source: source, theme: theme), file: file, line: line)
        #if canImport(Darwin)
        XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse(), "SVG must be XML-parseable", file: file, line: line)
        #endif
    }

    /// ASCII-only source: `&#769;` decodes to U+0301 COMBINING ACUTE ACCENT, which joins the `<` before it into
    /// one Character. `escape` switches on Characters, so that `<` is written raw.
    func testLessThanFollowedByCombiningMarkReference() throws {
        try assertWellFormedSVG("flowchart LR\n  A[\"a <&#769; b\"] --> B[ok]")
    }

    func testAmpersandFollowedByCombiningMarkReference() throws {
        try assertWellFormedSVG("flowchart LR\n  A[\"a &amp;&#769; b\"] --> B[ok]")
    }

    /// A terminal colour code pasted into a quoted label: ESC (U+001B) reaches `<text>` raw.
    func testEscapeCharacterInFlowchartLabel() throws {
        try assertWellFormedSVG("flowchart LR\n  A[\"a \u{1B}[1mb\u{1B}[0m\"] --> B[ok]")
    }

    func testControlCharacterInSequenceMessage() throws {
        try assertWellFormedSVG("sequenceDiagram\n  Alice->>Bob: hi\u{1}there")
    }

    /// Every character XML 1.0 forbids, straight into the renderer.
    func testEscapeWritesNoCharacterXMLForbids() {
        let forbidden = (0x01...0x1F).filter { ![0x09, 0x0A, 0x0D].contains($0) } + [0xFFFE, 0xFFFF]
        for value in forbidden {
            let text = "a" + String(Unicode.Scalar(UInt32(value))!) + "b"
            let svg = SVGRenderer.svg(RenderScene(
                size: CGSize(width: 10, height: 10), background: DiagramColor(red: 1, green: 1, blue: 1),
                elements: [.text(.init(string: text, center: .zero, fontSize: 12,
                                       color: DiagramColor(red: 0, green: 0, blue: 0)))]))
            #if canImport(Darwin)
            XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse(), "U+\(String(value, radix: 16, uppercase: true))")
            #endif
        }
    }

    /// Control: what `escape` handles today.
    func testPredefinedEntitiesInLabel() throws {
        try assertWellFormedSVG("flowchart LR\n  A[\"a < b & 'c' > d\"] --> B[ok]")
    }
}
#endif
