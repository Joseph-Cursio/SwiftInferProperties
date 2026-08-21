import Foundation
import SwiftParser
import SwiftSyntax

@testable import SwiftInferCore

/// **Which throwing functions have a signature they are not free to change?**
///
/// `result-carrier-reach.md` §4 measured the `Result` refactor at −218 and then
/// corrected it to about −66 by **subtracting a template total** — 152 rows of
/// `codable-round-trip`, on the grounds that `encode(to:)` and `init(from:)` are
/// `Codable` requirements whose `throws` is fixed by the protocol. That correction
/// was arithmetic standing in for a measurement, and §7 named this as the honest
/// instrument. This is it.
///
/// ## Structural, not a two-name allowlist
///
/// The cheap version — *skip anything called `encode`* — is the shape that has
/// already been refuted here: `purity-refuting-fixpoint-census.md` found **46 of 75**
/// cascade rows were `classify`-style name collisions, **61% false**. So a function
/// qualifies only when **both** hold:
///
/// 1. its `(name, parameter labels)` matches a **throwing requirement** of some
///    protocol, and
/// 2. its containing type **declares conformance to that protocol**.
///
/// A `func encode(to:) throws` on a type that never mentions `Encodable` is a free
/// function with an unlucky name, and `nameAloneIsNotEnough` asserts it stays free.
///
/// ## Two sources of requirements
///
/// **Built-in**, for the stdlib protocols most corpora conform to without declaring:
/// `Codable` and its halves. **Parsed**, for protocols the corpus declares itself —
/// `FunctionScanner` records `.protocol` typeDecls for their inheritance clause only
/// and deliberately skips the body, so the requirements are not in any summary and
/// have to be read off the syntax here.
///
/// ## What it cannot see, stated rather than implied
///
/// - **A conformance declared in another module.** `inheritedTypes` is textual and
///   file-local; a retroactive conformance elsewhere is invisible.
/// - **A conformance behind a `typealias`.** `Codable` is itself one, and is handled
///   by name; an arbitrary alias is not.
/// - **Non-protocol reasons a signature is fixed** — an `override`, an `@objc`
///   selector, or a C-interop shim. Those are also unfree, and this classifier will
///   call them free.
///
/// Every one of those errs toward classifying a function **free**, so the arm this
/// feeds **under-counts** the fixed population and therefore **over-states** the
/// refactor's cost. The bias direction is the one worth having: it cannot manufacture
/// the correction it exists to check.
enum ConformanceFixedSignatures {

    /// A requirement identified the way a summary can be matched against it: base
    /// name plus the parameter labels, because `FunctionSummary.name` carries no
    /// label suffix (`"encode"`, never `"encode(to:)"`).
    struct Requirement: Hashable {
        let name: String
        let labels: [String?]
        let isInitializer: Bool
    }

    /// Throwing requirements of stdlib protocols, which a corpus conforms to without
    /// declaring the protocol itself. `Codable` is a `typealias` for both halves, so
    /// all three spellings are listed rather than resolved.
    static let builtIn: [String: Set<Requirement>] = [
        "Encodable": [Requirement(name: "encode", labels: ["to"], isInitializer: false)],
        "Decodable": [Requirement(name: "init", labels: ["from"], isInitializer: true)],
        "Codable": [
            Requirement(name: "encode", labels: ["to"], isInitializer: false),
            Requirement(name: "init", labels: ["from"], isInitializer: true)
        ]
    ]

    /// Throwing requirements declared by protocols in the corpus itself.
    static func declaredRequirements(in root: URL) -> [String: Set<Requirement>] {
        var table: [String: Set<Requirement>] = [:]
        for file in SwiftSourceFiles.sorted(in: root) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let collector = ProtocolRequirementCollector(viewMode: .sourceAccurate)
            collector.walk(Parser.parse(source: text))
            for (protocolName, requirements) in collector.found {
                table[protocolName, default: []].formUnion(requirements)
            }
        }
        return table
    }

    /// Conformances declared for each type name, unioned across its primary
    /// declaration and every extension of it. A generic extension's `extendedType`
    /// carries its arguments (`Dictionary<String, Int>`); the base name is what a
    /// summary's `containingTypeName` will hold.
    static func conformances(from typeDecls: [TypeDecl]) -> [String: Set<String>] {
        var table: [String: Set<String>] = [:]
        for decl in typeDecls where !decl.inheritedTypes.isEmpty {
            let base = decl.name.split(separator: "<").first.map(String.init) ?? decl.name
            table[base, default: []].formUnion(decl.inheritedTypes.map {
                $0.split(separator: "<").first.map(String.init) ?? $0
            })
        }
        return table
    }

    /// **Is this function's signature fixed by a protocol its type conforms to?**
    static func isFixed(
        _ summary: FunctionSummary,
        conformances: [String: Set<String>],
        requirements: [String: Set<Requirement>]
    ) -> Bool {
        guard let owner = summary.containingTypeName else { return false }
        let base = owner.split(separator: "<").first.map(String.init) ?? owner
        guard let declared = conformances[base] else { return false }
        let candidate = Requirement(
            name: summary.name,
            labels: summary.parameters.map(\.label),
            isInitializer: summary.isInitializer
        )
        return declared.contains { requirements[$0]?.contains(candidate) == true }
    }
}

/// Throwing function and initializer requirements, per protocol declaration.
///
/// Only **requirements** — a body means it is a default implementation in a protocol
/// extension, not a signature anyone is bound to. `ProtocolDeclSyntax` bodies hold
/// requirements exclusively, so the visitor is scoped to those rather than filtering.
final class ProtocolRequirementCollector: SyntaxVisitor {

    private(set) var found: [String: Set<ConformanceFixedSignatures.Requirement>] = [:]

    /// `_` is a *suppressed* label and `FunctionSummary.Parameter.label` reports it
    /// as `nil` (`FunctionScannerVisitor+Summary.swift:232`). Reading it as the
    /// literal string `"_"` here would make every unlabelled requirement fail to
    /// match the summaries it exists to match — a classifier that silently never
    /// fires, which is the same zero as a classifier with nothing to find.
    static func labels(of clause: FunctionParameterClauseSyntax) -> [String?] {
        clause.parameters.map { $0.firstName.text == "_" ? nil : $0.firstName.text }
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        for member in node.memberBlock.members {
            if let function = member.decl.as(FunctionDeclSyntax.self),
               function.signature.effectSpecifiers?.throwsClause != nil {
                found[name, default: []].insert(
                    .init(
                        name: function.name.text,
                        labels: Self.labels(of: function.signature.parameterClause),
                        isInitializer: false
                    )
                )
            }
            if let initializer = member.decl.as(InitializerDeclSyntax.self),
               initializer.signature.effectSpecifiers?.throwsClause != nil {
                found[name, default: []].insert(
                    .init(
                        name: "init",
                        labels: Self.labels(of: initializer.signature.parameterClause),
                        isInitializer: true
                    )
                )
            }
        }
        return .skipChildren
    }
}
