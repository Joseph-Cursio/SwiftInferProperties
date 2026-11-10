import Foundation
import SwiftInferCore

/// **What the verifier package depends on, and what the stub imports.**
///
/// Extracted when target derivation gave the two verify paths — single-suggestion and
/// `--all-from-index` — the same question to answer, and both function bodies crossed SwiftLint's
/// length cap answering it inline. Keeping one file for it also puts the two policies side by
/// side, which is the point: they differ, and the difference is easy to get wrong.
extension SwiftInferCommand.Verify {

    /// The wiring pair: what to path-depend on, and what to `import`.
    typealias Wiring = (userPackage: VerifierWorkdir.UserPackageReference?, extraImports: [String])

    /// V1.149 — resolve the optional user-package wiring for the single-verify
    /// path. When `target` names a non-empty module, returns a path-dependency
    /// on `packageRoot` plus a `@testable` import of that module; otherwise
    /// `(nil, [])` so the v1.42 stdlib-carrier behavior is unchanged. The three
    /// distinct names are each resolved on their own axis: the `.package(path:)`
    /// identity from `packageRoot`'s basename (inside `UserPackageReference`),
    /// the `.product(name:)` from `PackageProductResolver` (tier 2 — may differ
    /// from the module), and the `@testable import` from the module name. Any
    /// of the three differing from the others now resolves correctly; the
    /// product resolution falls back to the module name when unresolvable.
    static func userPackageWiring(target: String?, packageRoot: URL) -> Wiring {
        userPackageWiring(modules: target.map { [$0] } ?? [], packageRoot: packageRoot)
    }

    /// The n-module form. `productNames` was already an array on
    /// `VerifierWorkdir.UserPackageReference`, so importing several modules of one package needed
    /// no new plumbing — only a caller that had more than one to give it.
    ///
    /// Products are de-duplicated and the order of `modules` is preserved, so this function is a
    /// function of its inputs alone — two runs of the same entry emit byte-identical source, which
    /// is what replay depends on. (The stub emitter sorts the import block itself, so the order
    /// here reaches the manifest, not the `import` lines.)
    static func userPackageWiring(modules: [String], packageRoot: URL) -> Wiring {
        let named = modules.filter { !$0.isEmpty }
        guard !named.isEmpty else { return (nil, []) }
        var products: [String] = []
        for module in named {
            let product = PackageProductResolver.libraryProduct(
                exposingModule: module,
                packageRoot: packageRoot
            ) ?? module
            if !products.contains(product) { products.append(product) }
        }
        let reference = VerifierWorkdir.UserPackageReference(
            packagePath: packageRoot,
            productNames: products
        )
        return (reference, named.map { "@testable \($0)" })
    }

    /// Wiring for one entry: an explicit `--target` if given, otherwise derived from the entry's
    /// own source path — **plus every other module the law's carrier reaches**.
    ///
    /// The override comes first because derivation is conservative by design — it declines nested
    /// packages and anything outside `Sources/` — and the flag is how a reader overrules a
    /// decline. Derivation returning nil, with no reachable types either, lands on
    /// `userPackageWiring`'s `(nil, [])`: the pre-derivation behaviour exactly.
    ///
    /// One module is not enough, and that is measured rather than supposed. A derived generator
    /// names the carrier's members and their members in turn, any of which may live elsewhere;
    /// `@testable import` does not re-export, so the stub sees a type it cannot name. **37 of 126
    /// `predicate` entries failed exactly that way** (2026-08-03), 31 on `FunctionSummary` alone.
    ///
    /// Empty `shapes` / `sourceFiles` — an un-reindexed project — reduce this to the single-module
    /// wiring, so an old index degrades to the previous behaviour instead of erroring.
    static func wiring(
        for entry: SemanticIndexEntry,
        explicitTarget: String?,
        packageRoot: URL,
        shapes: [String: IndexedTypeShape] = [:],
        sourceFiles: [String: String] = [:]
    ) -> Wiring {
        let entryModule = explicitTarget
            ?? VerifyTargetInference.module(forLocation: entry.location, packageRoot: packageRoot)
        let reachable = VerifyImportSet.referencedTypeNames(
            carrier: entry.carrierTypeName ?? entry.typeName ?? "",
            shapes: shapes
        )
        let modules = VerifyImportSet.modules(
            forTypes: reachable,
            entryModule: entryModule,
            sourceFileByTypeName: sourceFiles,
            packageRoot: packageRoot
        )
        return userPackageWiring(modules: modules, packageRoot: packageRoot)
    }

    /// Convenience over a resolved lookup — the form both pipelines actually call, so the maps
    /// travel together with the entry they were loaded beside rather than as two loose arguments.
    static func wiring(
        for resolved: ResolvedEntry,
        explicitTarget: String?,
        packageRoot: URL
    ) -> Wiring {
        wiring(
            for: resolved.entry,
            explicitTarget: explicitTarget,
            packageRoot: packageRoot,
            shapes: resolved.allShapes,
            sourceFiles: resolved.sourceFiles
        )
    }

    /// Survey wiring, which is the same question with one extra answer.
    ///
    /// `--corpus-module` configures a **curated corpus**: a separate package whose module and
    /// product are resolved on different axes and supplied explicitly, and whose sources are not
    /// under this package root at all. Derivation cannot see it and must not try — so when the
    /// flag is present it wins outright, and the plain (non-`@testable`) import is preserved
    /// because a corpus is consumed as a library, not opened up.
    ///
    /// With no flag the survey now derives per entry, which is the fix for its most misleading
    /// result: surveying the package it was run in returned `measured-error | build-failed` for
    /// every entry defined in that package — 114 of them — because the stub imported nothing and
    /// could not see the types its own generated law named. That reads as a limitation of
    /// measured verify and was a missing flag.
    static func surveyWiring(
        for entry: SemanticIndexEntry,
        corpusModuleName: String?,
        corpusProductName: String?,
        packageRoot: URL,
        shapes: [String: IndexedTypeShape] = [:],
        sourceFiles: [String: String] = [:]
    ) -> Wiring {
        guard let corpusModuleName else {
            return wiring(
                for: entry,
                explicitTarget: nil,
                packageRoot: packageRoot,
                shapes: shapes,
                sourceFiles: sourceFiles
            )
        }
        let reference = corpusProductName.map {
            VerifierWorkdir.UserPackageReference(packagePath: packageRoot, productNames: [$0])
        }
        return (reference, [corpusModuleName])
    }
}

/// One index lookup's results, kept together.
///
/// Was a 3-tuple until `sourceFileByTypeName` joined it and tripped `large_tuple`. The rule is
/// right here for a reason beyond arity: two of these three are whole-corpus maps that only mean
/// anything alongside the entry they were loaded with, and a tuple makes it easy to pass one and
/// forget the other — which is the shape of the bug that left the survey importing nothing.
struct ResolvedEntry {
    let entry: SemanticIndexEntry
    /// Whole-module shape universe, for recursive carrier derivation.
    let allShapes: [String: IndexedTypeShape]
    /// Declaration site per type name, for resolving which modules to import.
    let sourceFiles: [String: String]
}
