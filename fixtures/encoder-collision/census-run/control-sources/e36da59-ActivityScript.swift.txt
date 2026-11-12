import Foundation

/// A rendered activity diagram in PlantUML, Mermaid, or SVG format.
public struct ActivityScript: Sendable {
    /// The diagram text.
    public let text: String

    /// The output format.
    public let format: DiagramFormat

    /// Positioned activity layout (available when format is `.svg`).
    public let activityLayout: ActivityLayout?

    /// An empty script (used when the entry point is not found).
    public static let empty = ActivityScript(text: "", format: .plantuml)

    internal init(graph: ActivityGraph, configuration: Configuration) {
        self.format = configuration.format
        switch configuration.format {
        case .plantuml:
            self.text = Self.buildPlantUMLText(from: graph)
            self.activityLayout = nil
        case .mermaid, .nomnoml:
            // nomnoml does not support activity diagrams; fall back to Mermaid
            self.text = Self.buildMermaidText(from: graph)
            self.activityLayout = nil
        case .svg:
            let layout = ActivitySVGRenderer.computeLayout(from: graph)
            self.text = ActivitySVGRenderer.renderFromLayout(layout)
            self.activityLayout = layout
        }
    }

    private init(text: String, format: DiagramFormat) {
        self.text = text
        self.format = format
        self.activityLayout = nil
    }
}

// MARK: - PlantUML (state-diagram flavor)

private extension ActivityScript {
    static func buildPlantUMLText(from graph: ActivityGraph) -> String {
        var lines: [String] = ["@startuml"]
        if !graph.entryType.isEmpty {
            lines.append("title \(graph.entryType).\(graph.entryMethod)")
        }

        if graph.nodes.isEmpty {
            lines.append("@enduml")
            return lines.joined(separator: "\n")
        }

        for node in graph.nodes {
            if let line = plantUMLNodeLine(node) {
                lines.append(line)
            }
        }

        lines.append("")

        for edge in graph.edges {
            lines.append(plantUMLEdgeLine(edge, graph: graph))
        }

        lines.append("@enduml")
        return lines.joined(separator: "\n")
    }

    /// Emit the PlantUML `state` declaration line for one node, or `nil` when
    /// the node is represented by `[*]` in transitions (start/end pseudo-states).
    static func plantUMLNodeLine(_ node: ActivityNode) -> String? {
        switch node.kind {
        case .start, .end:
            return nil
        case .action:
            let prefix = node.isAsync ? "await " : ""
            return "state \"\(plantUMLEscape(prefix + node.label))\" as N\(node.id)"
        case .decision, .loopStart:
            return "state \"\(plantUMLEscape(node.label))\" as N\(node.id) <<choice>>"
        case .merge, .loopEnd:
            return "state \" \" as N\(node.id) <<choice>>"
        case .fork:
            return "state \" \" as N\(node.id) <<fork>>"
        case .join:
            return "state \" \" as N\(node.id) <<join>>"
        }
    }

    static func plantUMLEdgeLine(_ edge: ActivityEdge, graph: ActivityGraph) -> String {
        let from = plantUMLRef(id: edge.fromId, graph: graph)
        let to = plantUMLRef(id: edge.toId, graph: graph)
        if let label = edge.label, !label.isEmpty {
            return "\(from) --> \(to) : \(plantUMLEscape(label))"
        }
        return "\(from) --> \(to)"
    }

    static func plantUMLRef(id: Int, graph: ActivityGraph) -> String {
        if let node = graph.node(withId: id), node.kind == .start || node.kind == .end {
            return "[*]"
        }
        return "N\(id)"
    }

}

// MARK: - Mermaid (flowchart flavor)

private extension ActivityScript {
    static func buildMermaidText(from graph: ActivityGraph) -> String {
        var lines: [String] = ["flowchart TD"]
        if !graph.entryType.isEmpty {
            lines.append("%% title: \(graph.entryType).\(graph.entryMethod)")
        }

        if graph.nodes.isEmpty {
            return lines.joined(separator: "\n")
        }

        for node in graph.nodes {
            lines.append(contentsOf: mermaidNodeLines(node))
        }

        lines.append("classDef forkJoin fill:#333,stroke:#333,color:#fff,stroke-width:2px;")

        for edge in graph.edges {
            lines.append(mermaidEdgeLine(edge))
        }

        return lines.joined(separator: "\n")
    }

    /// Emit the Mermaid shape lines for one activity node.
    static func mermaidNodeLines(_ node: ActivityNode) -> [String] {
        let identifier = "N\(node.id)"
        let label = mermaidEscape(node.label)
        switch node.kind {
        case .start:
            return ["\(identifier)((\"start\"))"]
        case .end:
            return ["\(identifier)(((\"end\")))"]
        case .action:
            let prefix = node.isAsync ? mermaidEscape("await ") : ""
            return ["\(identifier)[\"\(prefix)\(label)\"]"]
        case .decision, .loopStart:
            return ["\(identifier){\"\(label)\"}"]
        case .merge, .loopEnd:
            return ["\(identifier){\" \"}"]
        case .fork, .join:
            return [
                "\(identifier):::forkJoin",
                "\(identifier)[\" \"]"
            ]
        }
    }

    static func mermaidEdgeLine(_ edge: ActivityEdge) -> String {
        let from = "N\(edge.fromId)"
        let to = "N\(edge.toId)"
        if let label = edge.label, !label.isEmpty {
            return "\(from) -->|\(mermaidEscape(label))| \(to)"
        }
        return "\(from) --> \(to)"
    }
}

extension ActivityScript: DiagramOutputting {}

// Internal rather than private so a test can call them directly.
extension ActivityScript {
    static func plantUMLEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func mermaidEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "|", with: "&#124;")
    }
}
