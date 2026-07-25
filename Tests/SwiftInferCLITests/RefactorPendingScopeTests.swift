@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// The refactor-pending advisory is scoped to what was actually scanned.
///
/// A seed manifest is written for a whole project; a `discover` run covers one target. Listing
/// every kernel in the manifest therefore names work the reader cannot do from here — measured on
/// SwiftProjectLint as a byte-identical 204-line block emitted for four different `--sources`
/// values, naming all seven packages every time, while every other part of the focus reporting
/// scoped correctly.
///
/// The scoping must be **lossless**: the per-scope counts have to reconstitute the manifest, or the
/// listing has quietly become a different kind of wrong. On that subject they do — 198 across the
/// eight scanned scopes plus 6 in the one target deliberately left out, against a manifest of 204.
@Suite("Refactor-pending advisory — scoped to the scanned sources")
struct RefactorPendingScopeTests {

    private func seed(_ file: String, _ symbol: String) -> SeedManifest.Seed {
        SeedManifest.Seed(file: file, line: 1, symbol: symbol, rule: "Pure Closure", kind: .extractableKernel)
    }

    // MARK: - The path predicate

    /// Seed paths are relative to the linter's working directory; scanned paths are absolute. The
    /// match is a path-component-aligned suffix.
    @Test
    func aRelativeSeedPathMatchesTheAbsoluteScannedPath() {
        let scanned: Set<String> = ["/Users/dev/Project/Packages/Config/Sources/Config/Loader.swift"]
        #expect(
            SwiftInferCommand.Discover.inScope(
                seed("Packages/Config/Sources/Config/Loader.swift", "parse"),
                scannedFiles: scanned
            )
        )
    }

    @Test
    func aSeedInAnotherTargetDoesNotMatch() {
        let scanned: Set<String> = ["/Users/dev/Project/Packages/Models/Sources/Models/Rule.swift"]
        #expect(
            SwiftInferCommand.Discover.inScope(
                seed("Packages/Engine/Sources/Engine/Linter.swift", "run"),
                scannedFiles: scanned
            ) == false
        )
    }

    /// The alignment on `/` is what keeps same-named files in different targets apart. Matching on
    /// a bare basename would collide — this project has several `Support/` twins — and matching on
    /// equality would never fire, since the two path forms never agree.
    @Test
    func aSameNamedFileInAnotherTargetDoesNotMatch() {
        let scanned: Set<String> = ["/Users/dev/Project/Packages/Rules/Sources/Rules/Support/Policy.swift"]
        #expect(
            SwiftInferCommand.Discover.inScope(
                seed("Packages/Visitors/Sources/Visitors/Support/Policy.swift", "decide"),
                scannedFiles: scanned
            ) == false
        )
    }

    /// A suffix that is not aligned on a separator must not match: `.../MyLoader.swift` does not
    /// contain `.../Loader.swift` as a path.
    @Test
    func anUnalignedSuffixDoesNotMatch() {
        let scanned: Set<String> = ["/Users/dev/Project/Sources/Core/MyLoader.swift"]
        #expect(
            SwiftInferCommand.Discover.inScope(
                seed("Loader.swift", "parse"),
                scannedFiles: scanned
            ) == false
        )
    }

    /// An already-absolute seed path still matches itself.
    @Test
    func anIdenticalPathMatches() {
        let path = "/Users/dev/Project/Sources/Core/Loader.swift"
        #expect(SwiftInferCommand.Discover.inScope(seed(path, "parse"), scannedFiles: [path]))
    }

    // MARK: - Losslessness

    /// Every kernel in a manifest lands in exactly one scope. If a seed matched two targets, or
    /// none, the per-scope listings would stop reconstituting the manifest and the scoping would
    /// have traded one wrong answer for a quieter one.
    @Test
    func everySeedIsInExactlyOneOfTwoDisjointScopes() {
        let seeds = [
            seed("Packages/Config/Sources/Config/Loader.swift", "parse"),
            seed("Packages/Config/Sources/Config/Writer.swift", "render"),
            seed("Packages/Models/Sources/Models/Rule.swift", "key")
        ]
        let configScope: Set<String> = [
            "/p/Packages/Config/Sources/Config/Loader.swift",
            "/p/Packages/Config/Sources/Config/Writer.swift"
        ]
        let modelsScope: Set<String> = ["/p/Packages/Models/Sources/Models/Rule.swift"]

        let inConfig = seeds.filter { SwiftInferCommand.Discover.inScope($0, scannedFiles: configScope) }
        let inModels = seeds.filter { SwiftInferCommand.Discover.inScope($0, scannedFiles: modelsScope) }

        #expect(inConfig.count == 2)
        #expect(inModels.count == 1)
        #expect(inConfig.count + inModels.count == seeds.count)
    }

    @Test
    func nothingMatchesAnEmptyScan() {
        #expect(
            SwiftInferCommand.Discover.inScope(
                seed("Packages/Config/Sources/Config/Loader.swift", "parse"),
                scannedFiles: []
            ) == false
        )
    }
}
