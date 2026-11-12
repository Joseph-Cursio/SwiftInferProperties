import Foundation

/// A rendered Component diagram. Supports PlantUML, Mermaid (flowchart
/// fallback — Mermaid lacks a dedicated component dialect), and SVG. The SVG
/// path additionally produces a `componentLayout` for Studio's native canvas;
/// Nomnoml falls back to PlantUML since it has no component dialect either.
public struct ComponentScript: Sendable {
    public let text: String
    public let format: DiagramFormat
    public let componentLayout: ComponentLayout?

    public static let empty = ComponentScript(text: "", format: .plantuml)

    public init(model: ComponentModel, configuration: Configuration = .default) {
        switch configuration.format {
        case .mermaid:
            self.format = .mermaid
            self.text = ComponentScript.buildMermaidText(model: model)
            self.componentLayout = nil
        case .svg:
            let result = ComponentSVGRenderer.render(model)
            self.format = .svg
            self.text = result.svg
            self.componentLayout = result.layout
        default:
            self.format = .plantuml
            self.text = ComponentScript.buildPlantUMLText(model: model)
            self.componentLayout = nil
        }
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
        for component in model.components {
            let stereotype = stereotypeText(for: component.kind)
            lines.append("component \"\(component.name)\" as \(safeAlias(component.name)) \(stereotype) {")
            for interfaceName in component.providedInterfaces {
                lines.append("  [\(interfaceName)]")
            }
            lines.append("}")
        }
        for dependency in model.dependencies {
            lines.append("\(safeAlias(dependency.from)) ..> \(safeAlias(dependency.to))")
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
        for component in model.components {
            let alias = safeAlias(component.name)
            // Use Mermaid's subgraph for the component box; one line per
            // provided interface inside.
            lines.append("    subgraph \(alias)[\"\(component.name)\"]")
            for interfaceName in component.providedInterfaces {
                lines.append("        \(safeAlias("\(component.name)_\(interfaceName)"))[\"\(interfaceName)\"]")
            }
            lines.append("    end")
        }
        for dependency in model.dependencies {
            lines.append("    \(safeAlias(dependency.from)) -.-> \(safeAlias(dependency.to))")
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
