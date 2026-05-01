import Foundation
import SwiftInferCore

/// SwiftInferTemplates — TemplateEngine template registry.
///
/// PRD v0.3 §5.2 specifies eight shipped templates: round-trip, idempotence,
/// commutativity, associativity, monotonicity, identity-element,
/// invariant-preservation, inverse-pair. M1.3 shipped **idempotence**; M1.4
/// adds **round-trip** + cross-function pairing; M2.3 adds **commutativity**;
/// M2.4 adds **associativity** with reducer/builder usage as a new
/// type-flow signal; M2.5 adds **identity-element** with op + identity
/// constant cross-pairing and an accumulator-with-empty-seed type-flow
/// signal; subsequent milestones add the remaining three.
public enum SwiftInferTemplates {}

/// Static registry that orchestrates every M1 template against a corpus of
/// `FunctionSummary` records. Kept in `SwiftInferTemplates` (rather than the
/// CLI) so the discovery pipeline is reachable from tests without going
/// through ArgumentParser, and so v1.1's constraint-engine upgrade has a
/// single seam to slot into.
public enum TemplateRegistry {

    /// Run every M1 template against `summaries`. Output is sorted by
    /// (file path, line) of the first evidence row so the byte-identical-
    /// reproducibility guarantee (PRD §16 #6) holds across runs.
    ///
    /// `vocabulary` is the project-extensible naming layer per PRD §4.5;
    /// templates consult it alongside their curated lists. Defaults to
    /// `.empty` so M1 call sites that haven't been updated for the M2
    /// vocabulary plumbing keep compiling.
    ///
    /// Currently runs idempotence + commutativity + associativity (per
    /// summary), round-trip (per pair produced by
    /// `FunctionPairing.candidates(in:)`), and identity-element (per pair
    /// produced by `IdentityElementPairing.candidates(in:identities:)`).
    /// Multiple templates are allowed to fire on the same function —
    /// overlap (e.g. `merge` matching both commutativity and
    /// associativity since they share the same curated naming list per
    /// v0.2 §5.2; or `add` matching idempotence + commutativity +
    /// associativity if the type pattern allows; or `merge` + `IntSet.empty`
    /// triggering identity-element on top of the binary-op suggestions)
    /// is left for the M7 algebraic-structure-composition (§5.4) cluster
    /// to deduplicate.
    ///
    /// `typeDecls` feed M3.4's `ContradictionDetector` via
    /// `EquatableResolver` — commutativity suggestions whose return type
    /// classifies `.notEquatable` and round-trip pairs where either
    /// half's domain or codomain classifies `.notEquatable` get dropped
    /// per PRD §5.6 contradictions #2 / #3. Defaults to empty so M1/M2
    /// call sites that don't yet thread type-decl info compile and run
    /// unchanged — empty `typeDecls` yields a resolver with no corpus
    /// evidence, which only drops on the curated non-Equatable shape
    /// list (function types, `Any`, `AnyObject`, opaque/existential
    /// prefixes); concrete corpus types stay `.unknown` and survive.
    ///
    /// `diagnostic` is a stderr sink for the dropped-contradiction stream
    /// (M3 plan open decision #4 default `(b)`). Defaults to a no-op so
    /// non-CLI consumers (tests, programmatic discovery) don't spew
    /// diagnostics; the CLI's `Discover.run` wires it into the existing
    /// `DiagnosticOutput` channel so drops land on stderr alongside the
    /// vocabulary/config warning lines.
    public static func discover(
        in summaries: [FunctionSummary],
        identities: [IdentityCandidate] = [],
        typeDecls: [TypeDecl] = [],
        vocabulary: Vocabulary = .empty,
        diagnostic: (String) -> Void = { _ in }
    ) -> [Suggestion] {
        // Corpus-wide union of names referenced as the closure-position
        // argument of any `.reduce(_, X)` call — feeds the associativity
        // reducer/builder-usage signal (PRD §5.3, +20). Computed once per
        // discover so per-summary template calls are O(1) lookups.
        let reducerOps: Set<String> = Set(summaries.flatMap(\.bodySignals.reducerOpsReferenced))
        // Subset whose `.reduce(seed, op)` seed was identity-shaped — feeds
        // identity-element's accumulator-with-empty-seed signal (+20).
        let opsWithIdentitySeed: Set<String> = Set(
            summaries.flatMap(\.bodySignals.reducerOpsWithIdentitySeed)
        )
        var suggestions: [Suggestion] = []
        // Per-suggestion list of type texts the M3.4 contradiction
        // detector classifies. Templates that don't surface a §5.6
        // contradiction (idempotence, associativity, identity-element)
        // skip this map entirely — the detector treats absence as keep.
        var typesToCheck: [SuggestionIdentity: [String]] = [:]
        for summary in summaries {
            if let suggestion = IdempotenceTemplate.suggest(for: summary, vocabulary: vocabulary) {
                suggestions.append(suggestion)
            }
            if let suggestion = CommutativityTemplate.suggest(for: summary, vocabulary: vocabulary) {
                suggestions.append(suggestion)
                typesToCheck[suggestion.identity] = commutativityTypes(for: summary)
            }
            if let suggestion = AssociativityTemplate.suggest(
                for: summary,
                vocabulary: vocabulary,
                reducerOps: reducerOps
            ) {
                suggestions.append(suggestion)
            }
        }
        for pair in FunctionPairing.candidates(in: summaries) {
            if let suggestion = RoundTripTemplate.suggest(for: pair, vocabulary: vocabulary) {
                suggestions.append(suggestion)
                typesToCheck[suggestion.identity] = roundTripTypes(for: pair)
            }
        }
        for pair in IdentityElementPairing.candidates(in: summaries, identities: identities) {
            if let suggestion = IdentityElementTemplate.suggest(
                for: pair,
                opsWithIdentitySeed: opsWithIdentitySeed
            ) {
                suggestions.append(suggestion)
            }
        }

        let resolver = EquatableResolver(typeDecls: typeDecls)
        let outcome = ContradictionDetector.filter(
            suggestions,
            typesToCheck: typesToCheck,
            resolver: resolver
        )
        for drop in outcome.dropped {
            diagnostic("contradiction: " + drop.reason)
        }
        return outcome.kept.sorted(by: lessThan)
    }

    /// Convenience: scan `directory` recursively, run every shipped
    /// template against the resulting summaries + identity candidates,
    /// and filter out any suggestion whose identity matches a
    /// `// swiftinfer: skip <hash>` marker found anywhere in the scanned
    /// `.swift` files (PRD §7.5). Uses `FunctionScanner.scanCorpus` so
    /// summaries, identity candidates, and `TypeDecl` records all come
    /// from a single AST walk — keeps the §13 perf budget intact even
    /// with the M3.4 contradiction pass active.
    public static func discover(
        in directory: URL,
        vocabulary: Vocabulary = .empty,
        diagnostic: (String) -> Void = { _ in }
    ) throws -> [Suggestion] {
        let corpus = try FunctionScanner.scanCorpus(directory: directory)
        let skipHashes = try SkipMarkerScanner.skipHashes(in: directory)
        return discover(
            in: corpus.summaries,
            identities: corpus.identities,
            typeDecls: corpus.typeDecls,
            vocabulary: vocabulary,
            diagnostic: diagnostic
        ).filter { suggestion in
            !skipHashes.contains(suggestion.identity.normalized)
        }
    }

    /// PRD §5.6 #2 — every type that has to classify Equatable for the
    /// commutativity suggestion to be testable. The type pattern guard
    /// in `CommutativityTemplate` enforces param[0] == param[1] ==
    /// return, but the detector is robust to template-side changes by
    /// listing all three.
    private static func commutativityTypes(for summary: FunctionSummary) -> [String] {
        var types = summary.parameters.map(\.typeText)
        if let returnType = summary.returnTypeText {
            types.append(returnType)
        }
        return types
    }

    /// PRD §5.6 #3 — domain and codomain on both halves of the
    /// round-trip pair. `FunctionPairing` enforces
    /// `forward.return == reverse.param[0]` and vice-versa, so the
    /// resulting set is at most two distinct type texts (T and U); the
    /// detector lists all four positions for symmetry with the
    /// commutativity helper.
    private static func roundTripTypes(for pair: FunctionPair) -> [String] {
        var types: [String] = []
        types.append(contentsOf: pair.forward.parameters.map(\.typeText))
        if let returnType = pair.forward.returnTypeText {
            types.append(returnType)
        }
        types.append(contentsOf: pair.reverse.parameters.map(\.typeText))
        if let returnType = pair.reverse.returnTypeText {
            types.append(returnType)
        }
        return types
    }

    private static func lessThan(_ lhs: Suggestion, _ rhs: Suggestion) -> Bool {
        let lhsLoc = lhs.evidence.first?.location
        let rhsLoc = rhs.evidence.first?.location
        guard let lhsLoc, let rhsLoc else {
            return lhs.templateName < rhs.templateName
        }
        if lhsLoc.file != rhsLoc.file {
            return lhsLoc.file < rhsLoc.file
        }
        if lhsLoc.line != rhsLoc.line {
            return lhsLoc.line < rhsLoc.line
        }
        return lhs.templateName < rhs.templateName
    }
}
