import Foundation

/// Applies the access blocker a linter resolved to the functions this scan set aside.
///
/// The sibling of `SeedEffectResolver`, and the same division of labour. This scan answers the
/// access question from the syntax in front of it, which is the better source for a directly nested
/// declaration and structurally incomplete for anything else: `FunctionScanner`'s enclosing-type
/// stack is **same-declaration only**, so a member of an unmarked `extension PrivateType { … }`
/// reads here as blocked by its own modifier. The linter resolved the type. Applying its answer
/// costs a dictionary lookup against a manifest the caller already loaded.
///
/// **Why it runs once, at the scan, rather than at each consumer.** Three places turn an
/// `AccessRestriction` into something a reader acts on — the rescued suggestion's leading caveat
/// (`withAccessRestrictionCaveats`), the determinism note (`Discover+GenericLaws`), and the
/// candidate filter that decides whether to spend a package snapshot on a patch
/// (`SpeculativeWidening`). Reconciling at each would be three chances to fix two of them; the
/// original defect this closes did exactly that, surviving in the computed-property arm after the
/// function arm was fixed.
public enum SeedRestrictionResolver {

    /// Returns `restricted` in input order, with each entry's reason corrected where the manifest
    /// names a blocker this scan could not see.
    ///
    /// The join is `(file basename, symbol)`, matching `SeedFocus`: the linter writes paths
    /// relative to its own working directory while the scanner records absolute ones, so the
    /// basename is the reliable common denominator. Symbol is included because a file-level join
    /// would apply one function's blocker to every function beside it.
    public static func resolve(
        restricted: [RestrictedFunction],
        manifest: SeedManifest,
        diagnostic: (String) -> Void = { _ in /* no-op */ }
    ) -> [RestrictedFunction] {
        let seeded = restrictionIndex(from: manifest)
        guard !seeded.isEmpty else { return restricted }

        var corrected = 0
        var disagreements: [String] = []
        let updated = restricted.map { entry -> RestrictedFunction in
            let key = joinKey(file: entry.summary.location.file, symbol: entry.summary.name)
            guard let claimed = seeded[key] else { return entry }
            if entry.restriction.disagrees(with: claimed) {
                disagreements.append(entry.summary.name)
            }
            let reconciled = entry.restriction.reconciled(with: claimed)
            guard reconciled != entry.restriction else { return entry }
            corrected += 1
            return RestrictedFunction(summary: entry.summary, restriction: reconciled)
        }

        if corrected > 0 {
            diagnostic(
                "corrected \(corrected) access remedy(ies) from the seed manifest — the linter "
                    + "resolved an enclosing type this scan could not see, and widening the "
                    + "declaration alone would have been a no-op"
            )
        }
        // One aggregate line, never one per row — the `ProtocolCoverageAudit` shape. A disagreement
        // is worth knowing and is not by itself a defect in the reader's code: it is two analyses
        // of one access question reaching different answers, usually because the manifest predates
        // a move. Per-row it would flood any stale `.pbt/` directory. Silent, it would be the drift
        // that let 316 seeds name uncallable functions for a whole cycle before anyone noticed.
        if !disagreements.isEmpty {
            diagnostic(
                "note: the seed manifest names a different access blocker than this scan found for "
                    + "\(disagreements.count) function(s) "
                    + "(\(disagreements.sorted().joined(separator: ", "))). This scan's reading was "
                    + "kept — see `AccessRestriction.reconciled(with:)` for why only one direction "
                    + "is arbitrated. The usual cause is a manifest generated before the code moved."
            )
        }
        return updated
    }

    /// `(basename, symbol) -> restriction`, over the seeds that carry one.
    ///
    /// Seeds without a restriction are skipped rather than mapped to `nil`: the producer classifies
    /// only `restricted-function` seeds, so an absent field is "not asked", and an entry claiming
    /// otherwise would make every `pure-function` seed look like an opinion about access.
    static func restrictionIndex(from manifest: SeedManifest) -> [String: SeedRestriction] {
        var index: [String: SeedRestriction] = [:]
        for seed in manifest.seeds {
            guard let restriction = seed.restriction else { continue }
            // First writer wins. Two seeds for one `(file, symbol)` come from one analysis of one
            // function — overloads share a base name — so the answers agree; when a lossy join does
            // collide, keeping the first makes the result independent of manifest order, which the
            // byte-comparability of diagnostics depends on.
            index[joinKey(file: seed.file, symbol: seed.symbol)] = index[
                joinKey(file: seed.file, symbol: seed.symbol)
            ] ?? restriction
        }
        return index
    }

    static func joinKey(file: String, symbol: String) -> String {
        "\(URL(fileURLWithPath: file).lastPathComponent)::\(symbol)"
    }
}
