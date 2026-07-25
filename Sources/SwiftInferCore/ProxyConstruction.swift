import Foundation

/// Carriers that cannot be *built* but can be **parsed** — and the recipe that
/// gets a reader runnable inputs anyway.
///
/// ## The gap
///
/// `DerivationStrategist` synthesises a `Gen<T>` by assembling `T` from its
/// parts: memberwise, enum cases, an initialiser, a composite of resolvable
/// leaves. That covers value types the corpus declares. It has nothing to say
/// about a type whose only legitimate construction path is *a function from some
/// other representation* — and it ends at `.notYetComputed`, which renders as
/// "not derived (no strategy matched this type)".
///
/// On the SwiftProjectLint road test that message accounted for **60% of all
/// suggestions**, and **~92% of those carriers were SwiftSyntax nodes**
/// (`FunctionDeclSyntax`, `ClosureExprSyntax`, `Syntax`, …). The subject is a
/// static analyser; its kernels take AST nodes. For that whole class the tool
/// proposed a law and then said, in effect, *and there is no way to run it* —
/// which is false, and the subject's own hand-written property suites prove it
/// false: they generate **source text**, parse it, and run the law over the
/// resulting tree.
///
/// So the knowledge was in the room and did not reach the work, which is the
/// same failure shape as a linter that prints a finding it never seeds.
///
/// ## Why the proxy, and not a hand-built node
///
/// Worth stating because the obvious alternative is worse. SwiftSyntax nodes
/// *can* be constructed programmatically, and a generator that did so would
/// produce trees that **the parser can never produce** — missing trivia,
/// structurally impossible child arrangements. A law checked against those is
/// being asked about inputs that do not occur, and its counterexamples would be
/// unactionable. Parsing text is not a workaround for the absence of a builder;
/// it is the *correct* domain restriction.
///
/// ## Scope
///
/// Keyed on the `…Syntax` suffix rather than a curated list of node types.
/// SwiftSyntax declares hundreds and adds more each release; a list would be
/// stale within a version and wrong in the silent direction — the tool would go
/// back to "no strategy matched this type" for exactly the carriers this exists
/// to serve.
public enum ProxyConstruction {

    /// Whether this carrier is a SwiftSyntax node — parser-produced, never
    /// assembled.
    ///
    /// Rejects the generic spellings (`some SyntaxProtocol`, `any SyntaxProtocol`)
    /// and the protocol itself: there is no single concrete node to parse out, so
    /// the recipe could not name one and would be guessing.
    public static func isParserConstructed(_ typeName: String) -> Bool {
        let trimmed = typeName.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("Syntax"), trimmed != "SyntaxProtocol" else { return false }
        // A plain identifier only — no `some`/`any`, no generic arguments, no
        // collection or tuple spelling.
        return trimmed.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// The recipe for a parser-constructed carrier, or `nil` when this is not one.
    public static func recipe(subject: String, typeName: String) -> GeneratorRecipe? {
        let trimmed = typeName.trimmingCharacters(in: .whitespaces)
        guard isParserConstructed(trimmed) else { return nil }
        return GeneratorRecipe(
            subject: subject,
            typeName: trimmed,
            expression: expression(for: trimmed),
            rationale: rationale(for: trimmed)
        )
    }

    /// A deliberately small, deliberately awkward source corpus.
    ///
    /// Two jobs. Most fragments must produce nodes the law can be *true and
    /// false* about, so the same corpus exercises both arms. The last few are
    /// malformed on purpose: a predicate over syntax owes **totality**, and
    /// half-written code is the input a real editor hands an analyser on every
    /// keystroke — the case a hand-written fixture of well-formed snippets never
    /// covers.
    static let sourceFragments: [String] = [
        "struct S { var x = 0 }",
        "struct V: View { var body: some View { Text(\"hi\") } }",
        "final class C { func f(_ x: Int) -> Int { x } }",
        "actor A { func g() async {} }",
        "enum E { case a, b }",
        "extension S { var doubled: Int { x * 2 } }",
        "func free<T>(_ value: T) throws -> T { value }",
        "let closure = { (n: Int) in n + 1 }",
        "let escaping: (Int) -> Void = { _ in }",
        // Malformed on purpose — totality is a real law, not a formality.
        "struct Half { var x =",
        "func broken( {",
        ""
    ]

    static func expression(for typeName: String) -> String {
        """
        // `\(typeName)` has no `Gen`: SwiftSyntax nodes come out of the parser, not
        // out of an initialiser. Generate the SOURCE, parse it, and run the law over
        // every node of the type in the resulting tree.

        // Paste once per test target:
        //     extension SyntaxProtocol {
        //         func descendants<T: SyntaxProtocol>(of type: T.Type) -> [T] {
        //             children(viewMode: .sourceAccurate).flatMap { child -> [T] in
        //                 (child.as(T.self).map { [$0] } ?? []) + child.descendants(of: type)
        //             }
        //         }
        //     }

        let sourceGen = Gen<String?>.element(of: [
        \(sourceFragments.map { "    \(quoted($0))," }.joined(separator: "\n"))
        ] as [String]).map { $0! }

        await propertyCheck(input: sourceGen) { source in
            let tree = Parser.parse(source: source)
            for node in tree.descendants(of: \(typeName).self) {
                // the law, over `node`
            }
        }
        """
    }

    /// Swift source literal for a fragment, escaped so the emitted recipe pastes
    /// and compiles.
    static func quoted(_ fragment: String) -> String {
        let escaped = fragment
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func rationale(for typeName: String) -> String {
        "SwiftSyntax nodes are PARSED, not built. Hand-constructing a `\(typeName)` "
            + "produces trees the parser never produces — absent trivia, child "
            + "arrangements real code cannot have — so the law would be checked "
            + "against inputs that do not occur and its counterexamples would be "
            + "unactionable. Generating source and parsing it is the correct domain, "
            + "not a workaround. Keep the malformed fragments: a predicate over syntax "
            + "owes totality, and half-written code is what an analyser is handed on "
            + "every keystroke."
    }
}
