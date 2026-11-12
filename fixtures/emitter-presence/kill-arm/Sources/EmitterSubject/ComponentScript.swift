// Verbatim from SwiftUMLStudio `e36da59`,
// `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Emitters/ComponentScript.swift`, lines 41–100: the two builders,
// `stereotypeText` and `safeAlias`. #673's kill arm (`docs/plans/emitter-presence-census-scope.md` §1.1).
//
// Two changes, neither in a function body: `ComponentScript` is an empty namespace here (the original's init
// dispatches on `Configuration`, which the arm does not need), and the two `private extension`s are internal so
// the tests can call the builders, as a widened subject would let a stub. Each `// Lnn` anchor is the line the
// mutation run recorded at `e36da59`; `scripts/emitter_presence_kill_arm.py` edits by anchor.
import Foundation

public struct ComponentScript: Sendable {}

// MARK: - PlantUML

extension ComponentScript {
    static func buildPlantUMLText(model: ComponentModel) -> String {
        var lines: [String] = ["@startuml"]
        for component in model.components {
            let stereotype = stereotypeText(for: component.kind)
            lines.append("component \"\(component.name)\" as \(safeAlias(component.name)) \(stereotype) {") // L48
            for interfaceName in component.providedInterfaces {
                lines.append("  [\(interfaceName)]") // L50
            }
            lines.append("}") // L52
        }
        for dependency in model.dependencies {
            lines.append("\(safeAlias(dependency.from)) ..> \(safeAlias(dependency.to))") // L55
        }
        lines.append("@enduml") // L57
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

extension ComponentScript {
    static func buildMermaidText(model: ComponentModel) -> String {
        var lines: [String] = ["flowchart TD"]
        for component in model.components {
            let alias = safeAlias(component.name)
            // Use Mermaid's subgraph for the component box; one line per
            // provided interface inside.
            lines.append("    subgraph \(alias)[\"\(component.name)\"]") // L80
            for interfaceName in component.providedInterfaces {
                lines.append("        \(safeAlias("\(component.name)_\(interfaceName)"))[\"\(interfaceName)\"]") // L82
            }
            lines.append("    end") // L84
        }
        for dependency in model.dependencies {
            lines.append("    \(safeAlias(dependency.from)) -.-> \(safeAlias(dependency.to))") // L87
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
