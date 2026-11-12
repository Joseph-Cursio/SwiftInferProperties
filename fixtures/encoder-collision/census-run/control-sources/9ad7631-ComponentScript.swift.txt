import Foundation

/// A rendered Component diagram. Supports PlantUML, Mermaid (flowchart
/// fallback — Mermaid lacks a dedicated component dialect), and SVG. The SVG
/// path additionally produces a `componentLayout` for Studio's native canvas.
/// Nomnoml has no component dialect either, so it falls back to Mermaid and
/// reports `.mermaid` — like the sequence, activity, state, and ER emitters.
public struct ComponentScript: Sendable {
    public let text: String
    public let format: DiagramFormat
    public let componentLayout: ComponentLayout?

    public static let empty = ComponentScript(text: "", format: .plantuml)

    public init(model: ComponentModel, configuration: Configuration = .default) {
        let drawn = configuration.format.drawn(
            plantUML: { ComponentScript.buildPlantUMLText(model: model) },
            mermaid: { ComponentScript.buildMermaidText(model: model) },
            svg: {
                let result = ComponentSVGRenderer.render(model)
                return (result.svg, result.layout)
            }
        )
        self.text = drawn.text
        self.format = drawn.format
        self.componentLayout = drawn.layout
    }

    private init(text: String, format: DiagramFormat) {
        self.text = text
        self.format = format
        self.componentLayout = nil
    }
}

extension ComponentScript: DiagramOutputting {}

// MARK: - PlantUML

private extension ComponentScript {
    static func buildPlantUMLText(model: ComponentModel) -> String {
        var lines: [String] = ["@startuml"]
        var ids = DiagramIdentifiers(sanitize: safeAlias)
        for component in model.components {
            let stereotype = stereotypeText(for: component.kind)
            lines.append("component \"\(component.name)\" as \(ids.id(for: component.name)) \(stereotype) {")
            for interfaceName in component.providedInterfaces {
                lines.append("  [\(interfaceName)]")
            }
            lines.append("}")
        }
        for dependency in model.dependencies {
            lines.append("\(ids.id(for: dependency.from)) ..> \(ids.id(for: dependency.to))")
        }
        lines.append("@enduml")
        return lines.joined(separator: "\n")
    }

    static func stereotypeText(for kind: Component.Kind) -> String {
        switch kind {
        case .executable: return "<<executable>>"
        case .library:    return "<<library>>"
        case .test:       return "<<test>>"
        case .other:      return ""
        }
    }
}

// MARK: - Mermaid (flowchart fallback — Mermaid has no component dialect)

private extension ComponentScript {
    static func buildMermaidText(model: ComponentModel) -> String {
        var lines: [String] = ["flowchart TD"]
        var ids = DiagramIdentifiers(sanitize: safeAlias)
        for component in model.components {
            let alias = ids.id(for: component.name)
            // Use Mermaid's subgraph for the component box; one line per
            // provided interface inside.
            lines.append("    subgraph \(alias)[\"\(component.name)\"]")
            for interfaceName in component.providedInterfaces {
                // Keyed apart from component names: interface `B` of `A` and a component named
                // `A_B` both sanitize to `A_B`, and must stay two nodes.
                let interfaceId = ids.id(
                    forKey: "\(component.name)\u{0}\(interfaceName)",
                    sanitizing: "\(component.name)_\(interfaceName)"
                )
                lines.append("        \(interfaceId)[\"\(interfaceName)\"]")
            }
            lines.append("    end")
        }
        for dependency in model.dependencies {
            lines.append("    \(ids.id(for: dependency.from)) -.-> \(ids.id(for: dependency.to))")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Helpers

// Internal rather than private so a test can call it directly.
extension ComponentScript {
    /// Convert a target name into a valid PlantUML / Mermaid identifier.
    static func safeAlias(_ name: String) -> String {
        name.replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "+", with: "_")
    }
}
