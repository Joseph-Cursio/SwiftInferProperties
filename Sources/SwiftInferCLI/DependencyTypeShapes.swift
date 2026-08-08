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
    }

    /// Scan the resolved dependency checkouts under `packageRoot`.
    ///
    /// Reads `.build/checkouts/*/Sources`, which is where SwiftPM puts a resolved
    /// dependency's source. Silent and empty when there is no `.build` — a package that has
    /// never been resolved has no dependency source to read, and that is not an error.
    static func scan(packageRoot: URL, localTypeNames: Set<String>) -> Scanned {
        var result = Scanned()
        var seenIn: [String: String] = [:]

        for root in checkoutSourceRoots(packageRoot: packageRoot) {
            let dependency = root.deletingLastPathComponent().lastPathComponent
            guard let corpus = try? FunctionScanner.scanCorpus(directory: root) else { continue }
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
            for decl in corpus.typeDecls where result.shapes[decl.name] != nil {
                result.sourceFiles[decl.name] = decl.location.file
            }
        }
        result.collisions.sort()
        return result
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
        for (name, shape) in scanned.shapes where shapes[name] == nil {
            shapes[name] = IndexedTypeShape(from: shape)
        }
        for (name, file) in scanned.sourceFiles where sourceFiles[name] == nil {
            sourceFiles[name] = file
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
    private static func checkoutSourceRoots(packageRoot: URL) -> [URL] {
        let checkouts = packageRoot
            .appendingPathComponent(".build")
            .appendingPathComponent("checkouts")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: checkouts, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }
        return entries
            .map { $0.appendingPathComponent("Sources") }
            .filter { isDirectory($0) }
            .sorted { $0.path < $1.path }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
