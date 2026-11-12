import Foundation

/// A rendered dependency graph in PlantUML or Mermaid format.
public struct DepsScript: Sendable {
    /// The diagram text.
    public let text: String

    /// The output format.
    public let format: DiagramFormat

    /// Positioned layout graph (available when format is `.svg`).
    public let layoutGraph: LayoutGraph?

    internal init(model: DependencyGraphModel, configuration: Configuration) {
        self.format = configuration.format
        let cycleNodes = model.detectCycles()

        switch configuration.format {
        case .plantuml:
            self.text = DepsScript.buildPlantUMLText(model: model, cycleNodes: cycleNodes)
            self.layoutGraph = nil
        case .mermaid:
            self.text = DepsScript.buildMermaidText(model: model, cycleNodes: cycleNodes)
            self.layoutGraph = nil
        case .nomnoml:
            self.text = DepsScript.buildNomnomlText(model: model, cycleNodes: cycleNodes)
            self.layoutGraph = nil
        case .svg:
            let result = DepsScript.buildSVGWithGraph(model: model)
            self.text = result.text
            self.layoutGraph = result.graph
        }
    }
}

// MARK: - DiagramOutputting

extension DepsScript: DiagramOutputting {}

// MARK: - PlantUML

private extension DepsScript {
    static func buildPlantUMLText(model: DependencyGraphModel, cycleNodes: Set<String>) -> String {
        var lines: [String] = ["@startuml"]

        let nodeDeclarations = packageNodeDeclarations(model: model)
        if !nodeDeclarations.isEmpty {
            lines.append(contentsOf: nodeDeclarations)
            lines.append("")
        }

        // Emit one edge per line
        for edge in model.edges {
            lines.append("\(edge.from) --> \(edge.to) : \(edge.kind.rawValue)")
        }

        // Annotate cycle nodes with a note block
        if !cycleNodes.isEmpty {
            let sorted = cycleNodes.sorted()
            lines.append("")
            lines.append("note as CyclicDependencies")
            lines.append("  Cyclic nodes: \(sorted.joined(separator: ", "))")
            lines.append("end note")
        }

        lines.append("@enduml")
        return lines.joined(separator: "\n")
    }

    /// When the model carries SPM provenance — either `targetKinds`
    /// (modules-mode + --package) or per-edge module tags (types-mode +
    /// --package) — emit explicit PlantUML node declarations so each node
    /// is stereotyped with its module / target kind.
    static func packageNodeDeclarations(model: DependencyGraphModel) -> [String] {
        let stereotypes = DepsScript.nodeStereotypes(model: model)
        guard !stereotypes.isEmpty else { return [] }
        // Modules-mode + --package: emit one `component` line per target.
        if !model.targetKinds.isEmpty {
            return stereotypes.keys.sorted().map { name in
                "component \"\(name)\" as \(name) <<\(stereotypes[name]!)>>"
            }
        }
        // Types-mode + --package: emit one `class` line per known type.
        return stereotypes.keys.sorted().map { name in
            "class \"\(name)\" as \(name) <<\(stereotypes[name]!)>>"
        }
    }
}

// MARK: - Stereotype map (shared across emitters)

internal extension DepsScript {
    /// Per-node stereotype text derived from SPM provenance. Empty when
    /// neither `targetKinds` nor per-edge module tags are present
    /// (i.e. the path-based, non-package flow).
    ///
    /// - In modules-mode + --package, the stereotype is the SPM target
    ///   kind (`library` / `executable` / `test` / `other`); external
    ///   dependencies are absent from the map.
    /// - In types-mode + --package, the stereotype is the owning module
    ///   name; types whose module is unknown (typically external parent
    ///   types) are absent from the map.
    static func nodeStereotypes(model: DependencyGraphModel) -> [String: String] {
        if !model.targetKinds.isEmpty {
            return model.targetKinds.mapValues { $0.rawValue }
        }
        var result: [String: String] = [:]
        for edge in model.edges {
            if let module = edge.fromModule { result[edge.from] = module }
            if let module = edge.toModule { result[edge.to] = module }
        }
        return result
    }
}

// MARK: - Mermaid

private extension DepsScript {
    static func buildMermaidText(model: DependencyGraphModel, cycleNodes: Set<String>) -> String {
        var lines: [String] = ["graph TD"]

        // Collect unique node names for declarations
        var seenNodes = Set<String>()
        for edge in model.edges {
            seenNodes.insert(edge.from)
            seenNodes.insert(edge.to)
        }

        let stereotypes = DepsScript.nodeStereotypes(model: model)

        // Declare nodes with quoted labels. In package mode the label
        // gets an extra line carrying the stereotype («library» / module
        // name) — flowchart syntax doesn't accept `<<>>` directly, so we
        // use guillemets which render cleanly as a UML stereotype.
        for node in seenNodes.sorted() {
            let safeId = mermaidId(node)
            let label: String
            if let stereotype = stereotypes[node] {
                label = "\(node)<br/>«\(stereotype)»"
            } else {
                label = node
            }
            lines.append("    \(safeId)[\"\(label)\"]")
        }

        if !seenNodes.isEmpty {
            lines.append("")
        }

        // Emit edge lines
        for edge in model.edges {
            let fromId = mermaidId(edge.from)
            let toId = mermaidId(edge.to)
            lines.append("    \(fromId) --> \(toId)")
        }

        // Annotate cycle nodes with red fill
        if !cycleNodes.isEmpty {
            lines.append("")
            for node in cycleNodes.sorted() {
                let safeId = mermaidId(node)
                lines.append("    style \(safeId) fill:#ffcccc,stroke:#cc0000")
            }
        }

        return lines.joined(separator: "\n")
    }

}

// MARK: - SVG

private extension DepsScript {
    static func buildSVGWithGraph(model: DependencyGraphModel) -> (text: String, graph: LayoutGraph) {
        let graph = LayoutGraphBuilder.buildDependencyGraph(from: model)
        let positioned = DagreLayoutEngine.layout(graph)
        return (SVGRenderer.render(positioned), positioned)
    }
}

// MARK: - Nomnoml

private extension DepsScript {
    static func buildNomnomlText(model: DependencyGraphModel, cycleNodes: Set<String>) -> String {
        // Output-building — these are nomnoml directive lines joined into a diagram script, not a
        // registry; Parallel List Drift pairs them with another emitter's line run. Not drift.
        // swiftprojectlint:disable:next parallel-list-drift
        var lines: [String] = [
            "#direction: down",
            "#fontSize: 12",
            "#spacing: 60",
            "#edges: rounded"
        ]

        let stereotypes = DepsScript.nodeStereotypes(model: model)

        // Emit edges: [From] arrow [To]. Nomnoml identifies nodes by
        // literal label, so when we have SPM provenance we inline the
        // stereotype into both endpoints rather than declaring nodes
        // separately.
        for edge in model.edges {
            let arrow: String
            switch edge.kind {
            case .inherits:
                arrow = "-:>"
            case .conforms:
                arrow = "--:>"
            case .imports:
                arrow = "-->"
            }
            let safeFrom = nomnomlLabel(edge.from, stereotype: stereotypes[edge.from])
            let safeTo = nomnomlLabel(edge.to, stereotype: stereotypes[edge.to])
            lines.append("[\(safeFrom)] \(arrow) [\(safeTo)]")
        }

        // Annotate cycle nodes
        if !cycleNodes.isEmpty {
            let sorted = cycleNodes.sorted()
            lines.append("")
            lines.append("// Cyclic nodes: \(sorted.joined(separator: ", "))")
            // nomnoml supports custom styles for highlighting
            for node in sorted {
                let safeName = node.nomnomlEscaped
                lines.append("#.warning: fill=#ffcccc stroke=#cc0000")
                lines.append("[<warning> \(safeName)]")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Produce a Nomnoml-safe node label, optionally augmented with a
    /// `«stereotype»` suffix. Guillemets render as a stereotype in
    /// Nomnoml output and avoid clashing with `[]` / `|` label syntax.
    static func nomnomlLabel(_ name: String, stereotype: String?) -> String {
        let escaped = name.nomnomlEscaped
        if let stereotype, !stereotype.isEmpty {
            return "\(escaped) «\(stereotype)»"
        }
        return escaped
    }
}

// Internal rather than private so a test can call it directly.
extension DepsScript {
    /// Convert a type/module name to a Mermaid-safe identifier (no spaces, generics, etc.).
    static func mermaidId(_ name: String) -> String {
        name
            .replacingOccurrences(of: "<", with: "_")
            .replacingOccurrences(of: ">", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }
}
