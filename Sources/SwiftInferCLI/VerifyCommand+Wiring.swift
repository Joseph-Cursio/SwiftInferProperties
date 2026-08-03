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
        guard let module = target, !module.isEmpty else { return (nil, []) }
        let product = PackageProductResolver.libraryProduct(
            exposingModule: module,
            packageRoot: packageRoot
        ) ?? module
        let reference = VerifierWorkdir.UserPackageReference(
            packagePath: packageRoot,
            productNames: [product]
        )
        return (reference, ["@testable \(module)"])
    }

    /// Wiring for one entry: an explicit `--target` if given, otherwise derived from the entry's
    /// own source path.
    ///
    /// The override comes first because derivation is conservative by design — it declines nested
    /// packages and anything outside `Sources/` — and the flag is how a reader overrules a
    /// decline. Derivation returning nil lands on `userPackageWiring`'s `(nil, [])`, which is the
    /// pre-derivation behaviour exactly.
    static func wiring(
        for entry: SemanticIndexEntry,
        explicitTarget: String?,
        packageRoot: URL
    ) -> Wiring {
        userPackageWiring(
            target: explicitTarget
                ?? VerifyTargetInference.module(
                    forLocation: entry.location,
                    packageRoot: packageRoot
                ),
            packageRoot: packageRoot
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
        packageRoot: URL
    ) -> Wiring {
        guard let corpusModuleName else {
            return wiring(for: entry, explicitTarget: nil, packageRoot: packageRoot)
        }
        let reference = corpusProductName.map {
            VerifierWorkdir.UserPackageReference(packagePath: packageRoot, productNames: [$0])
        }
        return (reference, [corpusModuleName])
    }
}
