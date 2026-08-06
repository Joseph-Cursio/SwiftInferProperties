import Foundation

/// What the generated verifier package declares about the environment it must
/// build in — its platform floor, and whether the corpus brings swift-syntax.
///
/// Extracted from `VerifierWorkdir.swift` on 2026-08-06, when the anchor work
/// took that file to 467 lines against a 400-line cap. The same move
/// `VerifierWorkdir+Products.swift` records for the same reason: relocate the
/// rationale, do not shave it.
///
/// The seam is real rather than arithmetic. `+Products` answers *what does a
/// generated verifier link against*; this answers *what must be true of the
/// machine and the corpus for that link to succeed*. Both are questions about
/// the synthesized manifest that the workdir logic itself does not ask.
extension VerifierWorkdir {

    /// The verifier package's macOS deployment target, mirrored from the corpus.
    ///
    /// **A hardcoded floor cannot work here, and the failure is total rather than
    /// partial.** SwiftPM refuses to link an executable requiring an older
    /// platform than a product it depends on, so a verifier pinned to
    /// `.macOS(.v14)` against a corpus declaring `.macOS(.v26)` fails *every*
    /// entry with `requires macos 14.0, but depends on the product '<Module>'
    /// which requires macos 26.0` — reported as `build-failed`, i.e. as a
    /// tooling error rather than as the version mismatch it is. Measured on
    /// SwiftProjectLint (2026-08-05): 60 of 60 picks, before this existed.
    ///
    /// Raising the constant just moves the wall: pinning 26 breaks every corpus
    /// that deploys lower, which is most of them. The requirement is not a
    /// number, it is *agreement with the corpus*, so it is read from the corpus.
    ///
    /// Deliberately a text scan, not a manifest evaluation. Evaluating a
    /// `Package.swift` means running it, which is a `swift package dump-package`
    /// subprocess per workdir for one integer. The regex covers both spellings
    /// (`.macOS(.v26)` and `.macOS("26.0")`) and takes the highest it finds;
    /// anything it cannot read falls back to `defaultMacOSVersion`, which is the
    /// behaviour every corpus had before. A missed declaration therefore
    /// degrades to the old failure rather than to a new one.
    ///
    /// Emitted in the **string** form (`.macOS("26.0")`) rather than
    /// `.macOS(.v26)`: the generated manifest is `swift-tools-version: 6.1`, and
    /// `.v26` does not exist in that version's `PackageDescription` — it fails
    /// with `'v26' is unavailable`. The string form is accepted at every tools
    /// version and needs no table of enum cases to stay current.
    static func macOSPlatformLine(userPackage: UserPackageReference?) -> String {
        let version = userPackage
            .flatMap { declaredMacOSVersion(inPackageAt: $0.packagePath) }
            ?? defaultMacOSVersion
        return ".macOS(\"\(version)\")"
    }

    /// The floor used when the corpus declares nothing readable — unchanged from
    /// the constant this replaced, so a corpus that worked before still does.
    static let defaultMacOSVersion = "14.0"

    /// Highest macOS version declared in `<packagePath>/Package.swift`, or `nil`.
    static func declaredMacOSVersion(inPackageAt packagePath: URL) -> String? {
        guard let manifest = try? String(
            contentsOf: packagePath.appendingPathComponent("Package.swift"), encoding: .utf8
        ) else {
            return nil
        }
        // `.macOS(.v26)` → "26.0"; `.macOS("26.0")` / `.macOS("26")` → as written.
        // Compared numerically by major version: string ordering would rank
        // "9.0" above "14.0", which is the whole reason this is not a `max()`
        // over the raw matches.
        let patterns = [#"\.macOS\(\.v([0-9]+)\)"#, #"\.macOS\("([0-9]+)(?:\.[0-9]+)*"\)"#]
        var best: Int?
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(manifest.startIndex..., in: manifest)
            for match in regex.matches(in: manifest, range: range) {
                guard let majorRange = Range(match.range(at: 1), in: manifest),
                      let major = Int(manifest[majorRange]) else {
                    continue
                }
                best = Swift.max(best ?? major, major)
            }
        }
        return best.map { "\($0).0" }
    }

    /// Whether the corpus at `packagePath` declares a swift-syntax dependency.
    ///
    /// Gates both the `.package(…)` line and the `.product(…)` entries for the
    /// SwiftSyntax carrier recipes — see the call site in
    /// `renderDependenciesBlock` for why this condition is exactly equivalent to
    /// "those recipes can be reached".
    ///
    /// Matches the repository URL rather than a product name: the package can be
    /// spelled `swiftlang/swift-syntax` or the older `apple/swift-syntax`, and a
    /// corpus may re-export it under any target name. A corpus that reaches
    /// swift-syntax only transitively (through a dependency that links it, never
    /// naming it itself) reads as `false` here — correctly, since a function
    /// whose *signature* names a syntax node needs the direct dependency to
    /// compile at all.
    static func packageDependsOnSwiftSyntax(at packagePath: URL) -> Bool {
        guard let manifest = try? String(
            contentsOf: packagePath.appendingPathComponent("Package.swift"), encoding: .utf8
        ) else {
            return false
        }
        return manifest.contains("swift-syntax")
    }}
