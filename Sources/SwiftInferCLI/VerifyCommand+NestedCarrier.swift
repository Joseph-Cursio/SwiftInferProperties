import Foundation
import SwiftInferCore

extension SwiftInferCommand.Verify {

    /// Rewrite a bare carrier name to its **qualified lexical path** when the module declares
    /// exactly one type by that name and it is nested.
    ///
    /// ## The defect
    ///
    /// A stub that writes `Finding` for a type declared as `ProtocolCoverageAudit.Finding`
    /// does not compile — *cannot find type 'Finding' in scope* — and the pick lands in
    /// `Inconclusive: build-failed`, which reads as a tooling error rather than as the
    /// name-resolution problem it is.
    ///
    /// `resolveFunctionCalls` has qualified the **call-site owner** since 2026-08-05
    /// (`entry.qualifiedTypeName ?? carrier`, the fix for `Scaffold` →
    /// `SwiftInferCommand.Scaffold`). The **generator carrier** — the type whose `gen()` is
    /// derived and whose name the stub writes as a type reference — was never given the same
    /// treatment. Those are different types in general: `lawTotal(for:)` is declared on
    /// `ProtocolCoverageAudit` and quantifies over `Finding`.
    ///
    /// ## Why this needs no new index column
    ///
    /// `allShapes` is already threaded to this call site, and `TypeShapeBuilder` groups it by
    /// **`TypeDecl.qualifiedName`** — so the map's keys are the very paths a stub must write.
    /// Resolution is a lookup, not a re-scan, and the fix costs one dictionary pass.
    ///
    /// ## Never guess
    ///
    /// Three rules, and the last two matter more than the first:
    ///
    /// 1. A name that is **already a key** is returned untouched — it is top-level, or the
    ///    caller already qualified it.
    /// 2. A name matching the last component of **exactly one** key is rewritten to that key.
    /// 3. **Zero or several matches fall back to the bare name**, which is today's behaviour.
    ///    Two types called `Finding` in different parents give no way to choose, and a wrong
    ///    qualification fails to compile just as surely as no qualification — while being
    ///    harder to read. Ambiguity keeps the status quo rather than picking.
    ///
    /// Generic and optional spellings are left alone: `[Finding]`, `Finding?` and
    /// `Box<Finding>` are shapes the strategist composes, not names to look up, and rewriting
    /// the outer spelling would corrupt them.
    ///
    /// Measured (`docs/measurements/roadtest-self-dogfood-2026-08-08.md` §8.3.3): against the
    /// kit at `0720714` this class held **4** of the survey's 10 `Inconclusive` picks, up from
    /// 2, because every carrier the kit newly learned to generate arrived here bare.
    static func qualifyingNestedCarrier(
        _ carrier: String,
        in allShapes: [String: IndexedTypeShape]
    ) -> String {
        guard !carrier.isEmpty, allShapes[carrier] == nil else { return carrier }
        // A composed spelling is not a name. Bail before the scan rather than after, so a
        // `[Finding]` can never be rewritten to `[ProtocolCoverageAudit.Finding` by a
        // suffix match on its last component.
        guard carrier.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }) else {
            return carrier
        }
        let matches = allShapes.keys.filter { key in
            key.hasSuffix(".\(carrier)")
        }
        guard matches.count == 1, let qualified = matches.first else { return carrier }
        return qualified
    }
}
