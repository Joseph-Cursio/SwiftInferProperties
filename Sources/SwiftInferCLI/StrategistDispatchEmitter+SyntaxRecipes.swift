import Foundation

// Curated generator recipes for **SwiftSyntax node carriers**.
//
// ## Why these exist
//
// Measured on SwiftProjectLint (2026-08-05, 60 picks across six packages):
// **34 of 60 were `unsupported-carrier`, and 30 of those 34 were SwiftSyntax
// node types** — `Syntax`, `FunctionCallExprSyntax`, `StructDeclSyntax`,
// `ClosureExprSyntax`, `AccessorBlockSyntax`, and friends. Half the corpus was
// unverifiable for one reason: nothing could produce a compiler AST node.
//
// That measurement also contradicts `docs/measurements/verify-carrier-reach-census.md`,
// which found carrier to be **3.6%** of declines on `SwiftInferCore` against
// template at 65%, and concluded carrier was not the gate. Both numbers are
// right about their own corpus. Which wall a corpus hits is a property of what
// its functions *take as input*: string and collection helpers hit the template
// wall, syntax visitors hit the carrier wall. The census's conclusion does not
// generalise, and this file is the other half of the picture.
//
// ## Parsed, not constructed
//
// Every recipe runs real Swift source through `Parser.parse(source:)` and
// navigates to the node, rather than assembling nodes from initialisers. A
// hand-built `StructDeclSyntax` has whatever shape the builder gave it; a parsed
// one has the trivia, token layout, and parent chain a visitor actually meets in
// the field. Since the law under test for a `predicate` pick is **totality** —
// does this function return for every input its type admits — the realism of the
// input is the entire experiment. A synthetic node that no parser would produce
// can neither confirm nor refute anything about a real visitor.
//
// ## The corpus is the measurement
//
// A totality law over 100 copies of `struct S { var a = 1 }` proves nothing:
// the seed varies, the *shape* does not, and the run reports Proven on a single
// tree sampled a hundred times. So each carrier carries a hand-written corpus of
// structurally distinct snippets — empty bodies, generics with `where` clauses,
// attributes, property wrappers, nested types, `async`/`throws` accessors — and
// the seed indexes into it. **The strength of any Proven verdict from this file
// is bounded by that list and nothing else.** Extending a corpus is the cheapest
// way to make these laws bite harder, and the honest reading of a pass is "held
// on N shapes", not "holds".
//
// ## Force-unwraps are deliberate
//
// Each navigation force-unwraps its way to the node. If a snippet does not
// produce the kind its carrier claims, the generator traps and the entry reports
// as a failure. That is correct: the alternative — a fallback node when
// navigation misses — would silently change what is under test and report a pass
// for a law that never ran on the intended shape. A broken recipe should be
// loud.
extension StrategistDispatchEmitter {

    /// Curated recipe for a SwiftSyntax node carrier, or `nil` when the carrier
    /// is not one. Consulted from `resolveRecipe` after the OrderedCollections
    /// table and before the `typeShape` branch — syntax nodes are external
    /// types with no indexed shape, so the strategist would return `.todo`.
    static func curatedSyntaxRecipe(carrier: String) -> GeneratorRecipe? {
        curatedSyntaxRecipes[carrier]
    }

    /// The carriers this table answers for, sorted. Read by
    /// `CuratedRecipePremiseTests` for the same reason as
    /// `curatedOCRecipeCarriers` — the guard reads the population out of the
    /// table, so a new curated entry is enrolled in the premise check for free.
    static var curatedSyntaxRecipeCarriers: [String] {
        curatedSyntaxRecipes.keys.sorted()
    }

    /// Fallback for a syntax node the curated table does not name: delegate to
    /// the kit's `Gen<T>.syntaxNode()`, which is written **generically over
    /// `SyntaxProtocol`** rather than per type.
    ///
    /// ## Why a fallback rather than sixteen more curated entries
    ///
    /// The curated table is 16 carriers and the survey blocks on five it does
    /// not name (`DeclModifierListSyntax`, `CodeBlockItemSyntax`,
    /// `StringLiteralExprSyntax`, `InheritanceClauseSyntax`,
    /// `DictionaryExprSyntax`). Hand-writing a navigation per kind is how that
    /// table got to 16 and it does not converge — swift-syntax has hundreds of
    /// node kinds. The kit's generator parses a snippet pool and pulls nodes of
    /// the requested kind out of it, so it answers for a kind nobody enumerated.
    ///
    /// **Curated wins on purpose.** Consulted only AFTER `curatedSyntaxRecipe`,
    /// because a curated recipe navigates to a *specific shape* the law is about
    /// (`funcCorpus` → the `FunctionDeclSyntax` of a function that throws),
    /// while the generic one draws whatever the pool happens to contain. Losing
    /// that targeting would weaken laws that currently bite.
    ///
    /// ## The gate is a naming convention, and that is load-bearing
    ///
    /// Every swift-syntax node type ends in `Syntax`. This is the one place a
    /// name-suffix test is sound rather than a heuristic: it is the library's
    /// own generated-code convention, not an inference about intent. The cost of
    /// a false positive is bounded and loud — a user type named `FooSyntax` gets
    /// a recipe that fails to compile against `SyntaxProtocol`, which reports as
    /// `build-failed` on that one entry rather than silently changing a verdict.
    ///
    /// A trailing `?` is unwrapped because `InheritanceClauseSyntax?` is a real
    /// surveyed carrier; collections are deliberately NOT unwrapped here, since
    /// `[CodeBlockItemSyntax]` and `ArraySlice<CodeBlockItemSyntax>` reach the
    /// kit through `GeneratorPlan.array` / `.arraySlice` over the element, which
    /// is the composite path's job rather than this one's.
    static func kitSyntaxNodeRecipe(carrier: String) -> GeneratorRecipe? {
        let bare = carrier.hasSuffix("?") ? String(carrier.dropLast()) : carrier
        guard bare.hasSuffix("Syntax"), !bare.contains("<"), !bare.contains("[") else { return nil }
        guard curatedSyntaxRecipes[bare] == nil else { return nil }
        return GeneratorRecipe(
            expression: "Gen<\(bare)>.syntaxNode()",
            carrierTypeName: bare,
            imports: syntaxImports + ["PropertyLawSyntax"]
        )
    }

    /// `SwiftSyntaxBuilder` is deliberately absent: the string-literal node
    /// initialisers it provides are the "constructed, not parsed" path this file
    /// rejects. `SwiftParser` is what turns source into trees.
    private static let syntaxImports = ["Foundation", "PropertyBased", "SwiftParser", "SwiftSyntax"]

    /// Render a Swift string literal for `text`, escaping backslashes and
    /// quotes. Written rather than hand-escaped because these corpora are full
    /// of nested quotes (`Text("hi")`) and interpolation-looking sequences, and
    /// hand-escaping them in the emitter is how a recipe acquires a typo that
    /// only shows up as a build failure three layers down.
    private static func literal(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Compose one recipe: index the corpus by seed, parse, navigate.
    ///
    /// The `seed % count` index keeps the outer `Gen` the only source of
    /// randomness, preserving the Xoshiro seed → outcome chain the whole verify
    /// harness depends on — the same constraint `curatedOCRecipe` documents.
    private static func parsedRecipe(
        carrier: String,
        sources: [String],
        navigation: String
    ) -> GeneratorRecipe {
        let literals = sources.map(literal).joined(separator: ", ")
        let expression = """
            Gen<Int>.int(in: 0 ... 100).map { seed -> \(carrier) in \
            let corpus: [String] = [\(literals)]; \
            let file = Parser.parse(source: corpus[seed % corpus.count]); \
            return \(navigation) }
            """
        return GeneratorRecipe(
            expression: expression,
            carrierTypeName: carrier,
            imports: syntaxImports
        )
    }

    // MARK: - Corpora

    /// Whole files, for the carriers that take a tree rather than a declaration.
    /// Deliberately spans decl kinds a visitor dispatches on differently —
    /// import, protocol, extension, actor, SwiftUI view — plus an empty file,
    /// which is the shape that finds `first!` bugs.
    private static let fileCorpus = [
        "",
        "import Foundation",
        "struct Empty {}",
        "struct ContentView: View { var body: some View { Text(\"hi\").padding() } }",
        "protocol P { func run() throws }",
        "extension Int: @retroactive Identifiable { public var id: Int { self } }",
        "actor Store { private var items: [Int] = []; func add(_ x: Int) { items.append(x) } }",
        "enum E: String, CaseIterable { case a, b }",
        "final class VM: ObservableObject { @Published var count = 0 }",
        "func f<T: Equatable>(_ v: T) -> T where T: Hashable { v }"
    ]

    private static let structCorpus = [
        "struct Empty {}",
        "struct Point { var x = 0; var y = 0 }",
        "struct ContentView: View { var body: some View { Text(\"hi\") } }",
        "struct Wrapper<T: Equatable>: Codable where T: Hashable { let value: T }",
        "@MainActor struct Flagged { @State private var on = false }",
        "struct Nested { struct Inner { let a: Int }; var inner = Inner(a: 1) }"
    ]

    private static let classCorpus = [
        "class Empty {}",
        "final class Model: ObservableObject { @Published var count = 0 }",
        "@MainActor final class VM { var items: [Int] = [] }",
        "class Generic<T> where T: Sendable { var value: T? }",
        "open class Base { open func run() {} }"
    ]

    private static let funcCorpus = [
        "func f() {}",
        "func g(a: Int, b: String = \"x\") throws -> Int { a }",
        "@objc private func h() async -> [Int] { [] }",
        "func generic<T: Equatable>(_ v: T) -> T where T: Hashable { v }",
        "func inoutParam(_ x: inout Int) { x += 1 }",
        "func trailing() { withLock { doWork() } }"
    ]

    /// Bodies, for `CodeBlockSyntax`. The empty body and the `for` loop are the
    /// two that most often break a line-counting or statement-walking helper.
    private static let bodyCorpus = [
        "func f() {}",
        "func g() { let a = 1; print(a) }",
        "func h() { if true { return } else { } }",
        "func i() { for x in 0 ..< 10 { _ = x } }",
        "func j() { do { try run() } catch { } }"
    ]

    private static let varCorpus = [
        "let a = 1",
        "var b: Int = 0",
        "@State private var c = false",
        "let (d, e) = (1, 2)",
        "var f: Int { 42 }",
        "lazy var g: [String] = []"
    ]

    /// Accessor blocks specifically — every spelling the grammar admits,
    /// including the observer form, which is a different `AccessorBlockSyntax`
    /// shape from the getter form and the one that catches `.first!` on
    /// `accessors`.
    private static let accessorCorpus = [
        "var a: Int { 1 }",
        "var b: Int { get { 1 } set { } }",
        "var c: Int { get async throws { 1 } }",
        "var d: Int = 0 { didSet { } }",
        "var e: Int = 0 { willSet { } }"
    ]

    /// Includes an *unattributed* declaration on purpose: `AttributeListSyntax`
    /// is then empty, which is the input a `hasAttribute(_:named:)` helper is
    /// most likely to mishandle.
    private static let attributeCorpus = [
        "func plain() {}",
        "@objc func f() {}",
        "@available(macOS 14, *) @MainActor func g() {}",
        "@discardableResult @inlinable func h() -> Int { 0 }"
    ]

    private static let callCorpus = [
        "f()",
        "g(1, 2)",
        "Text(\"hi\").padding()",
        "a.b.c(x: 1, y: [1, 2])",
        "foo { $0 + 1 }",
        "Button(\"Tap\") { action() }",
        "Array<Int>()",
        "x.map { $0 }.filter { $0 > 0 }"
    ]

    /// Payload-carrying and raw-valued forms alongside the empty one, since a
    /// visitor asking about an enum is usually asking about its cases.
    ///
    /// A named constant like every other corpus here. It was the one written
    /// inline at the call site, which is what tripped `multiline_literal_brackets`
    /// — the rule was pointing at a real inconsistency, not just a layout.
    private static let enumCorpus = [
        "enum E {}",
        "enum F: String, CaseIterable { case a, b }",
        "enum G<T> { case some(T), none }"
    ]

    private static let closureCorpus = [
        "{ }",
        "{ x in x }",
        "{ (a: Int, b: Int) -> Int in a + b }",
        "{ [weak self] in self?.run() }",
        "{ $0 + $1 }"
    ]

    // MARK: - Navigation

    /// The first top-level item as a `Syntax`, the common root of every
    /// declaration/expression navigation below. `Syntax(_:)` rather than
    /// `item.as(_:)`: `SyntaxChildChoices.as` is deprecated as
    /// "This cast will always fail", so casting must go through `Syntax`.
    private static let firstItem = "Syntax(file.statements.first!.item)"

    private static func firstItem(as nodeType: String) -> String {
        "\(firstItem).as(\(nodeType).self)!"
    }

    private static let curatedSyntaxRecipes: [String: GeneratorRecipe] = [
        "SourceFileSyntax": parsedRecipe(
            carrier: "SourceFileSyntax", sources: fileCorpus, navigation: "file"
        ),
        // Whole trees, so a walker gets something to walk. `Syntax(file)` rather
        // than the first item: the functions taking a bare `Syntax` in the
        // measured corpus (`containsImage(in:)`, `getLineNumber(for:)`) recurse,
        // and a single decl gives them almost nothing to recurse through.
        "Syntax": parsedRecipe(
            carrier: "Syntax", sources: fileCorpus, navigation: "Syntax(file)"
        ),
        "DeclSyntax": parsedRecipe(
            carrier: "DeclSyntax", sources: fileCorpus.filter { !$0.isEmpty },
            navigation: firstItem(as: "DeclSyntax")
        ),
        "StructDeclSyntax": parsedRecipe(
            carrier: "StructDeclSyntax", sources: structCorpus,
            navigation: firstItem(as: "StructDeclSyntax")
        ),
        "ClassDeclSyntax": parsedRecipe(
            carrier: "ClassDeclSyntax", sources: classCorpus,
            navigation: firstItem(as: "ClassDeclSyntax")
        ),
        "EnumDeclSyntax": parsedRecipe(
            carrier: "EnumDeclSyntax",
            sources: enumCorpus,
            navigation: firstItem(as: "EnumDeclSyntax")
        ),
        "FunctionDeclSyntax": parsedRecipe(
            carrier: "FunctionDeclSyntax", sources: funcCorpus,
            navigation: firstItem(as: "FunctionDeclSyntax")
        ),
        "VariableDeclSyntax": parsedRecipe(
            carrier: "VariableDeclSyntax", sources: varCorpus,
            navigation: firstItem(as: "VariableDeclSyntax")
        ),
        "MemberBlockSyntax": parsedRecipe(
            carrier: "MemberBlockSyntax", sources: structCorpus,
            navigation: firstItem(as: "StructDeclSyntax") + ".memberBlock"
        ),
        "CodeBlockSyntax": parsedRecipe(
            carrier: "CodeBlockSyntax", sources: bodyCorpus,
            navigation: firstItem(as: "FunctionDeclSyntax") + ".body!"
        ),
        "PatternBindingSyntax": parsedRecipe(
            carrier: "PatternBindingSyntax", sources: varCorpus,
            navigation: firstItem(as: "VariableDeclSyntax") + ".bindings.first!"
        ),
        "AccessorBlockSyntax": parsedRecipe(
            carrier: "AccessorBlockSyntax", sources: accessorCorpus,
            navigation: firstItem(as: "VariableDeclSyntax") + ".bindings.first!.accessorBlock!"
        ),
        "AttributeListSyntax": parsedRecipe(
            carrier: "AttributeListSyntax", sources: attributeCorpus,
            navigation: firstItem(as: "FunctionDeclSyntax") + ".attributes"
        ),
        "ExprSyntax": parsedRecipe(
            carrier: "ExprSyntax", sources: callCorpus,
            navigation: firstItem(as: "ExprSyntax")
        ),
        "FunctionCallExprSyntax": parsedRecipe(
            carrier: "FunctionCallExprSyntax", sources: callCorpus,
            navigation: firstItem(as: "FunctionCallExprSyntax")
        ),
        "ClosureExprSyntax": parsedRecipe(
            carrier: "ClosureExprSyntax", sources: closureCorpus,
            navigation: firstItem(as: "ClosureExprSyntax")
        ),
        "TokenSyntax": parsedRecipe(
            carrier: "TokenSyntax", sources: funcCorpus,
            navigation: firstItem(as: "FunctionDeclSyntax") + ".name"
        )
    ]
}
