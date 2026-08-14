import Foundation

/// What the generated verifier package declares about the environment it must
/// build in — its macOS floor, and whether the corpus brings swift-syntax.
///
/// Extracted from `VerifierWorkdir.swift` on 2026-08-06, when the anchor work
/// took that file to 467 lines against a 400-line cap. The same move
/// `VerifierWorkdir+Products.swift` records for the same situation, and for the
/// reason it gives: relocate the rationale, do not shave it.
///
/// The seam is real rather than arithmetic. `+Products` answers *what does a
/// generated verifier link against*; this answers *what must be true of the
/// machine and the corpus for that link to succeed*. Both are questions about
/// the synthesized manifest that the workdir-writing logic itself never asks.
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
    /// **Mirroring the corpus is only half the requirement, and the other half was missing
    /// until 2026-08-14.** The paragraph above fixes the corpus-is-HIGHER direction. The
    /// corpus-is-LOWER direction fails just as totally and in the same words, because
    /// `PropertyLawKit` declares `.macOS(.v14)`: a verifier mirroring a corpus at 13.0 gets
    /// *"the executable requires macos 13.0, but depends on the product 'PropertyLawKit' which
    /// requires macos 14.0"*, and **every pick lands in `build-failed`**.
    ///
    /// Measured on swift-format `d2bd4b3` (2026-08-14), whose floor is a wholly ordinary
    /// `.macOS("13.0")`: **129 picks, 0 executed** — 39 reached a build and all 39 died here,
    /// the other 90 never got that far. That reads as *the tool cannot verify this package*
    /// when the truth is one line of a generated manifest.
    ///
    /// So the floor is `max(corpus, kit)`, not the corpus's value. Note this is a **regression
    /// the 2026-08-05 fix introduced**: the hardcoded `.macOS(.v14)` it replaced satisfied the
    /// kit by construction, so swift-format would have verified before that change and not
    /// after. A one-directional fix to a two-directional constraint.
    static func macOSPlatformLine(userPackage: UserPackageReference?) -> String {
        let declared = userPackage
            .flatMap { declaredMacOSVersion(inPackageAt: $0.packagePath) }
        return ".macOS(\"\(atLeastKitFloor(declared))\")"
    }

    /// The higher of the corpus's declared floor and the kit's own, compared by major version
    /// — string ordering ranks "9.0" above "14.0", the same trap `declaredMacOSVersion` calls
    /// out for its regex matches.
    ///
    /// A `nil` declaration (no manifest, or unreadable) yields the kit floor unchanged, which
    /// is the behaviour every corpus had before this existed.
    static func atLeastKitFloor(_ declared: String?) -> String {
        guard let declared,
              let declaredMajor = Int(declared.split(separator: ".").first ?? ""),
              let kitMajor = Int(kitMacOSFloor.split(separator: ".").first ?? "") else {
            return kitMacOSFloor
        }
        return declaredMajor > kitMajor ? declared : kitMacOSFloor
    }

    /// The kit's own `platforms:` floor, which the verifier can never go below because every
    /// generated executable links `PropertyLawKit`. Also the fallback when the corpus declares
    /// nothing readable — unchanged from the constant this replaced, so a corpus that worked
    /// before still does.
    ///
    /// **Guarded against the kit's manifest by `VerifierPlatformFloorTests`**, because a
    /// literal here that drifts below the kit's real floor reintroduces exactly the failure
    /// above, silently and on every corpus at once.
    static let kitMacOSFloor = "14.0"

    /// Retained spelling of `kitMacOSFloor` — the name this constant had when it meant only
    /// "the fallback". Kept so existing call sites and tests read unchanged.
    static var defaultMacOSVersion: String { kitMacOSFloor }

    /// Highest macOS version declared in `<packagePath>/Package.swift`, or `nil`.
    ///
    /// **Absent and unreadable both answer `nil`, and the caller cannot tell them apart.**
    /// No manifest is an Xcode project or a `--sources` run, and falling to
    /// `defaultMacOSVersion` is right for it. A manifest that exists and cannot be read means
    /// the declared floor is UNKNOWN, and silently using 14.0 produces a stub that fails to
    /// build on a corpus requiring more — an error naming an availability symbol, which reads
    /// as a property of the code rather than of the read.
    ///
    /// Same split, same file: `packageDependsOnSwiftSyntax` below. Leaving this one silent
    /// while its sibling reports would be an inconsistency a reader has to discover.
    static func declaredMacOSVersion(
        inPackageAt packagePath: URL,
        diagnostic: (String) -> Void = { _ in /* no-op */ }
    ) -> String? {
        let manifestURL = packagePath.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return nil }
        let manifest: String
        do {
            manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        } catch {
            diagnostic(
                "warning: \(manifestURL.path) exists but could not be read — \(error). "
                    + "Falling back to the macOS \(defaultMacOSVersion) floor; if the corpus "
                    + "declares a higher one, its stubs will fail to build on availability."
            )
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
    /// - Parameter diagnostic: reports a manifest that EXISTS but cannot be read. Defaults
    ///   to a no-op, matching `SeedRestrictionResolver.resolve` and `KitEvidenceStore.load`.
    ///
    /// **An absent manifest and an unreadable one answer the same `false` for different
    /// reasons, and only one is benign.** No manifest means an Xcode project or a `--sources`
    /// run — a corpus that genuinely does not declare swift-syntax, and `false` is right. A
    /// manifest that exists and cannot be read means the answer is *unknown*, and `false`
    /// makes the stub omit `SwiftSyntax`, `SwiftParser` and `PropertyLawSyntax`.
    ///
    /// The failure then surfaces as `cannot find type 'DeclSyntax' in scope` at build time,
    /// which the survey files as `build-failed` — an instrument-failure bucket — or, worse,
    /// as `unsupported-carrier`, which reads as *no generator exists for this type* and
    /// points a reader at the kit. That is the exact misattribution
    /// `roadtest-self-dogfood-2026-08-08.md` §9.3 spent a day unpicking from the other end.
    static func packageDependsOnSwiftSyntax(
        at packagePath: URL,
        diagnostic: (String) -> Void = { _ in /* no-op */ }
    ) -> Bool {
        let manifestURL = packagePath.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            // No manifest at all — an Xcode project or a `--sources` run. Silent, because
            // this is a normal shape and `false` is the correct answer for it.
            return false
        }
        do {
            return try String(contentsOf: manifestURL, encoding: .utf8).contains("swift-syntax")
        } catch {
            diagnostic(
                "warning: \(manifestURL.path) exists but could not be read — \(error). "
                    + "Assuming the corpus does NOT depend on swift-syntax, so the verifier "
                    + "stub will omit SwiftSyntax/SwiftParser/PropertyLawSyntax. If it does "
                    + "depend on them, entries will fail to build and report as though no "
                    + "generator exists for their carrier."
            )
            return false
        }
    }}
