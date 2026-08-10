import Foundation
import PropertyLawCore
import SwiftInferCore

/// Type shapes for types declared in a **dependency**, not in the scanned package.
///
/// ## Why the index could not see them
///
/// #118: `FunctionSummary` was the single largest carrier-decline bucket in the
/// whole-corpus survey, and it declined because two of its initializer parameters —
/// `Effect?` and `PurityVerdict`, both declared in SwiftEffectInference — have no
/// recorded shape. Not by omission: **zero** of the index's recorded source files pointed
/// outside the package, because the scan reads the package's own `Sources/`. A dependency
/// type was invisible by construction.
///
/// ## Why this became worth doing
///
/// The issue argued it was not, and was right at the time: `Effect` is not `CaseIterable`
/// and cannot be (`case externallyIdempotent(keyParameter: String?)` carries a payload), so
/// recording the shape would only move the failure to *"cannot derive an enum with an
/// associated value"* — this repo's own rule that a refuter which fires first hides every
/// refuter behind it.
///
/// **That second blocker has since been retired.** The kit ships `DerivationStrategy`
/// Tier 4 `enumCases`, whose doc says it "fills the `enum without CaseIterable/raw` gap",
/// and swift-infer consumes it (`StrategistDispatchEmitter`, `VerifyImportSet`). So the
/// downstream capability now exists and only the shape is missing.
///
/// ## Local always wins
///
/// The index keys shapes on the **bare** type name, which the sidecar maps already document
/// as a limitation, and widening the population is exactly how a bare-name collision starts
/// mattering. Two rules keep it from doing harm:
///
/// - a name the scanned package declares is **never** overwritten by a dependency's;
/// - a name two dependencies both declare is recorded from **neither**, because picking one
///   silently would hand verify a shape for the wrong type — a wrong shape is worse than no
///   shape, which is the whole reason the decline exists.
///
/// Collisions are returned rather than swallowed, so a caller can say what it skipped.
enum DependencyTypeShapes {

    struct Scanned {
        var shapes: [String: PropertyLawCore.TypeShape] = [:]
        var sourceFiles: [String: String] = [:]
        /// Bare names two or more dependencies declare. Recorded from none of them.
        var collisions: [String] = []
        /// Dependency roots actually scanned, for reporting.
        var roots: [String] = []
        /// Whether `.build/checkouts` existed at all. **The distinction this type exists to
        /// preserve:** no checkouts means *the package was never resolved*, an empty scan
        /// means *it was resolved and had nothing* — and a caller that cannot tell them apart
        /// reports a confident zero. Measured: a survey with `--scan-dependencies` returned
        /// byte-identical output to one without, because the run happened in a fresh
        /// `git worktree` that has no `.build`. Nothing said so.
        var checkoutsDirectoryFound = false
        /// Dependencies whose sources could not be read, with the reason. Was a bare
        /// `try? … else { continue }`, so a parse failure in one dependency was
        /// indistinguishable from that dependency having no types.
        var unreadable: [(dependency: String, reason: String)] = []
    }

    /// Scan the resolved dependency checkouts under `packageRoot`.
    ///
    /// Reads `.build/checkouts/*/Sources`, which is where SwiftPM puts a resolved
    /// dependency's source.
    ///
    /// **Returns what happened, and never merely nothing.** An empty result used to be
    /// unreadable in three different ways — no `.build`, an unreadable checkout, a checkout
    /// with no types — and the caller saw one undifferentiated empty map. `Scanned` now
    /// carries `checkoutsDirectoryFound`, `roots` and `unreadable` so `merging` can say which
    /// happened. This function stays free of a diagnostics channel deliberately: reporting is
    /// the caller's job, and a pure return value is what a test can assert on.
    static func scan(packageRoot: URL, localTypeNames: Set<String>) -> Scanned {
        var result = Scanned()
        var seenIn: [String: String] = [:]
        // Names an actual `struct`/`class`/`enum`/`actor` declaration has claimed, so a later
        // `extension` in another module cannot overwrite the declaring site.
        var primaryDeclarationSites: Set<String> = []

        let located = checkoutSourceRoots(packageRoot: packageRoot)
        result.checkoutsDirectoryFound = located.directoryFound
        for root in located.roots {
            let dependency = root.deletingLastPathComponent().lastPathComponent
            let corpus: ScannedCorpus
            do {
                corpus = try FunctionScanner.scanCorpus(directory: root)
            } catch {
                // Was `try? … else { continue }`. A dependency that fails to parse is a
                // different fact from one that declares no types, and the survey has no way
                // to notice the difference on its own.
                result.unreadable.append((dependency: dependency, reason: "\(error)"))
                continue
            }
            result.roots.append(dependency)

            for shape in TypeShapeBuilder.shapes(from: corpus.typeDecls) {
                // A local declaration always wins: the scanned package is the subject, and
                // its own type is the one a law is about.
                guard !localTypeNames.contains(shape.name) else { continue }
                if let other = seenIn[shape.name], other != dependency {
                    result.shapes.removeValue(forKey: shape.name)
                    result.sourceFiles.removeValue(forKey: shape.name)
                    if !result.collisions.contains(shape.name) {
                        result.collisions.append(shape.name)
                    }
                    continue
                }
                guard !result.collisions.contains(shape.name) else { continue }
                seenIn[shape.name] = dependency
                result.shapes[shape.name] = shape
            }
            // **A declaration beats an extension, and last-writer-wins was picking either.**
            // The map answers *which module must be imported to name this type*, and an
            // `extension` is not where a type is declared — it is somewhere the type is used.
            // Measured: `CodeBlockItemSyntax` recorded
            // `SwiftSyntaxBuilder/generated/SyntaxExpressibleByStringInterpolationConformances`
            // rather than its declaration in `SwiftSyntax`, so a decline naming the module
            // would have sent a reader to import the wrong one. `primaryDeclarationSites`
            // holds the names an actual declaration has claimed; an extension only fills a
            // gap none of them filled.
            recordDeclarationSites(
                from: corpus.typeDecls, into: &result, primaries: &primaryDeclarationSites
            )
        }
        result.collisions.sort()
        return result
    }

    /// Where each type is declared, preferring a real declaration over an `extension`.
    ///
    /// **A declaration beats an extension, and last-writer-wins was picking either.** The map
    /// answers *which module must be imported to name this type*, and an `extension` is not
    /// where a type is declared — it is somewhere the type is used.
    ///
    /// Measured 2026-08-09: `CodeBlockItemSyntax` recorded
    /// `SwiftSyntaxBuilder/generated/SyntaxExpressibleByStringInterpolationConformances.swift`
    /// rather than its declaration in `SwiftSyntax`, so a decline naming the module would have
    /// sent a reader to import the wrong one — the mistake `missingPairedFunction`'s doc names,
    /// arrived at from a different direction.
    ///
    /// An extension only fills a gap no declaration filled, and the first declaration wins over
    /// a later one so the result does not depend on checkout order.
    private static func recordDeclarationSites(
        from typeDecls: [TypeDecl],
        into result: inout Scanned,
        primaries: inout Set<String>
    ) {
        for decl in typeDecls where result.shapes[decl.name] != nil {
            if decl.kind == .extension {
                if result.sourceFiles[decl.name] == nil {
                    result.sourceFiles[decl.name] = decl.location.file
                }
                continue
            }
            guard !primaries.contains(decl.name) else { continue }
            primaries.insert(decl.name)
            result.sourceFiles[decl.name] = decl.location.file
        }
    }

    /// Fold dependency shapes into a pass's own maps, local-wins, and report collisions.
    ///
    /// Lives here rather than in `IndexCommand` because it is the same fact as the scan:
    /// what gets recorded, and what deliberately does not.
    static func merging(
        shapes: [String: IndexedTypeShape],
        sourceFiles: [String: String],
        localTypeNames: Set<String>,
        packageRoot: URL,
        diagnostics: any DiagnosticOutput
    ) -> (shapes: [String: IndexedTypeShape], sourceFiles: [String: String]) {
        let scanned = scan(packageRoot: packageRoot, localTypeNames: localTypeNames)
        var shapes = shapes
        var sourceFiles = sourceFiles
        var added = 0
        for (name, shape) in scanned.shapes where shapes[name] == nil {
            shapes[name] = IndexedTypeShape(from: shape)
            added += 1
        }
        for (name, file) in scanned.sourceFiles where sourceFiles[name] == nil {
            sourceFiles[name] = file
        }
        // **Say what happened.** Every branch below was previously silence, and the cost is
        // measured: a `--scan-dependencies` survey produced output byte-identical to one
        // without the flag, and the only reason that was caught is that an unrelated control
        // happened to print the shape count. `Confident zero` in the glossary is this exact
        // failure — an empty result a reader cannot distinguish from a clean one.
        //
        // The caller asked for dependency scanning, so a zero here is always worth a line.
        // (`merging` is only reached when the flag is on; with it off nothing is said, which
        // is correct — then empty genuinely is a non-event.)
        if !scanned.checkoutsDirectoryFound {
            diagnostics.writeDiagnostic(
                "warning: dependency scanning was requested, but there is no "
                    + "`.build/checkouts` under \(packageRoot.path) — SwiftPM puts resolved "
                    + "dependency sources there, so nothing could be read. Run `swift build` "
                    + "first. 0 dependency shape(s) recorded."
            )
        } else if scanned.roots.isEmpty {
            diagnostics.writeDiagnostic(
                "warning: `.build/checkouts` exists under \(packageRoot.path) but no checkout "
                    + "has a readable `Sources` directory — 0 dependency shape(s) recorded."
            )
        } else {
            diagnostics.writeDiagnostic(
                "scanned \(scanned.roots.count) dependency checkout(s) "
                    + "(\(scanned.roots.prefix(4).joined(separator: ", "))"
                    + (scanned.roots.count > 4 ? ", …" : "") + "), "
                    + "recorded \(added) shape(s)."
            )
        }
        for failure in scanned.unreadable {
            diagnostics.writeDiagnostic(
                "warning: could not read dependency `\(failure.dependency)` — "
                    + "\(failure.reason). Its types have no recorded shape, so a law whose "
                    + "carrier it declares will decline as `unsupported-carrier`."
            )
        }
        if !scanned.collisions.isEmpty {
            diagnostics.writeDiagnostic(
                "warning: \(scanned.collisions.count) type name(s) are declared by more than "
                    + "one dependency, so no shape is recorded for them — a shape for the wrong "
                    + "type is worse than none: "
                    + scanned.collisions.prefix(5).joined(separator: ", ")
                    + (scanned.collisions.count > 5 ? ", …" : "")
            )
        }
        return (shapes, sourceFiles)
    }

    /// `<packageRoot>/.build/checkouts/*/Sources`, for every checkout that has one.
    private static func checkoutSourceRoots(
        packageRoot: URL
    ) -> (directoryFound: Bool, roots: [URL]) {
        let checkouts = packageRoot
            .appendingPathComponent(".build")
            .appendingPathComponent("checkouts")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: checkouts, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return (directoryFound: false, roots: []) }
        return (directoryFound: true, roots: entries
            .map { $0.appendingPathComponent("Sources") }
            .filter { isDirectory($0) }
            .sorted { $0.path < $1.path })
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
