import Foundation
import SwiftParser
import SwiftSyntax

/// A class receiver built from an initializer every argument of which has an obvious empty value.
///
/// ## Why
///
/// A law whose receiver is a class needs a constructed receiver, and one comes from a package's own
/// tests (`ReceiverConstructionHarvester`) or nowhere. SwiftProjectLint's cross-file visitors are
/// never constructed directly in a test — they are built through a helper from a local `cache` —
/// yet every one of them inherits `required init(fileCache: [String: SourceFileSyntax])` from
/// `CrossFileVisitorBase`, and `X(fileCache: [:])` is a perfectly real value of the type. After the
/// 2026-09-24 widening, 32 stubs were blocked by nothing but such a receiver.
///
/// The generator derivation cannot see this: the initializer is declared on a SUPERCLASS, often in
/// another package, and memberwise derivation is structs-only by design.
///
/// ## The rule
///
/// Walk the class and its superclasses, as declared anywhere in the given sources. A class that
/// declares any initializer offers only its own (Swift inherits designated initializers only when a
/// subclass declares none, apart from `required` ones, which this treats the same way). The first
/// accessible initializer whose every parameter has a default, or is a dictionary, array or optional,
/// is used with `[:]`, `[]` or `nil` for each. A chain reaching SwiftSyntax's `SyntaxVisitor` with no
/// initializer of its own uses `init(viewMode: .sourceAccurate)`.
///
/// ⚠ **An empty receiver is one value, not a domain.** A law checked on it says nothing about the
/// same method on a receiver holding real state; the stub's header already says the receiver is held.
public enum TrivialConstruction {

    /// One declared class: what it inherits from, and its initializers.
    public struct ClassDecl: Sendable, Equatable {
        public let superclass: String?
        public let initializers: [Initializer]
    }

    /// An initializer's parameters, each as its external label and whether a trivial value exists.
    public struct Initializer: Sendable, Equatable {
        public let isAccessible: Bool
        public let parameters: [(label: String?, value: String?)]

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.isAccessible == rhs.isAccessible
                && lhs.parameters.map(\.label) == rhs.parameters.map(\.label)
                && lhs.parameters.map(\.value) == rhs.parameters.map(\.value)
        }
    }

    /// The construction for `typeName`, and whether it needs `import SwiftSyntax`, or `nil`.
    public static func expression(for typeName: String, classes: [String: ClassDecl]) -> (String, Bool)? {
        let bare = typeName.components(separatedBy: ".").last ?? typeName
        var current = bare
        var seen: Set<String> = []
        while seen.insert(current).inserted {
            guard let decl = classes[current] else {
                return current == "SyntaxVisitor" ? ("\(typeName)(viewMode: .sourceAccurate)", true) : nil
            }
            if !decl.initializers.isEmpty {
                guard let usable = decl.initializers.first(where: isTrivial) else { return nil }
                let arguments = usable.parameters.compactMap { parameter -> String? in
                    guard let value = parameter.value, !value.isEmpty else { return nil }
                    return parameter.label.map { "\($0): \(value)" } ?? value
                }
                return ("\(typeName)(\(arguments.joined(separator: ", ")))", false)
            }
            guard let superclass = decl.superclass else { return ("\(typeName)()", false) }
            current = superclass
        }
        return nil
    }

    private static func isTrivial(_ initializer: Initializer) -> Bool {
        initializer.isAccessible && initializer.parameters.allSatisfy { $0.value != nil }
    }

    /// Every class declared in `sources`, by bare name. A name declared twice keeps neither.
    public static func classes(in sources: [String]) -> [String: ClassDecl] {
        var found: [String: ClassDecl] = [:]
        var duplicated: Set<String> = []
        for source in sources {
            let collector = ClassCollector(viewMode: .sourceAccurate)
            collector.walk(Parser.parse(source: source))
            for (name, decl) in collector.classes {
                if found[name] != nil { duplicated.insert(name) } else { found[name] = decl }
            }
        }
        duplicated.forEach { found[$0] = nil }
        return found
    }

    /// The trivial value for a parameter, or `nil` when it has none. `""` marks "has a default":
    /// the argument is omitted.
    static func trivialValue(type: TypeSyntax, hasDefault: Bool) -> String? {
        if hasDefault { return "" }
        if type.is(DictionaryTypeSyntax.self) { return "[:]" }
        if type.is(ArrayTypeSyntax.self) { return "[]" }
        if type.is(OptionalTypeSyntax.self) || type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) { return "nil" }
        return nil
    }

    private final class ClassCollector: SyntaxVisitor {
        var classes: [String: ClassDecl] = [:]

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            let superclass = node.inheritanceClause?.inheritedTypes.first?.type.trimmedDescription
            let initializers = node.memberBlock.members.compactMap { member -> Initializer? in
                guard let initializer = member.decl.as(InitializerDeclSyntax.self),
                      initializer.optionalMark == nil else { return nil }
                let isPrivate = initializer.modifiers.contains {
                    ["private", "fileprivate"].contains($0.name.text)
                }
                let parameters = initializer.signature.parameterClause.parameters.map { parameter in
                    let label = parameter.firstName.text == "_" ? nil : parameter.firstName.text
                    let value = trivialValue(type: parameter.type, hasDefault: parameter.defaultValue != nil)
                    return (label: label, value: value)
                }
                return Initializer(isAccessible: !isPrivate, parameters: parameters)
            }
            classes[node.name.text] = ClassDecl(superclass: superclass, initializers: initializers)
            return .visitChildren
        }
    }
}
