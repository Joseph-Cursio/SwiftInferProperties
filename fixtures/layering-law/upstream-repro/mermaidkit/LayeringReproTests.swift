import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// Reproductions: an edge that is on no cycle should point down the layering (its target in a strictly later
/// row / layer than its source). Each case has a control that differs only in the triggering feature.
final class LayeringReproTests: XCTestCase {
    private let measure: DiagramTextMeasurer = { t, s in
        CGSize(width: CGFloat(max(t.count, 1)) * s * 0.6, height: s + 4)
    }

    // MARK: - C4: an edge out of a cycle

    private func c4Rows(_ src: String) throws -> [String: CGFloat] {
        guard case .c4(let diagram)? = MermaidParser.parse(src) else { XCTFail("not C4"); return [:] }
        let layout = DiagramLayoutEngine.layout(diagram, measure: measure)
        var minY: [String: CGFloat] = [:]
        for box in layout.boxes { minY[box.titleLines.joined(separator: " ")] = box.frame.minY }
        return minY
    }

    func testC4EdgeLeavingACyclePointsDown() throws {
        let y = try c4Rows("""
        C4Context
        Person(a, "A")
        Person(b, "B")
        Person(c, "C")
        Rel(a, b, "x")
        Rel(b, a, "y")
        Rel(b, c, "z")
        """)
        print("C4 with cycle: \(y)")
        XCTAssertGreaterThan(y["C"]!, y["B"]!, "b -> c is on no cycle, so C should sit below B")
    }

    func testC4ControlWithoutTheBackEdge() throws {
        let y = try c4Rows("""
        C4Context
        Person(a, "A")
        Person(b, "B")
        Person(c, "C")
        Rel(a, b, "x")
        Rel(b, c, "z")
        """)
        print("C4 control: \(y)")
        XCTAssertGreaterThan(y["B"]!, y["A"]!)
        XCTAssertGreaterThan(y["C"]!, y["B"]!)
    }

    // MARK: - Flowchart: a subgraph whose members sit on both sides of an outside node

    private func flowchartY(_ src: String) throws -> [String: CGFloat] {
        guard case .flowchart(let chart)? = MermaidParser.parse(src) else { XCTFail("not a flowchart"); return [:] }
        let layout = DiagramLayoutEngine.layout(chart, measure: measure)
        return Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.id, $0.frame.minY) })
    }

    func testClusteredFlowchartEdgesPointDown() throws {
        let y = try flowchartY("""
        flowchart TD
          subgraph S
            X
            Y
          end
          X --> A
          A --> Y
        """)
        print("flowchart with subgraph: \(y)")
        XCTAssertGreaterThan(y["A"]!, y["X"]!, "X --> A")
        XCTAssertGreaterThan(y["Y"]!, y["A"]!, "A --> Y")
    }

    func testFlatFlowchartControl() throws {
        let y = try flowchartY("""
        flowchart TD
          X --> A
          A --> Y
        """)
        print("flowchart flat: \(y)")
        XCTAssertGreaterThan(y["A"]!, y["X"]!)
        XCTAssertGreaterThan(y["Y"]!, y["A"]!)
    }

    // MARK: - assignLayers: "self-edges are ignored"

    func testAssignLayersIgnoresSelfEdgesOnTwoNodes() {
        let layers = DiagramLayoutEngine.assignLayers(ids: ["x", "y"], edges: [("x", "y"), ("x", "x")])
        print("assignLayers two nodes with self-edge: \(layers)")
        XCTAssertGreaterThan(layers["y"]!, layers["x"]!, "x -> y")
    }

    func testAssignLayersIgnoresSelfEdgesOnThreeNodes() {
        let layers = DiagramLayoutEngine.assignLayers(
            ids: ["n0", "n1", "n2"], edges: [("n1", "n2"), ("n0", "n1"), ("n0", "n2"), ("n0", "n0")])
        print("assignLayers three nodes with self-edge: \(layers)")
        XCTAssertGreaterThan(layers["n1"]!, layers["n0"]!, "n0 -> n1")
        XCTAssertGreaterThan(layers["n2"]!, layers["n1"]!, "n1 -> n2")
    }

    func testAssignLayersControlWithoutSelfEdge() {
        let layers = DiagramLayoutEngine.assignLayers(
            ids: ["n0", "n1", "n2"], edges: [("n1", "n2"), ("n0", "n1"), ("n0", "n2")])
        print("assignLayers control: \(layers)")
        XCTAssertGreaterThan(layers["n1"]!, layers["n0"]!)
        XCTAssertGreaterThan(layers["n2"]!, layers["n1"]!)
    }
}

extension LayeringReproTests {
    /// Does a self-loop reach assignLayers through the public flowchart layout?
    func testSelfLoopThroughPublicLayout() throws {
        let y = try flowchartY("""
        flowchart TD
          x --> y
          x --> x
          n0 --> n1
          n0 --> n2
          n1 --> n2
          n0 --> n0
        """)
        print("public layout with self-loops: \(y)")
        XCTAssertGreaterThan(y["y"]!, y["x"]!)
        XCTAssertGreaterThan(y["n2"]!, y["n1"]!)
    }
}
