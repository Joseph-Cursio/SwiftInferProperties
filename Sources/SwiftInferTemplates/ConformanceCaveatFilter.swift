import SwiftInferCore

/// Drops the "T must conform to Equatable" caveat from suggestions whose carrier the corpus
/// **proves** conforms.
///
/// ## Why a post-pass rather than fifteen edits
///
/// The caveat is emitted by fifteen templates, and it is right most of the time: for a corpus type
/// the tool has not seen declare a conformance, "confirm before applying" is honest. It is noise
/// when the suggestion has already resolved the carrier to `String` in its own signal line
/// (`Type-symmetry signature: T -> T (T = String)`) and then asks the reader to go and check
/// whether `String` is `Equatable`.
///
/// The knowledge needed to tell those apart is `EquatableResolver`, which is built from the scanned
/// `TypeDecl`s and therefore cannot exist inside a template's static `Constraint`. Threading it into
/// fifteen caveat builders would mean fifteen signature changes and fifteen chances to diverge;
/// applying it once, here, is the same shape as `GeneratorSelection.apply` and keeps the rule in one
/// place.
///
/// ## Why `EquatableResolver` rather than a list of stdlib names
///
/// A hardcoded list was written first and thrown away. It answered only for `String`, `Int` and
/// friends, while the resolver already folds every corpus `TypeDecl` — so `struct Rule: Hashable`
/// declared anywhere in the project, or conformance added by `extension Rule: Equatable` in a
/// *different file*, lifts to `.equatable` too. The capability existed; duplicating a worse version
/// of it would have left the caveat firing on exactly the first-party types an adopter cares most
/// about.
///
/// ## What it deliberately does not do
///
/// Only `.equatable` suppresses. `.unknown` keeps the caveat, which is the whole point of the
/// resolver's three-valued answer: generics, tuples and conditional conformances land there, and
/// for those the reader really does have to check. `.notEquatable` also keeps it — a suggestion
/// whose carrier is provably non-Equatable has a bigger problem than a caveat, and silencing the
/// warning would be the wrong way to surface it.
public enum ConformanceCaveatFilter {

    /// Openings of the conformance caveats the templates emit. Matched on a prefix rather than the
    /// whole sentence so a reworded tail does not silently stop matching — the failure mode would
    /// be invisible, since the caveat would simply keep appearing.
    static let caveatOpenings: [String] = [
        "T must conform to Equatable",
        "X must conform to Equatable",
        "The element type must be Equatable",
        "The element type must be Hashable"
    ]

    /// Whether `caveat` is one of the conformance caveats this filter governs.
    static func isConformanceCaveat(_ caveat: String) -> Bool {
        caveatOpenings.contains { caveat.hasPrefix($0) }
    }

    /// Strip the conformance caveat from every suggestion whose carrier type the resolver proves
    /// `Equatable`.
    ///
    /// - Parameter carrierTypeByIdentity: the resolved carrier per suggestion — the same map
    ///   `GeneratorSelection` uses, so the two passes cannot disagree about what a suggestion is
    ///   *about*.
    public static func apply(
        to suggestions: [Suggestion],
        resolver: EquatableResolver,
        carrierTypeByIdentity: [SuggestionIdentity: String]
    ) -> [Suggestion] {
        suggestions.map { suggestion in
            guard let carrier = carrierTypeByIdentity[suggestion.identity]
                ?? suggestion.carrierTypeName
                ?? suggestion.carrier,
                resolver.classify(typeText: carrier) == .equatable else {
                return suggestion
            }
            let kept = suggestion.explainability.whyMightBeWrong.filter { isConformanceCaveat($0) == false }
            guard kept.count != suggestion.explainability.whyMightBeWrong.count else { return suggestion }

            var updated = suggestion
            updated.explainability = ExplainabilityBlock(
                whySuggested: suggestion.explainability.whySuggested,
                whyMightBeWrong: kept
            )
            return updated
        }
    }
}
