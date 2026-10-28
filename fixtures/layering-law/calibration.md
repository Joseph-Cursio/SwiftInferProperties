# Calibration packet (`docs/plans/layering-law-census-scope.md` §4.2)

Classify these eight functions before any census packet. Items 1–4 are copied verbatim from SwiftUMLStudio's
`SwiftUMLBridge` (`Sources/SwiftUMLBridgeFramework/`); items 5–8 are synthetic.

## calibration/1

- repository: `SwiftUMLStudio` at `c6c82e3`
- file: `Emitters/ActivitySVGRenderer.swift`
- owner: `ActivitySVGRenderer`
- owner's doc comment: Lays out and renders activity diagrams as SVG without dagre. Uses a simple longest-path layering: each node gets a row equal to 1 + max row of any non-back-edge predecessor, where back-edges are those a DFS from the start node finds closing a cycle. Within each row, nodes are spread horizontally in creation order. Back-edges (loop → loopStart) are rendered as dashed curves going upward.
- the function's doc comment: (none)
- same-file functions it calls: forwardEdges
- same-file functions that call it: computeLayout

```swift
    static func computeRows(graph: ActivityGraph) -> [Int: Int] {
        var rows: [Int: Int] = [:]
        guard let start = graph.startNode else {
            for node in graph.nodes { rows[node.id] = 0 }
            return rows
        }

        // Kahn's algorithm over the acyclic forward edges, so a node is placed only after
        // every predecessor has its final row — a join always lands below its longest branch.
        var successors: [Int: [Int]] = [:]
        var inDegree: [Int: Int] = [:]
        for edge in forwardEdges(from: start.id, in: graph.edges) {
            successors[edge.fromId, default: []].append(edge.toId)
            inDegree[edge.toId, default: 0] += 1
        }
        rows[start.id] = 0
        var ready = [start.id]
        while let nodeId = ready.popLast() {
            let nextRow = (rows[nodeId] ?? 0) + 1
            for target in successors[nodeId] ?? [] {
                rows[target] = max(rows[target] ?? 0, nextRow)
                inDegree[target, default: 0] -= 1
                if inDegree[target] == 0 { ready.append(target) }
            }
        }

        for node in graph.nodes where rows[node.id] == nil {
            rows[node.id] = 0
        }
        return rows
    }
```

## calibration/2

- repository: `SwiftUMLStudio` at `e36da59`
- file: `Emitters/ActivitySVGRenderer.swift`
- owner: `ActivitySVGRenderer`
- owner's doc comment: Lays out and renders activity diagrams as SVG without dagre. Uses a simple longest-path layering: each node gets a row equal to 1 + max row of any non-back-edge predecessor. Within each row, nodes are spread horizontally in creation order. Back-edges (loop → loopStart) are rendered as dashed curves going upward.
- the function's doc comment: (none)
- same-file functions it calls: (none)
- same-file functions that call it: computeLayout

```swift
    static func computeRows(graph: ActivityGraph) -> [Int: Int] {
        var rows: [Int: Int] = [:]
        guard let start = graph.startNode else {
            for node in graph.nodes { rows[node.id] = 0 }
            return rows
        }
        rows[start.id] = 0

        let iterationCap = graph.nodes.count * max(1, graph.edges.count) + 10
        var iterations = 0
        var changed = true
        while changed && iterations < iterationCap {
            changed = false
            iterations += 1
            for edge in graph.edges {
                guard edge.toId != edge.fromId else { continue }
                guard let fromRow = rows[edge.fromId] else { continue }
                if let toRow = rows[edge.toId], toRow <= fromRow { continue }
                let newRow = fromRow + 1
                if let existing = rows[edge.toId] {
                    if newRow > existing {
                        rows[edge.toId] = newRow
                        changed = true
                    }
                } else {
                    rows[edge.toId] = newRow
                    changed = true
                }
            }
        }

        for node in graph.nodes where rows[node.id] == nil {
            rows[node.id] = 0
        }
        return rows
    }
```

## calibration/3

- repository: `SwiftUMLStudio` at `c6c82e3`
- file: `Model/ComponentSVGRenderer.swift`
- owner: `ComponentSVGRenderer`
- owner's doc comment: Computes a positioned `ComponentLayout` from a `ComponentModel` and emits an SVG representation. Components are arranged in dependency-level rows: "leaf" components (the ones every other target depends on) at the bottom, dependent components stacked above them. Within a row, components are laid out left-to-right and centered horizontally.
- the function's doc comment: (shown in the text)
- same-file functions it calls: chainDepth
- same-file functions that call it: computeLayout

```swift
    /// Group components into rows so each row's components depend only on
    /// components in *later* rows. Row 0 is the top of the canvas (the most
    /// "dependent" targets), the last row is the bottom (the most depended-on
    /// leaf libraries).
    static func dependencyLevels(for model: ComponentModel) -> [[String]] {
        let names = model.components.map(\.name)
        if names.isEmpty { return [] }

        // outDegree["A"] = depth of A's dependency chain.
        // Compute by traversing the `from -> to` adjacency.
        var adjacency: [String: [String]] = [:]
        for dependency in model.dependencies {
            adjacency[dependency.from, default: []].append(dependency.to)
        }

        var depthCache: [String: Int] = [:]
        let depths = names.map {
            (name: $0, depth: chainDepth(of: $0, adjacency: adjacency, cache: &depthCache))
        }
        let maxDepth = depths.map(\.depth).max() ?? 0
        var rows = Array(repeating: [String](), count: maxDepth + 1)
        for entry in depths {
            // Row 0 = highest-depth (most "consumer"-y) at the top.
            let row = maxDepth - entry.depth
            rows[row].append(entry.name)
        }
        return rows
    }
```

## calibration/4

- repository: `SwiftUMLStudio` at `c6c82e3`
- file: `Emitters/ActivitySVGRenderer.swift`
- owner: `ActivitySVGRenderer`
- owner's doc comment: Lays out and renders activity diagrams as SVG without dagre. Uses a simple longest-path layering: each node gets a row equal to 1 + max row of any non-back-edge predecessor, where back-edges are those a DFS from the start node finds closing a cycle. Within each row, nodes are spread horizontally in creation order. Back-edges (loop → loopStart) are rendered as dashed curves going upward.
- the function's doc comment: (none)
- same-file functions it calls: (none)
- same-file functions that call it: computeLayout

```swift
    static func computeColumns(graph: ActivityGraph, rows: [Int: Int]) -> [Int: Int] {
        var perRow: [Int: [Int]] = [:]
        for node in graph.nodes {
            perRow[rows[node.id] ?? 0, default: []].append(node.id)
        }
        var columns: [Int: Int] = [:]
        for (_, ids) in perRow {
            let sorted = ids.sorted()
            let count = sorted.count
            for (index, identifier) in sorted.enumerated() {
                columns[identifier] = index - (count - 1) / 2
            }
        }
        return columns
    }
```

## calibration/5

- repository: (synthetic)
- file: `Graph.swift`
- owner: `TaskGraph`
- owner's doc comment: A directed acyclic graph of build tasks.
- the function's doc comment: The level of every task reachable from `root`.
- same-file functions it calls: (none)
- same-file functions that call it: (none)

```swift
    func levels(from root: TaskID) -> [TaskID: Int] {
        var level: [TaskID: Int] = [root: 0]
        var queue = [root]
        var head = 0
        while head < queue.count {
            let task = queue[head]
            head += 1
            for next in successors[task, default: []] where level[next] == nil {
                level[next] = level[task]! + 1
                queue.append(next)
            }
        }
        return level
    }
```

## calibration/6

- repository: (synthetic)
- file: `Graph.swift`
- owner: `TaskGraph`
- owner's doc comment: A directed acyclic graph of build tasks.
- the function's doc comment: The tasks in an order in which each runs after everything it depends on.
- same-file functions it calls: (none)
- same-file functions that call it: (none)

```swift
    func buildOrder() -> [TaskID] {
        var remaining = dependencies.mapValues(\.count)
        var ready = remaining.filter { $0.value == 0 }.map(\.key).sorted()
        var order: [TaskID] = []
        while let task = ready.popLast() {
            order.append(task)
            for dependent in dependents[task, default: []] {
                remaining[dependent, default: 0] -= 1
                if remaining[dependent] == 0 { ready.append(dependent) }
            }
        }
        return order
    }
```

## calibration/7

- repository: (synthetic)
- file: `Outline.swift`
- owner: `Outline`
- owner's doc comment: A document outline: every heading has at most one parent heading.
- the function's doc comment: How deep `heading` sits in the outline.
- same-file functions it calls: (none)
- same-file functions that call it: (none)

```swift
    func depth(of heading: HeadingID) -> Int {
        var depth = 0
        var current = parent[heading]
        while let next = current {
            depth += 1
            current = parent[next]
        }
        return depth
    }
```

## calibration/8

- repository: (synthetic)
- file: `BuildGraph.swift`
- owner: `BuildGraph`
- owner's doc comment: A graph of build targets; `dependencies[t]` lists what `t` depends on. The graph may have cycles.
- the function's doc comment: The longest chain of dependencies below `target`, remembered in `depthCache` across calls.
- same-file functions it calls: depth
- same-file functions that call it: depth

```swift
    func depth(of target: TargetID) -> Int {
        if let known = depthCache[target] { return known }
        if visiting.contains(target) { return 0 }
        visiting.insert(target)
        let below = dependencies[target, default: []].map { depth(of: $0) }.max() ?? -1
        visiting.remove(target)
        depthCache[target] = 1 + below
        return 1 + below
    }
```
