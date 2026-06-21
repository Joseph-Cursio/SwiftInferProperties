import Foundation
import SwiftParser
import SwiftSyntax

/// PROTOTYPE — scans a corpus for `protocol` declarations and reports each
/// one's requirements structurally (instance methods with their return
/// types + instance properties). The verify-side `ViewModelProtocolFaker`
/// decides fakeability (every requirement's type must be defaultable) and
/// emits the no-op conformer. `init` / `subscript` / `associatedtype` /
/// `static` requirements set `hasUnsupportedRequirement` (can't be
/// no-op-faked here).
public enum ViewModelProtocolScanner {

    public struct ProtocolDecl: Sendable, Equatable {
        public let name: String
        public let methods: [MethodRequirement]
        public let properties: [PropertyRequirement]
        public let hasUnsupportedRequirement: Bool

        public init(
            name: String,
            methods: [MethodRequirement],
            properties: [PropertyRequirement],
            hasUnsupportedRequirement: Bool
        ) {
            self.name = name
            self.methods = methods
            self.properties = properties
            self.hasUnsupportedRequirement = hasUnsupportedRequirement
        }
    }

    /// A method requirement: its full decl text (`"func count() -> Int"`)
    /// and return type (`nil` for `Void`).
    public struct MethodRequirement: Sendable, Equatable {
        public let signature: String
        public let returnType: String?

        public init(signature: String, returnType: String?) {
            self.signature = signature
            self.returnType = returnType
        }
    }

    /// A property requirement: name + type (mutability doesn't matter — a
    /// stored `var` in the fake satisfies both `{ get }` and `{ get set }`).
    public struct PropertyRequirement: Sendable, Equatable {
        public let name: String
        public let typeText: String

        public init(name: String, typeText: String) {
            self.name = name
            self.typeText = typeText
        }
    }

    public static func scan(directory: URL) throws -> [ProtocolDecl] {
        let files = SwiftSourceFiles.sorted(in: directory)
        var result: [ProtocolDecl] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            result.append(contentsOf: scan(source: source))
        }
        return result
    }

    public static func scan(source: String) -> [ProtocolDecl] {
        let tree = Parser.parse(source: source)
        let visitor = Visitor()
        visitor.walk(tree)
        return visitor.protocols
    }

    private final class Visitor: SyntaxVisitor {
        var protocols: [ProtocolDecl] = []

        init() { super.init(viewMode: .sourceAccurate) }

        override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
            var methods: [MethodRequirement] = []
            var properties: [PropertyRequirement] = []
            var unsupported = false
            for member in node.memberBlock.members {
                let decl = member.decl
                if let method = decl.as(FunctionDeclSyntax.self) {
                    if Self.isStatic(method.modifiers) {
                        unsupported = true
                    } else {
                        methods.append(Self.requirement(method))
                    }
                } else if let property = decl.as(VariableDeclSyntax.self) {
                    if Self.isStatic(property.modifiers) {
                        unsupported = true
                    } else if let req = Self.requirement(property) {
                        properties.append(req)
                    } else {
                        unsupported = true
                    }
                } else {
                    unsupported = true   // init / subscript / associatedtype
                }
            }
            protocols.append(
                ProtocolDecl(
                    name: node.name.text,
                    methods: methods,
                    properties: properties,
                    hasUnsupportedRequirement: unsupported
                )
            )
            return .skipChildren
        }

        static func isStatic(_ modifiers: DeclModifierListSyntax) -> Bool {
            modifiers.contains { $0.name.text == "static" || $0.name.text == "class" }
        }

        static func requirement(_ method: FunctionDeclSyntax) -> MethodRequirement {
            let returnType = method.signature.returnClause?.type.trimmedDescription
            let isVoid = returnType == nil || returnType == "Void" || returnType == "()"
            return MethodRequirement(
                signature: method.trimmedDescription,
                returnType: isVoid ? nil : returnType
            )
        }

        static func requirement(_ property: VariableDeclSyntax) -> PropertyRequirement? {
            guard let binding = property.bindings.first,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeText = binding.typeAnnotation?.type.trimmedDescription else {
                return nil
            }
            return PropertyRequirement(name: pattern.identifier.text, typeText: typeText)
        }
    }
}
