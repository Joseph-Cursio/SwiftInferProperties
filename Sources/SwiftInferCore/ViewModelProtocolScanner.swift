import Foundation
import SwiftParser
import SwiftSyntax

/// PROTOTYPE — scans a corpus for `protocol` declarations and reports
/// which are *fakeable* with a no-op conformer: every requirement is a
/// `Void`-returning method (any arity / `async` / `throws`), and there are
/// no property / associated-type / non-`Void` requirements (which would
/// need a synthesized return value or a stored value — deferred). The
/// dependency-faking constructor uses this to satisfy a view model's
/// injected protocol dependencies so it can be constructed for verify.
public enum ViewModelProtocolScanner {

    public struct ProtocolRequirements: Sendable, Equatable {
        public let name: String
        /// The Void-method requirement signatures (e.g.
        /// `"func save(_ id: Int) async throws"`); the faker appends `{ }`.
        public let methodSignatures: [String]
        /// `true` when a no-op `struct Fake: P { … }` can conform.
        public let isFakeable: Bool

        public init(name: String, methodSignatures: [String], isFakeable: Bool) {
            self.name = name
            self.methodSignatures = methodSignatures
            self.isFakeable = isFakeable
        }
    }

    public static func scan(directory: URL) throws -> [ProtocolRequirements] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        files.sort { $0.path < $1.path }
        var result: [ProtocolRequirements] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            result.append(contentsOf: scan(source: source))
        }
        return result
    }

    public static func scan(source: String) -> [ProtocolRequirements] {
        let tree = Parser.parse(source: source)
        let visitor = Visitor()
        visitor.walk(tree)
        return visitor.protocols
    }

    private final class Visitor: SyntaxVisitor {
        var protocols: [ProtocolRequirements] = []

        init() { super.init(viewMode: .sourceAccurate) }

        override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
            var signatures: [String] = []
            var fakeable = true
            for member in node.memberBlock.members {
                if let method = member.decl.as(FunctionDeclSyntax.self) {
                    if Self.returnsVoid(method) {
                        signatures.append(method.trimmedDescription)
                    } else {
                        fakeable = false   // non-Void method needs a return value
                    }
                } else {
                    // property / associatedtype / init / subscript requirement
                    fakeable = false
                }
            }
            protocols.append(
                ProtocolRequirements(
                    name: node.name.text,
                    methodSignatures: signatures,
                    isFakeable: fakeable
                )
            )
            return .skipChildren
        }

        static func returnsVoid(_ method: FunctionDeclSyntax) -> Bool {
            guard let returnType = method.signature.returnClause?.type.trimmedDescription else {
                return true   // no return clause → Void
            }
            return returnType == "Void" || returnType == "()"
        }
    }
}
