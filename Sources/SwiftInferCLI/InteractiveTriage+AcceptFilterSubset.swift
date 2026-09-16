import Foundation
import PropertyLawCore
import SwiftInferCore
import SwiftInferTemplates

/// The accept-path arm for `filter-subset`: a named filter owes `result ⊆ haystack` (#476, #468).
///
/// Its own file, like `+AcceptComparator`, because its **generator** choice is its own: every other
/// entailed arm draws one value per argument, and this one has to draw a *collection* for at least
/// one of them. Asking the resolver for `[Violation]` answers `.todo` — the type universe holds a
/// shape called `Violation` and none called `[Violation]` — so an array argument is resolved at its
/// element and wrapped, which is the idiom the algebraic composers already use.
///
/// The corpus funnel census declined 13 of these, and #476 blocked the writer on the classification
/// question that file's gate now settles: the law is **entailed**, so the stub header says a correct
/// implementation cannot fail it, and a reader who sees it go red has found something.
extension InteractiveTriage {

    /// A subset stub for a named filter, or `nil` when the row cannot be spelled.
    ///
    /// The haystack is the parameter whose type the template recorded as the carrier —
    /// `FilterSubsetTemplate` sets `carrierType` to exactly that, so this reads the template's own
    /// answer rather than re-deriving the rule and drifting from it.
    static func filterSubsetStub(
        for suggestion: Suggestion,
        customGenerator: ((String) -> String?)?
    ) -> String? {
        guard let evidence = suggestion.evidence.first,
              let callee = CalleeReference(evidence: evidence),
              let argumentTypes = arityFreeArgumentTypes(callee: callee, evidence: evidence),
              let haystackType = suggestion.carrierTypeName,
              let haystackIndex = haystackArgumentIndex(
                  of: haystackType, among: argumentTypes, isInstanceMethod: callee.isInstanceMethod
              ),
              filterSubsetDeclineReason(haystackType: haystackType) == nil else {
            return nil
        }
        let element = FilterSubsetTemplate.arrayElement(of: haystackType)
        return LiftedTestEmitter.filterSubset(
            LiftedTestEmitter.FilterSubsetCall(
                callee: callee,
                generators: argumentTypes.map {
                    subsetGenerator(for: $0, suggestion: suggestion, customGenerator: customGenerator)
                },
                haystackIndex: haystackIndex,
                conformanceIsUnverified: element.map { equatableEvidence(of: $0) != .equatable } ?? true
            ),
            seed: SamplingSeed.derive(from: suggestion.identity)
        )
    }

    /// Why a filter's subset law cannot be written, or `nil` when it can.
    ///
    /// **One reason, and it is the only one with clear evidence behind it.** The check is
    /// `selected.allSatisfy { haystack.contains($0) }`, so the element needs `==`. A function type,
    /// `Any`, `AnyObject` or an existential cannot host value equality at all, and `[any Rule]`
    /// would emit a file that cannot compile for a reason the reader would have to work out.
    ///
    /// ⚠ **This is the corpus-INDEPENDENT half of `EquatableResolver` and nothing more.** The
    /// resolver is built over an empty declaration list on purpose: the accept context carries
    /// `TypeShape`s rather than `TypeDecl`s, so the corpus-derived arm has nothing to read, and
    /// the curated-shape veto is the part that needs no corpus. A project type therefore reads
    /// `.unknown`, which emits — the caveat-don't-drop posture `EquatableResolver`'s own header
    /// records, and the reason the stub carries a line saying the conformance was not checked.
    static func filterSubsetDeclineReason(haystackType: String) -> String? {
        guard let element = FilterSubsetTemplate.arrayElement(of: haystackType) else {
            return "the carrier `\(haystackType)` is not a collection spelling, so there is nothing "
                + "for the result to be a subset of"
        }
        guard equatableEvidence(of: element) != .notEquatable else {
            return "`\(element)` cannot host value equality — a function type, `Any`, `AnyObject` or "
                + "an existential — so `contains` cannot be spelled over it"
        }
        return nil
    }

    /// Where the haystack sits among the arguments the call needs, shifted past the receiver for an
    /// instance method.
    ///
    /// `nil` when no argument carries the carrier's type, which should not happen for a row the
    /// template produced and is declined rather than guessed at: picking the wrong argument would
    /// emit a law about the wrong collection, and it would pass.
    static func haystackArgumentIndex(
        of haystackType: String,
        among argumentTypes: [String],
        isInstanceMethod: Bool
    ) -> Int? {
        let parameterOffset = isInstanceMethod ? 1 : 0
        guard argumentTypes.count > parameterOffset else { return nil }
        return argumentTypes.indices
            .dropFirst(parameterOffset)
            .first { argumentTypes[$0] == haystackType }
    }

    /// The generator for one argument of a filter call.
    ///
    /// A collection argument is resolved at its **element** and wrapped in the kit's `.array(of:)`;
    /// anything else goes through `chooseGenerator` unchanged. Applied to every array argument and
    /// not only the haystack, because a filter's other arguments are collections just as often —
    /// `filterViolations([Violation], batch: [URL], workspacePath: URL)` is the census's own shape —
    /// and resolving one of them at its element while the rest fall to `.todo` would be arbitrary.
    private static func subsetGenerator(
        for typeName: String,
        suggestion: Suggestion,
        customGenerator: ((String) -> String?)?
    ) -> String {
        guard let element = FilterSubsetTemplate.arrayElement(of: typeName) else {
            return chooseGenerator(for: suggestion, typeName: typeName, customGenerator: customGenerator)
        }
        return LiftedTestEmitter.arrayDraw(
            over: chooseGenerator(for: suggestion, typeName: element, customGenerator: customGenerator)
        )
    }

    /// `EquatableResolver`'s verdict over no corpus — see `filterSubsetDeclineReason`.
    private static func equatableEvidence(of typeName: String) -> EquatableEvidence {
        EquatableResolver(typeDecls: []).classify(typeText: typeName)
    }
}
