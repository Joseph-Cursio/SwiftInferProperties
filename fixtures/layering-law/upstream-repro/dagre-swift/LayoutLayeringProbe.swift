// SPDX-License-Identifier: MIT
// Probe: does the public layout() ever draw an acyclic edge level with or above its source (rankdir TB)?

import XCTest
@testable import SwiftDagre

final class LayoutLayeringProbe: XCTestCase {
    private func upward(_ nodes: [String], _ edges: [(String, String)]) throws -> [String] {
        let g = DagreGraph(options: GraphOptions(directed: true, multigraph: true, compound: false))
        for v in nodes { g.setNode(v, label: DagreNodeLabel(width: 40, height: 20)) }
        for (v, w) in edges { try g.setEdge(v, w, label: DagreEdgeLabel()) }
        try SwiftDagre.layout(g, options: LayoutOptions())
        return edges.compactMap { v, w in
            let yv = g.node(v)!.y, yw = g.node(w)!.y
            return yw <= yv ? "\(v)->\(w): y \(yv) -> \(yw)" : nil
        }
    }

    func testCounterexamplesThroughLayout() throws {
        let cases: [([String], [(String, String)])] = [
            (["g", "f", "e", "h", "a", "i", "m12"],
             [("e", "m12"), ("i", "h"), ("f", "e"), ("a", "h"), ("h", "g"), ("m12", "g"), ("f", "i"), ("e", "a")]),
            (["c", "e", "h", "b", "a", "f", "d", "i", "g"],
             [("h", "g"), ("e", "f"), ("g", "c"), ("i", "h"), ("i", "e"), ("b", "c"), ("a", "h"), ("d", "b"),
              ("e", "d"), ("f", "c"), ("a", "e")]),
        ]
        for (nodes, edges) in cases { print("layout probe: \(try upward(nodes, edges))") }
    }

    func testRandomDAGsThroughLayout() throws {
        var state: UInt64 = 0x667_1A70_07
        func below(_ n: Int) -> Int { Int(state.next() % UInt64(n)) }
        let names = (0..<26).map { String(UnicodeScalar(UInt8(97 + $0))) }
        var bad = 0
        var first: String?
        let trials = 3_000
        for _ in 0..<trials {
            let count = 4 + below(9)
            let order = Array(names.shuffled(using: &state).prefix(count))
            var edges: [(String, String)] = []
            for i in 0..<count { for j in (i + 1)..<count where below(10) < 3 { edges.append((order[i], order[j])) } }
            if edges.isEmpty { continue }
            edges.shuffle(using: &state)
            let up = try upward(order.shuffled(using: &state), edges)
            if !up.isEmpty { bad += 1; if first == nil { first = "\(edges) => \(up)" } }
        }
        print("layout probe random: \(bad) of \(trials) with an upward or level edge; first: \(first ?? "none")")
    }
}
