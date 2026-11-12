// Verbatim from SwiftUMLStudio `e36da59`,
// `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Model/ComponentModel.swift` and `ComponentKind.swift`
// (doc comments shortened). #673's kill arm (`docs/plans/emitter-presence-census-scope.md` §1.1).
import Foundation

public enum ComponentKind: String, Sendable, Hashable {
    case executable
    case library
    case test
    case other
}

/// IR for a Component diagram. One `Component` per SPM target, plus the
/// directed `target_dependencies` edges between them.
public struct ComponentModel: Sendable, Hashable {
    public let components: [Component]
    public let dependencies: [ComponentDependency]

    public init(components: [Component] = [], dependencies: [ComponentDependency] = []) {
        self.components = components
        self.dependencies = dependencies
    }

    public var isEmpty: Bool { components.isEmpty }
}

/// One SPM target rendered as a UML component box.
public struct Component: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let kind: Kind
    public let providedInterfaces: [String]

    public typealias Kind = ComponentKind

    public init(name: String, kind: Kind, providedInterfaces: [String] = []) {
        self.id = name
        self.name = name
        self.kind = kind
        self.providedInterfaces = providedInterfaces
    }
}

/// `from` depends on `to`. Mirrors a target's `target_dependencies` entry.
public struct ComponentDependency: Sendable, Hashable {
    public let from: String
    public let to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}
