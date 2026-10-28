// SPDX-License-Identifier: MIT
// Reproduction: an undirected Graph.setEdge(v, w) with v > w stores the normalized edge id under the
// un-normalized endpoints, so the edge is invisible to neighbors() and NetworkSimplex can return an
// infeasible ranking (rank(w) - rank(v) < minlen on an acyclic edge).

import XCTest
@testable import SwiftDagre

final class NetworkSimplexFeasibilityTests: XCTestCase {

    // MARK: - The root cause, on Graph alone

    func testUndirectedSetEdgeIsVisibleFromBothEndpoints() throws {
        let t = Graph<Int, Int>(options: GraphOptions(directed: false, multigraph: false, compound: false))
        try t.setEdge("b", "a", label: 0)
        XCTAssertEqual(Set(t.neighbors("a") ?? []), ["b"], "neighbors(a)")
        XCTAssertEqual(Set(t.neighbors("b") ?? []), ["a"], "neighbors(b)")
    }

    func testUndirectedRemoveEdgeClearsAdjacency() throws {
        let t = Graph<Int, Int>(options: GraphOptions(directed: false, multigraph: false, compound: false))
        try t.setEdge("b", "a", label: 0)
        t.removeEdge("b", "a")
        XCTAssertEqual(t.neighbors("a") ?? [], [], "neighbors(a) after removal")
        XCTAssertEqual(t.neighbors("b") ?? [], [], "neighbors(b) after removal")
    }

    // MARK: - NetworkSimplex feasibility

    private typealias Spec = (nodes: [String], edges: [(String, String, Int, Int)])

    private func build(_ spec: Spec, multigraph: Bool) throws -> DagreGraph {
        let g = DagreGraph(options: GraphOptions(directed: true, multigraph: multigraph, compound: false))
        for v in spec.nodes { g.setNode(v, label: DagreNodeLabel()) }
        for (v, w, minlen, weight) in spec.edges {
            try g.setEdge(v, w, label: DagreEdgeLabel(minlen: minlen, weight: weight))
        }
        return g
    }

    /// Every edge v -> w whose rank(w) - rank(v) is below its minlen.
    private func violations(_ g: DagreGraph) -> [String] {
        g.edges().compactMap { e in
            guard let rv = g.node(e.v)?.rank, let rw = g.node(e.w)?.rank, let minlen = g.edge(e.id)?.minlen else {
                return "\(e.v)->\(e.w): unranked"
            }
            return rw - rv < minlen ? "\(e.v)->\(e.w): rank \(rv) -> \(rw), minlen \(minlen)" : nil
        }
    }

    private func ranks(_ g: DagreGraph) -> String {
        g.nodes().map { "\($0)=\((g.node($0)?.rank).map(String.init) ?? "nil")" }.joined(separator: " ")
    }

    private func assertFeasible(_ spec: Spec, _ name: String) throws {
        for multigraph in [false, true] {
            let g = try build(spec, multigraph: multigraph)
            try NetworkSimplex.run(g)
            let broken = violations(g)
            print("\(name) multigraph=\(multigraph): \(ranks(g)) violations=\(broken)")
            XCTAssertEqual(broken, [], "\(name), multigraph \(multigraph)")
        }
    }

    func testCounterexampleSevenNodes() throws {
        try assertFeasible((
            ["g", "f", "e", "h", "a", "i", "m12"],
            [("e", "m12", 1, 1), ("i", "h", 1, 1), ("f", "e", 1, 1), ("a", "h", 1, 1), ("h", "g", 1, 1),
             ("m12", "g", 1, 1), ("f", "i", 1, 2), ("e", "a", 1, 1)]), "seven nodes")
    }

    func testCounterexampleNineNodesEqualRank() throws {
        try assertFeasible((
            ["c", "e", "h", "b", "a", "f", "d", "i", "g"],
            [("h", "g", 1, 1), ("e", "f", 1, 1), ("g", "c", 1, 1), ("i", "h", 1, 1), ("i", "e", 1, 1),
             ("b", "c", 1, 1), ("a", "h", 1, 1), ("d", "b", 1, 1), ("e", "d", 1, 1), ("f", "c", 1, 1),
             ("a", "e", 1, 1)]), "nine nodes, equal rank")
    }

    func testCounterexampleNineNodesReversedRank() throws {
        try assertFeasible((
            ["ar", "bl", "fh", "fk", "oy", "rh", "tr", "xr", "fz"],
            [("fk", "xr", 3, 1), ("fk", "fz", 1, 1), ("fh", "rh", 1, 5), ("bl", "fh", 1, 1), ("oy", "tr", 2, 1),
             ("ar", "bl", 1, 1), ("fh", "oy", 3, 1), ("rh", "fz", 1, 1), ("bl", "fk", 3, 1), ("rh", "xr", 1, 1)]),
            "nine nodes, reversed rank")
    }

    /// Random DAGs: nodes named by a seeded shuffle, an edge i -> j (i < j in a random topological order) with
    /// probability 0.3, inserted in random order, minlen 1. Counts the graphs NetworkSimplex leaves infeasible.
    func testRandomDAGsStayFeasible() throws {
        var state: UInt64 = 0x667_0000_D46E
        func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
        let names = (0..<26).map { String(UnicodeScalar(UInt8(97 + $0))) }
        var broken = 0
        var first: String?
        let trials = 20_000
        for _ in 0..<trials {
            let count = 3 + below(8)
            let order = names.shuffled(using: &state).prefix(count).map { $0 }
            var edges: [(String, String, Int, Int)] = []
            for i in 0..<count { for j in (i + 1)..<count where below(10) < 3 { edges.append((order[i], order[j], 1, 1 + below(2))) } }
            if edges.isEmpty { continue }
            edges.shuffle(using: &state)
            let g = try build((order.shuffled(using: &state), edges), multigraph: false)
            try NetworkSimplex.run(g)
            let bad = violations(g)
            if !bad.isEmpty {
                broken += 1
                if first == nil { first = "\(edges.map { "\($0.0)->\($0.1)" }) => \(ranks(g)) \(bad)" }
            }
        }
        print("random DAGs: \(broken) of \(trials) infeasible; first: \(first ?? "none")")
        XCTAssertEqual(broken, 0)
    }
}

extension UInt64: @retroactive RandomNumberGenerator {
    public mutating func next() -> UInt64 {
        self &+= 0x9E37_79B9_7F4A_7C15
        var z = self
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
