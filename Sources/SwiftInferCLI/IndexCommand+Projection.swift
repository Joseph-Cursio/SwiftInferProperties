import Foundation
import PropertyLawCore
import SwiftInferCore

/// V1.141 — projection helpers for `SwiftInferCommand.Index`, split out of
/// `IndexCommand.swift` to keep that file + the `Index` struct body within
/// SwiftLint's length caps (the same extension-file pattern the discover
/// commands use). Maps discovered suggestions onto their persisted index
/// rows — algebraic (`Suggestion` → `SemanticIndexEntry`) and interaction
/// (`InteractionInvariantSuggestion` → `InteractionIndexEntry`) — joining
/// any recorded triage decision.
extension SwiftInferCommand.Index {

    // MARK: - Interaction surface (V1.141)

    /// Discover + project the interaction surface for the single-target
    /// `index --target` path. Returns `[]` (no-op) when
    /// `targetName`/`workingDirectory` are absent (verify's reindex) or
    /// when interaction discovery throws — a failure here must not sink
    /// the algebraic index, so it is caught and surfaced as a warning.
    static func interactionEntries(
        for inputs: IndexInputs,
        now: String,
        diagnostics: any DiagnosticOutput
    ) -> [InteractionIndexEntry] {
        guard let targetName = inputs.targetName,
              let workingDirectory = inputs.workingDirectory else {
            return []
        }
        do {
            let suggestions = try SwiftInferCommand.DiscoverInteraction.collectSuggestions(
                target: targetName,
                workingDirectory: workingDirectory
            )
            let decisionsLoad = InteractionDecisionsLoader.load(
                startingFrom: inputs.scanDirectory
            )
            replayWarnings(decisionsLoad.warnings, to: diagnostics)
            let decisionsByHash = interactionDecisionsByHash(from: decisionsLoad.decisions)
            return suggestions.map {
                buildInteractionEntry(from: $0, decisionsByHash: decisionsByHash, now: now)
            }
        } catch {
            diagnostics.writeDiagnostic(
                "warning: interaction-surface indexing skipped for target "
                    + "\(targetName): \(error.localizedDescription)"
            )
            return []
        }
    }

    private static func interactionDecisionsByHash(
        from decisions: InteractionDecisions
    ) -> [String: InteractionDecisionRecord] {
        Dictionary(
            uniqueKeysWithValues: decisions.records.map { ($0.identityHash, $0) }
        )
    }

    /// Project an `InteractionInvariantSuggestion` (+ any recorded triage
    /// decision) onto an `InteractionIndexEntry`. Mirrors `buildEntry` for
    /// the algebraic surface: store the `0x` display hash, join the
    /// decision on the normalized (no-`0x`) hash, and stamp
    /// `firstSeenAt`/`lastSeenAt` with `now` (upsert preserves the prior
    /// `firstSeenAt` for already-known invariants).
    static func buildInteractionEntry(
        from suggestion: InteractionInvariantSuggestion,
        decisionsByHash: [String: InteractionDecisionRecord],
        now: String
    ) -> InteractionIndexEntry {
        let decisionRecord = decisionsByHash[suggestion.identity.normalized]
        return InteractionIndexEntry(
            identityHash: suggestion.identity.display,
            family: suggestion.family.rawValue,
            reducerQualifiedName: suggestion.reducerQualifiedName,
            stateTypeName: suggestion.stateTypeName,
            actionTypeName: suggestion.actionTypeName,
            predicate: suggestion.predicate,
            location: suggestion.reducerLocation,
            moduleName: suggestion.moduleName,
            score: suggestion.score,
            tier: humanReadableTier(suggestion.tier),
            decision: decisionRecord?.decision.rawValue,
            decisionAt: decisionRecord.map { isoTimestamp(from: $0.timestamp) },
            firstSeenAt: now,
            lastSeenAt: now
        )
    }

    // MARK: - Algebraic surface (Suggestion → SemanticIndexEntry)

    /// Module-internal for V1.33.C unit tests. V1.47.C adds the optional
    /// `typeShapesByName` parameter — when present, the projection looks up
    /// the carrier's `TypeShape` and mirrors it onto the entry as
    /// `IndexedTypeShape`. Tests that don't care can pass an empty map.
    static func buildEntry(
        from suggestion: Suggestion,
        decisionsByHash: [String: DecisionRecord],
        typeShapesByName: [String: PropertyLawCore.TypeShape] = [:],
        now: String
    ) -> SemanticIndexEntry {
        let evidence = suggestion.evidence.first
        let primaryName = evidence?.displayName ?? "(unknown)"
        let location: String
        if let loc = evidence?.location {
            location = "\(loc.file):\(loc.line)"
        } else {
            location = "(unknown)"
        }
        // SuggestionIdentity.display = "0x<16-char hex>".
        // DecisionRecord.identityHash = "<16-char hex>" (no 0x prefix).
        // Join on the normalized form.
        let displayHash = suggestion.identity.display
        let normalizedHash = suggestion.identity.normalized
        let decisionRecord = decisionsByHash[normalizedHash]
        let decisionString = decisionRecord?.decision.rawValue
        let decisionAt = decisionRecord.map { isoTimestamp(from: $0.timestamp) }
        let typeShape = indexedTypeShape(
            for: suggestion,
            typeShapesByName: typeShapesByName
        )
        let secondaryFunctionName = secondaryFunctionName(for: suggestion)
        return SemanticIndexEntry(
            identityHash: displayHash,
            templateName: suggestion.templateName,
            typeName: carrierType(for: suggestion),
            score: suggestion.score.total,
            tier: humanReadableTier(suggestion.score.tier),
            primaryFunctionName: primaryName,
            location: location,
            decision: decisionString,
            decisionAt: decisionAt,
            firstSeenAt: now,
            lastSeenAt: now,
            typeShape: typeShape,
            secondaryFunctionName: secondaryFunctionName,
            carrierTypeName: suggestion.carrierTypeName,
            isInstanceMethod: evidence?.isInstanceMethod ?? false,
            isMutatingMethod: evidence?.isMutatingMethod ?? false,
            isNullary: evidence?.isNullary ?? false,
            returnsSelfType: evidence?.returnsSelfType ?? false
        )
    }

    /// V1.49.C.2 — read the round-trip inverse-half name from the
    /// Suggestion's evidence array. The round-trip template emits
    /// `evidence = [forward, reverse]`; v1.49 persists the second half so
    /// the verify resolver can use it as a non-curated fallback. Returns
    /// `nil` for non-round-trip templates and for evidence arrays with
    /// fewer than 2 entries.
    private static func secondaryFunctionName(for suggestion: Suggestion) -> String? {
        guard suggestion.templateName == "round-trip" else { return nil }
        guard suggestion.evidence.count >= 2 else { return nil }
        return suggestion.evidence[1].displayName
    }

    /// V1.47.C — look up the carrier's TypeShape by bare name (no generic
    /// argument list) and mirror it onto the entry. Returns `nil` when the
    /// carrier is a free function (no carrier), a stdlib raw type the
    /// indexer doesn't store TypeShapes for, or a third-party type whose
    /// primary declaration isn't in the indexed source.
    private static func indexedTypeShape(
        for suggestion: Suggestion,
        typeShapesByName: [String: PropertyLawCore.TypeShape]
    ) -> IndexedTypeShape? {
        // V1.149 — prefer the generator carrier (the param type the
        // `Gen<T>` must produce) over the owner when they diverge, so a
        // non-raw `T` on an unrelated owner resolves its own shape.
        guard let carrier = suggestion.carrierTypeName ?? suggestion.carrier else { return nil }
        let bareName = bareTypeName(from: carrier)
        guard let kitShape = typeShapesByName[bareName] else { return nil }
        return IndexedTypeShape(from: kitShape)
    }

    /// Strip the generic argument list from a carrier name so the
    /// `TypeShape` lookup hits the bare declaration name. e.g.
    /// `"OrderedSet<Element>"` → `"OrderedSet"`, `"Complex<Double>"` →
    /// `"Complex"`, `"Int"` → `"Int"`.
    static func bareTypeName(from carrier: String) -> String {
        if let openAngle = carrier.firstIndex(of: "<") {
            return String(carrier[..<openAngle])
        }
        return carrier
    }

    /// V1.34.C — carrier-type extraction. `nil` flows through to the
    /// emitted `SemanticIndexEntry.typeName`, which renders as `(none)` in
    /// `query` output and matches `query --type none`.
    private static func carrierType(for suggestion: Suggestion) -> String? {
        suggestion.carrier
    }

    static func humanReadableTier(_ tier: Tier) -> String {
        switch tier {
        case .verified:   return "Verified"
        case .strong:     return "Strong"
        case .likely:     return "Likely"
        case .possible:   return "Possible"
        case .suppressed: return "Suppressed"
        case .advisory:   return "Advisory"
        }
    }
}
