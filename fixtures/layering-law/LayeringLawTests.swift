// #667's layering law, prototyped by hand for SwiftInferProperties' kill arm
// (`docs/plans/layering-law-census-scope.md` §5.2). It is copied into an export of SwiftUMLStudio's
// `SwiftUMLBridgeFrameworkTests` target by `scripts/layering_kill_arm.py`, never into SwiftUMLStudio itself.
//
// The law: for every edge `u → v` the layering covers, with `v` unable to reach `u`, `layer(v) > layer(u)`.
// Reachability is computed here, over the input edges, by a search of the test's own. A covered edge whose
// endpoint has no row (L1) or no positioned node or component (L2, L3) counts as a failure.
import Testing
@testable import SwiftUMLBridgeFramework

@Suite("#667 layering law (hand prototype)")
struct LayeringLawTests {
    static let trials = 1_000
    static let activitySeed: UInt64 = 667_001
    static let componentSeed: UInt64 = 667_003

    /// SplitMix64, so every run draws the same graphs on one toolchain.
    struct SplitMix64: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
    }

    // MARK: - Generators (§5.2)

    /// 1–9 nodes with distinct ids from `0..<64`, exactly one `.start`, and a tree of edges from the
    /// start so it reaches every node; then 0–n more edges between any two drawn ids. Both lists shuffled.
    static func activityGraph(_ rng: inout SplitMix64) -> ActivityGraph {
        let count = Int.random(in: 1...9, using: &rng)
        let ids = Array(Array(0..<64).shuffled(using: &rng).prefix(count))
        let otherKinds: [ActivityNodeKind] = [.end, .action, .decision, .merge, .fork, .join, .loopStart, .loopEnd]
        var nodes = [ActivityNode(id: ids[0], kind: .start, label: "")]
        for identifier in ids.dropFirst() {
            let kind = otherKinds[Int.random(in: 0..<otherKinds.count, using: &rng)]
            nodes.append(ActivityNode(id: identifier, kind: kind, label: "n\(identifier)"))
        }
        var edges: [ActivityEdge] = []
        for index in ids.indices.dropFirst() {
            edges.append(ActivityEdge(fromId: ids[Int.random(in: 0..<index, using: &rng)], toId: ids[index]))
        }
        for _ in 0..<Int.random(in: 0...count, using: &rng) {
            let from = ids[Int.random(in: 0..<count, using: &rng)]
            let to = ids[Int.random(in: 0..<count, using: &rng)]
            edges.append(ActivityEdge(fromId: from, toId: to))
        }
        return ActivityGraph(nodes: nodes.shuffled(using: &rng), edges: edges.shuffled(using: &rng))
    }

    /// 1–8 components with distinct names, a random kind and 0–3 provided interfaces of random length;
    /// then 0–2n dependencies between drawn names, cycles and self-loops allowed, shuffled.
    static func componentModel(_ rng: inout SplitMix64) -> ComponentModel {
        let count = Int.random(in: 1...8, using: &rng)
        let kinds: [ComponentKind] = [.executable, .library, .test, .other]
        let names = (0..<count).map { "Target\($0)" }.shuffled(using: &rng)
        let components = names.map { name in
            let interfaces = (0..<Int.random(in: 0...3, using: &rng)).map { _ in
                String(repeating: "x", count: Int.random(in: 1...40, using: &rng))
            }
            return Component(
                name: name, kind: kinds[Int.random(in: 0..<kinds.count, using: &rng)], providedInterfaces: interfaces)
        }
        let dependencies = (0..<Int.random(in: 0...(2 * count), using: &rng)).map { _ in
            ComponentDependency(
                from: names[Int.random(in: 0..<count, using: &rng)], to: names[Int.random(in: 0..<count, using: &rng)])
        }
        return ComponentModel(components: components, dependencies: dependencies.shuffled(using: &rng))
    }

    // MARK: - Reachability, the test's own

    static func reachable<Node: Hashable>(from source: Node, along edges: [(Node, Node)]) -> Set<Node> {
        var successors: [Node: [Node]] = [:]
        for (from, to) in edges { successors[from, default: []].append(to) }
        var seen: Set<Node> = [source]
        var frontier = [source]
        while let node = frontier.popLast() {
            for next in successors[node] ?? [] where seen.insert(next).inserted { frontier.append(next) }
        }
        return seen
    }

    /// The edges the law covers: `u` reachable from `root` (every node when `root` is nil), `v` unable to reach `u`.
    static func coveredEdges<Node: Hashable>(_ edges: [(Node, Node)], root: Node?) -> [(Node, Node)] {
        let fromRoot = root.map { reachable(from: $0, along: edges) }
        return edges.filter { from, to in
            (fromRoot?.contains(from) ?? true) && !reachable(from: to, along: edges).contains(from)
        }
    }

    /// Checks `layer(v) > layer(u)` on every covered edge, records the first failure, and prints a summary
    /// line the kill arm compares across runs (RC6).
    static func check<Node: Hashable>(
        _ property: String, trials: Int, draw: (inout SplitMix64) -> (edges: [(Node, Node)], root: Node?, layer: [Node: Double]),
        seed: UInt64
    ) {
        var rng = SplitMix64(state: seed)
        var checked = 0
        var failures = 0
        var firstFailure: String?
        for trial in 0..<trials {
            let drawn = draw(&rng)
            for (from, to) in coveredEdges(drawn.edges, root: drawn.root) {
                checked += 1
                guard let fromLayer = drawn.layer[from], let toLayer = drawn.layer[to], toLayer > fromLayer else {
                    failures += 1
                    if firstFailure == nil {
                        firstFailure = "trial \(trial): \(from) → \(to) has layers \(String(describing: drawn.layer[from])) → "
                            + "\(String(describing: drawn.layer[to])); edges \(drawn.edges)"
                    }
                    continue
                }
            }
        }
        print("LAYERING-LAW \(property) trials=\(trials) edges=\(checked) failures=\(failures)")
        if let firstFailure {
            Issue.record("\(property): \(failures) covered edges do not descend; first: \(firstFailure)")
        }
    }

    // MARK: - The three properties

    @Test("L1: computeRows puts v below u on every covered edge")
    func rowsDescend() {
        Self.check("L1", trials: Self.trials, draw: { rng in
            let graph = Self.activityGraph(&rng)
            let rows = ActivitySVGRenderer.computeRows(graph: graph)
            return (graph.edges.map { ($0.fromId, $0.toId) }, graph.startNode?.id, rows.mapValues(Double.init))
        }, seed: Self.activitySeed)
    }

    @Test("L2: computeLayout's centerY descends on every covered edge")
    func activityCentersDescend() {
        Self.check("L2", trials: Self.trials, draw: { rng in
            let graph = Self.activityGraph(&rng)
            let layout = ActivitySVGRenderer.computeLayout(from: graph)
            let centers = Dictionary(layout.nodes.map { ($0.id, $0.centerY) }, uniquingKeysWith: { first, _ in first })
            return (graph.edges.map { ($0.fromId, $0.toId) }, graph.startNode?.id, centers)
        }, seed: Self.activitySeed)
    }

    @Test("L3: a component sits above every component it depends on, off cycles")
    func componentCentersDescend() {
        Self.check("L3", trials: Self.trials, draw: { rng in
            let model = Self.componentModel(&rng)
            let layout = ComponentSVGRenderer.computeLayout(model)
            let centers = Dictionary(layout.components.map { ($0.name, $0.centerY) }, uniquingKeysWith: { first, _ in first })
            return (model.dependencies.map { ($0.from, $0.to) }, nil, centers)
        }, seed: Self.componentSeed)
    }
}
