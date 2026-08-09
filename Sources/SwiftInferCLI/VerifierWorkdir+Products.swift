import Foundation

/// Which SwiftPM products each verify-workdir mode declares.
///
/// Extracted from `VerifierWorkdir.swift` on 2026-08-04, when adding
/// `PropertyLawKit` to the `.algebraic` list took that file from 399 lines to
/// 405 against a 400-line cap. The alternative was shaving the rationale until
/// it fit, which is the move this project rejects elsewhere for exactly this
/// situation (`Signal+Kind.swift`'s overflow doc: relocate, do not trim).
///
/// The seam is a real one rather than an arithmetic split: this is the whole
/// answer to *what does a generated verifier link against*, and nothing else in
/// the parent file asks that question.
extension VerifierWorkdir {

    /// Build the comma-joined target `dependencies:` array.
    /// Mode-dependent: `.algebraic` (v1.42 default) declares
    /// ComplexModule + OrderedCollections + RealModule + PropertyBased
    /// + PropertyLawComplex. `.interaction` (V2.0 M3.E.2) declares
    /// PropertyBased + PropertyLawKit only — the M3.B-emitted stub
    /// imports just those. User products append in either mode.
    static func renderTargetDependenciesBlock(
        userPackage: UserPackageReference?,
        mode: WorkdirMode
    ) -> String {
        var entries: [String]
        switch mode {
        case .algebraic:
            entries = [
                ".product(name: \"ComplexModule\", package: \"swift-numerics\")",
                ".product(name: \"OrderedCollections\", package: \"swift-collections\")",
                // Phase 1 M4 (collections/async workplan) — DequeModule for
                // the curated Deque<Int> recipe, same pattern as V1.59.A's
                // OrderedCollections entry above.
                ".product(name: \"DequeModule\", package: \"swift-collections\")",
                ".product(name: \"RealModule\", package: \"swift-numerics\")",
                ".product(name: \"PropertyBased\", package: \"swift-property-based\")",
                ".product(name: \"PropertyLawComplex\", package: \"SwiftPropertyLaws\")",
                // The kit's Foundation generators (`Gen<URL>.url()`, …) are
                // extensions in `PropertyLawKit` while `Gen` is
                // `PropertyBased`'s. `.interaction`/`.valueSemantics` already
                // declared it; `.algebraic` was the outlier. See open-threads
                // → *The `Gen<URL>` defect*.
                ".product(name: \"PropertyLawKit\", package: \"SwiftPropertyLaws\")"
            ]
            // Products for the SwiftSyntax carrier recipes
            // (`StrategistDispatchEmitter+SyntaxRecipes`), gated on the same
            // condition as their `.package(…)` line — a product entry without
            // its package declaration is a manifest error, so these two lists
            // must agree. See `VerifierWorkdir.packageDependsOnSwiftSyntax`.
            if let userPackage, packageDependsOnSwiftSyntax(at: userPackage.packagePath) {
                entries.append(".product(name: \"SwiftSyntax\", package: \"swift-syntax\")")
                entries.append(".product(name: \"SwiftParser\", package: \"swift-syntax\")")
                // The kit's generic node generator (`Gen<T>.syntaxNode()` over
                // every `SyntaxProtocol`), which backs
                // `StrategistDispatchEmitter.kitSyntaxNodeRecipe` for the node
                // kinds the curated table does not name. Gated on the SAME
                // condition as the two products above, not declared always:
                // `PropertyLawSyntax` links `SwiftParser`, so a subject that
                // does not already use swift-syntax would pay for a dependency
                // no pick of its can reach. That gate is the kit's opt-in
                // posture honoured at the point where the cost is actually
                // known — here the stub already links SwiftSyntax+SwiftParser
                // because the subject does, so the marginal cost is nil.
                //
                // Measured (2026-08-09, `SwiftInferCore` @ kit 3.28.0): 9 of 20
                // `unsupported-carrier` rows name a syntax node or
                // `ArraySlice<CodeBlockItemSyntax>`, and the kit vends a
                // generator for every one — they declined for want of an
                // import, not for want of a generator.
                entries.append(".product(name: \"PropertyLawSyntax\", package: \"SwiftPropertyLaws\")")
            }

        case .interaction:
            entries = [
                ".product(name: \"PropertyBased\", package: \"swift-property-based\")",
                ".product(name: \"PropertyLawKit\", package: \"SwiftPropertyLaws\")"
            ]

        case .interactionTCA:
            entries = [
                ".product(name: \"PropertyBased\", package: \"swift-property-based\")",
                ".product(name: \"PropertyLawKit\", package: \"SwiftPropertyLaws\")",
                ".product(name: \"ComposableArchitecture\", "
                    + "package: \"swift-composable-architecture\")"
            ]

        case .interactionMobius:
            entries = [
                ".product(name: \"PropertyBased\", package: \"swift-property-based\")",
                ".product(name: \"PropertyLawKit\", package: \"SwiftPropertyLaws\")",
                ".product(name: \"MobiusCore\", package: \"Mobius.swift\")"
            ]
        }
        if let userPackage {
            for productName in userPackage.productNames {
                entries.append(
                    ".product(name: \(escapedLiteral(productName)), "
                        + "package: \(escapedLiteral(userPackage.packageIdentity)))"
                )
            }
        }
        // #169 — the product edges need no rewrite when a URL dependency is
        // collapsed into the corpus, because the collision *is* the two
        // identities being equal: `package: "swift-collections"` resolves
        // against the surviving path dependency unchanged. What can now repeat
        // is a product: surveying swift-collections makes the built-in
        // `OrderedCollections` edge and the corpus's own resolved product the
        // same line. Order-preserving, so the built-in entries stay first.
        var seen: Set<String> = []
        return entries
            .filter { seen.insert($0).inserted }
            .map { "                \($0)" }
            .joined(separator: ",\n")
    }
}
