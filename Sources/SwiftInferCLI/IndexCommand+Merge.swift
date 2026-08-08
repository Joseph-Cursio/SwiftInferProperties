import Foundation
import PropertyLawCore
import SwiftInferCore

// Extracted from `IndexCommand.swift` when recording dependency type shapes (#118) took
// that file past its 400-line cap. The seam is a real one: this is the whole answer to
// *what does one indexing pass merge into the stored index*, and nothing else in the
// parent file asks that question.
extension SwiftInferCommand.Index {

    /// What `mergedAlgebraicSurface` needs about the pass beyond the pipeline itself.
    /// Bundled so the signature stays inside SwiftLint's parameter cap.
    struct SurfaceContext {
        let packageRoot: URL
        let diagnostics: any DiagnosticOutput
    }

    /// Merge one pass's **algebraic surface** into the existing index — the three things a
    /// scan learns and verify later needs, kept together because they are one fact about one
    /// pass and were drifting apart as separate statements.
    ///
    /// Returns the fresh entries alongside the merged index so the caller can still diff
    /// against the prior one; the diff is a reporting concern, not a merging one.
    static func mergedAlgebraicSurface(
        pipeline: SwiftInferCommand.Discover.PipelineResult,
        into existing: IndexStore.Index,
        decisionsByHash: [String: DecisionRecord],
        now: String,
        context: SurfaceContext
    ) -> (index: IndexStore.Index, freshEntries: [SemanticIndexEntry]) {
            // Project Suggestions → SemanticIndexEntry. Fresh `firstSeenAt` is `now` for new
            // entries; `IndexStore.upsert` preserves the prior one for already-known entries.
        let freshEntries = pipeline.suggestions.map { suggestion in
            buildEntry(
                from: suggestion,
                decisionsByHash: decisionsByHash,
                typeShapesByName: pipeline.typeShapesByName,
                now: now
            )
        }
            // WS-6 Slice 2 — the whole-module shape universe, not just per-entry carrier shapes,
            // so verify can build a `GeneratorResolver` over every scanned type and recursively
            // derive nested custom-type carriers.
            // #118 — types a law's signature reaches but this package does not declare.
            // `FunctionSummary` was the largest carrier-decline bucket in the whole-corpus
            // survey purely because two of its initializer parameters are declared in a
            // dependency, and the scan reads only the package's own `Sources/`.
        let merged = DependencyTypeShapes.merging(
            shapes: pipeline.typeShapesByName.mapValues { IndexedTypeShape(from: $0) },
            sourceFiles: pipeline.sourceFileByTypeName,
            localTypeNames: Set(pipeline.typeShapesByName.keys),
            packageRoot: context.packageRoot,
            diagnostics: context.diagnostics
        )
        let freshShapes = merged.shapes
        let freshSourceFiles = merged.sourceFiles
        return (
            IndexStore.upsert(
                freshEntries,
                into: existing,
                at: now,
                typeShapes: freshShapes,
                    // Declaration sites for every type this pass saw, so verify can resolve the
                    // module of a type that appears in a law's signature but not on its entry.
                sourceFiles: freshSourceFiles
            ),
            freshEntries
        )
    }
}
