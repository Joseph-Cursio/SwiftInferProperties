// The pre-fix `computeRows` from SwiftUMLStudio `e36da59` (SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/
// Emitters/ActivitySVGRenderer.swift), verbatim. The kill arm's RC2 swaps it in for the fixed function
// (`docs/plans/layering-law-census-scope.md` §5.5). It keeps the first row it assigns: SwiftUMLStudio#53.
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
