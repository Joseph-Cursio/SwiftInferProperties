// Drop into Tests/GraffleTests/ and add to Package.swift:
//     .testTarget(name: "GraffleTests", dependencies: ["Graffle"], path: "Tests/GraffleTests")
// Each test exports a drawing with SVGExport (what File > Export > SVG writes, via CanvasView.svgData) and asks
// Foundation's XMLParser whether the document is well-formed, then reads it back with the app's own SVGImport.
import AppKit
import XCTest
@testable import Graffle

final class SVGExportWellFormedTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)

    private func export(_ drawing: Drawing) -> String {
        SVGExport.svg(for: drawing, bounds: bounds)
    }

    /// The first error libxml2 reports, or nil when the document is well-formed.
    private func firstParseError(_ svg: String) -> String? {
        final class Delegate: NSObject, XMLParserDelegate {
            var first: String?
            func parser(_ parser: XMLParser, parseErrorOccurred error: Error) {
                guard first == nil else { return }
                let ns = error as NSError
                let message = (ns.userInfo["NSXMLParserErrorMessage"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                first = "code \(ns.code) at \(parser.lineNumber):\(parser.columnNumber): \(message)"
            }
        }
        let parser = XMLParser(data: Data(svg.utf8))
        let delegate = Delegate()
        parser.delegate = delegate
        return parser.parse() ? nil : (delegate.first ?? "\(String(describing: parser.parserError))")
    }

    private func assertWellFormed(_ drawing: Drawing, file: StaticString = #filePath, line: UInt = #line) {
        let svg = export(drawing)
        XCTAssertNil(firstParseError(svg), "export is not well-formed", file: file, line: line)
        XCTAssertNoThrow(try SVGImport.parse(Data(svg.utf8), name: "export.svg"),
                         "the app cannot import its own export", file: file, line: line)
    }

    /// A control character pasted into a layer's name reaches `data-name="…"` raw.
    func testControlCharacterInLayerName() {
        var drawing = Drawing()
        drawing.layers[0].name = "Layer\u{1}1"
        assertWellFormed(drawing)
    }

    /// A control character in a shape's text reaches a `<tspan>` raw.
    func testControlCharacterInShapeText() {
        var drawing = Drawing()
        drawing.shapes = [Shape(layer: drawing.layers[0].id, kind: .rectangle,
                                frame: CGRect(x: 20, y: 20, width: 200, height: 60), text: "x\u{1B}[0my")]
        assertWellFormed(drawing)
    }

    /// A control character in a connector's label reaches the label's text raw.
    func testControlCharacterInConnectorLabel() {
        var drawing = Drawing()
        let layer = drawing.layers[0].id
        let a = Shape(layer: layer, kind: .rectangle, frame: CGRect(x: 20, y: 20, width: 80, height: 40))
        let b = Shape(layer: layer, kind: .rectangle, frame: CGRect(x: 220, y: 20, width: 80, height: 40))
        var link = Connector(layer: layer, from: a.id, to: b.id)
        link.text = "go\u{1}now"
        drawing.shapes = [a, b]
        drawing.connectors = [link]
        assertWellFormed(drawing)
    }

    /// `replacingOccurrences(of: "<", with: "&lt;")` compares by character, so it does not match a '<' that
    /// begins a longer character, such as '<' followed by U+0301 COMBINING ACUTE ACCENT. That '<' is written raw.
    func testLessThanFollowedByCombiningMarkInLayerName() {
        var drawing = Drawing()
        drawing.layers[0].name = "a <\u{301} b"
        assertWellFormed(drawing)
    }

    /// Control: the characters `escape` handles today.
    func testPredefinedEntitiesInLayerNameAndText() {
        var drawing = Drawing()
        drawing.layers[0].name = "Tom & \"Jerry\" <3>"
        drawing.shapes = [Shape(layer: drawing.layers[0].id, kind: .rectangle,
                                frame: CGRect(x: 20, y: 20, width: 200, height: 60), text: "a < b & c")]
        assertWellFormed(drawing)
    }
}
