import Foundation
import SwiftInferCore

/// **Do not write a stub whose law splices a bare call to a `throws` subject.**
///
/// A value law states itself by calling the subject inside the backend's `property` closure:
///
/// ```swift
/// // static func contentsURL(in: URL) throws -> URL
/// property: { (value: URL) in
///     Extractor.contentsURL(in: Extractor.contentsURL(in: value)) == Extractor.contentsURL(in: value)
/// }
/// ```
///
/// which is `call can throw, but it is not marked with 'try'`. No generator, budget or import
/// changes that — the call is simply not spelled in Swift.
///
/// ## Why a gate and not a `try?`
///
/// Several arms already handle a throwing subject: `input-totality` writes
/// `_ = try? parse(value); return true`, `determinism` compares `try? f(x)` on both sides, and
/// `replay-idempotence` takes `isThrows` to its own emitter. **The value form has no such reading
/// available for free**: `f(f(x)) == f(x)` with `try?` on the outer call alone does not type-check,
/// and threading it through the nested call asks whether a subject that throws on its own output is
/// *non-idempotent* or merely *partial* — a semantic choice the repository has not made, and one no
/// emitter should make silently.
///
/// ## ⚠ The list is of arms that ARE gated, and the polarity is the whole design
///
/// This gate was first written with an EXEMPT list — every arm gated unless named — and it
/// **withdrew a law that compiled and passed**: `SPMPackageReader.parse` under `input-totality`,
/// which spells its own `try?` and was not on the list. Measured, that arm cost SwiftUMLStudio one
/// compile and one pass.
///
/// The two polarities fail differently and the difference is not symmetric. An exempt list fails
/// by **withdrawing a working law** for an arm nobody remembered; a gated list fails by **leaving
/// a stub that does not compile**, which is exactly the state before this gate existed. One
/// regression is a loss, the other is a delay. **An arm joins this list when a stub of that arm has
/// been SEEN splicing a bare call to a throwing subject** — not when it seems like it might.
///
/// **Seven signature templates already refuse a throwing subject at admission** —
/// `ComparatorTemplate`, `FilterSubsetTemplate`, `GuardDomainTemplate`, `EquivalenceRelationTemplate`,
/// `DiffDisjointnessTemplate`, `CaseIterableMappingTemplate` and `BulkIncrementalPairing` all carry
/// `!summary.isThrows`. This gate is that same house rule applied where the rule was missing,
/// at the one place every arm passes through.
///
/// ## The posture is the availability gate's
///
/// It costs no laws: a stub that cannot be spelled was never a law. Measured on `SwiftUMLStudio`,
/// where `CoreDataModelExtractor.contentsURL` was the one row the widening rule freed into this
/// error rather than into a compile — **invisible until access stopped hiding it**, which is #499's
/// mechanism at a fourth site.
enum ThrowingSubjectGate {

    /// Arms observed splicing a bare call to the subject, so a `throws` subject cannot compile.
    ///
    /// **`idempotence` alone, because it is the only one measured doing it.** `involution` and
    /// `normal-form` state themselves the same way and are the obvious next entries — they are
    /// deliberately absent until a stub of theirs is seen failing this way, because the cost of
    /// guessing wrong here is a withdrawn law and the cost of waiting is a stub that already does
    /// not compile.
    static let armsSplicingBareCalls: Set<String> = ["idempotence"]

    /// Why no stub can be written for this suggestion, or `nil` when the subject cannot throw.
    ///
    /// Reads `throws` off the recorded signature, as every accept-path arm already does
    /// (`InteractiveTriage+Accept.swift`), and excludes `rethrows`: a `rethrows` function called
    /// with a non-throwing argument does not throw, so the call the stub writes is legal.
    static func declineReason(for suggestion: Suggestion) -> String? {
        guard armsSplicingBareCalls.contains(suggestion.templateName),
              let evidence = suggestion.evidence.first,
              throwsClause(in: evidence.signature)
        else { return nil }
        return "\(evidence.displayName) is `throws`, and a \(suggestion.templateName) law calls it "
            + "inside a property closure that cannot propagate the error"
    }

    /// `throws` in the signature's effects position, never `rethrows` and never a type named so.
    ///
    /// `FunctionSummary.inferenceSignature` renders `(String) async throws -> String`, so the
    /// effects clause is a bare word between spaces. The letter boundaries carry the whole rule:
    /// they reject `rethrows`, whose `throws` is preceded by `e`, and a parameter type spelled
    /// `ThrowsPolicy`, whose capital `T` is not this word at all.
    private static func throwsClause(in signature: String) -> Bool {
        signature.range(of: #"(?<![A-Za-z])throws(?![A-Za-z])"#, options: .regularExpression) != nil
    }
}
