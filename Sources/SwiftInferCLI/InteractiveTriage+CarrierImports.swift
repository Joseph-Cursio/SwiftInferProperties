import Foundation
import PropertyLawCore
import SwiftInferCore

extension InteractiveTriage {

    /// The `@testable import` lines for modules the carrier reaches but the subject's own module
    /// does not re-export.
    ///
    /// **This is `VerifyImportSet`, which already existed and had one caller.** The verify
    /// emitter has resolved imports structurally since 2026-08-03, when 37 of 126 `predicate`
    /// entries failed on exactly this — 31 of them on `FunctionSummary` alone. The accept path
    /// never called it, so the two emitters disagreed about a question one of them had already
    /// measured and answered (#492).
    ///
    /// **Measured on the 19-repository corpus funnel re-run: 666 stubs fail because a type other
    /// than the subject is not in scope**, against the 308 the 2026-09-14 census recorded as a
    /// floor — and `predicate` (338) outnumbers `determinism` (304), so it was never the
    /// determinism-only defect that census's *Not filed* note described.
    ///
    /// ⚠ **This claims about 159 of those 666, and deliberately not the rest.** 507 of them name
    /// a type declared in a package DEPENDENCY — `Syntax`, `FunctionCallExprSyntax`, `ExprSyntax`
    /// — which `VerifyTargetInference` resolves to no module, so they are skipped here exactly as
    /// they are in verify. Reaching those needs a second half this does not do: a `.package` and
    /// product edge on the stub's own package, since `@testable import` does not re-export a
    /// dependency. `docs/plans/dependency-carrier-imports-scope.md` scoped that and declined it
    /// on a population of 2 rows; **that population reading is stale — the discover side measures
    /// 507** — but 445 of the 507 are `SwiftProjectLint` alone and only 4 of 19 repositories have
    /// any, so it reopens the question rather than settling it. Left as its own decision.
    static func carrierImportLines(
        for suggestion: Suggestion,
        entryModule: String?,
        resolving carrierImports: CarrierImports?
    ) -> String {
        guard let carrierImports else { return "" }
        var shapes: [String: IndexedTypeShape] = [:]
        for (name, shape) in carrierImports.typeShapesByName {
            shapes[name] = IndexedTypeShape(from: shape)
        }
        // **Seed the closure with every type the stub NAMES, not only the carrier.** Verify's
        // stub is built around one carrier; a discover stub draws a value per PARAMETER — the
        // arity-free arm draws the receiver and then each one — so the carrier is one of
        // several roots and often not the one that fails.
        //
        // Measured on SwiftAssist: closing over the carrier alone moved 37 missing-type
        // failures to 35 and changed no verdict, because the types still missing
        // (`SkillDescriptor`, `BuildRunner`, `RawChunk`) are parameter and return types that no
        // walk from the carrier reaches.
        var roots: Set<String> = []
        if let carrier = suggestion.carrierTypeName ?? suggestion.carrier { roots.insert(carrier) }
        for evidence in suggestion.evidence {
            roots.formUnion(evidence.parameterTypeNames)
            if let owner = evidence.qualifiedTypeName { roots.insert(owner) }
        }
        guard !roots.isEmpty else { return "" }
        let referenced = roots.reduce(into: Set<String>()) { collected, root in
            collected.formUnion(
                VerifyImportSet.referencedTypeNames(carrier: root, shapes: shapes)
            )
        }
        let modules = VerifyImportSet.modules(
            forTypes: referenced,
            entryModule: entryModule,
            sourceFileByTypeName: carrierImports.sourceFileByTypeName,
            packageRoot: carrierImports.packageRoot
        )
        // The entry module is already on its own line above, emitted whether or not the carrier
        // reaches it, so re-emitting it here would duplicate the import.
        return modules
            .filter { $0 != entryModule }
            .map { "@testable import \($0)\n" }
            .joined()
    }

    /// The provenance line for a Codable round-trip generator scaffold, or `""`.
    ///
    /// Lifted out of `wrappedFileContents` for its body-length cap when #492's carrier imports
    /// landed in it.
    static func codableScaffoldLine(for suggestion: Suggestion) -> String {
        guard suggestion.generator.source == .derivedCodableRoundTrip else { return "" }
        return "// Codable round-trip generator scaffold — medium confidence"
            + " (replace the fixture inside the generator body before this"
            + " property exercises real values)"
    }
}
