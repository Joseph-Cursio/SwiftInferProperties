import Foundation
import SwiftInferCore

/// V1.147 — the confidence *anchor*: connects a discovered candidate to the
/// proven standard-library truth (or trap) it resembles, as explainability
/// provenance. When a candidate's `(template family, stdlib carrier)` matches
/// the known-properties catalog, a matching **law** becomes a "why suggested"
/// line (a proven analog) and a matching **caveat** becomes a "why this might
/// be wrong" line (a proven counter-example).
///
/// It deliberately adds NO score: the scoring engine already covers the
/// caveats (`antiCommutativityNaming`, `floatingPointStorage`), and a carrier
/// match is suggestive, not proof — a boost would risk the "shared shape ≠
/// shared purpose" false positive. The value here is provenance the engine
/// doesn't cite by name. The `Set` commutativity case shows why both halves
/// matter: `Set.union` is commutative (analog) but `Set.subtracting` is not
/// (trap), so the candidate gets both lines and the reader sees the ambiguity.
enum StdlibAnchor {

    /// Extra explainability lines for `(templateName, carrier)`, or empty when
    /// the carrier isn't a catalogued stdlib type. Fires only for the bare
    /// stdlib carriers, so custom-type suggestions are untouched.
    static func provenance(
        templateName: String,
        carrier: String?
    ) -> (whySuggested: [String], whyMightBeWrong: [String]) {
        guard let carrier, !carrier.isEmpty else { return ([], []) }
        let type = catalogType(carrier)
        var whySuggested: [String] = []
        var whyMightBeWrong: [String] = []
        for entry in StandardLibraryProperties.all
        where entry.template == templateName && entry.type == type {
            switch entry.kind {
            case .law:
                let proto = entry.witnesses.map { " (SwiftPropertyLaws `\($0)`)" } ?? ""
                whySuggested.append(
                    "Proven analog: `\(type)` satisfies `\(entry.statement)` — \(entry.structure)\(proto)."
                )

            case .caveat:
                let detail = entry.note.map { " (\($0))" } ?? ""
                whyMightBeWrong.append(
                    "Known counter-example on `\(type)`: \(entry.statement)\(detail)"
                )
            }
        }
        return (whySuggested, whyMightBeWrong)
    }

    /// A copy of `suggestion` with any stdlib provenance appended to its
    /// explainability (unchanged when there's no catalog match). Considers
    /// BOTH the enclosing-type carrier and the generator carrier — a static
    /// `(Set, Set) -> Set` on `enum Ops` carries `Ops` but is *about* `Set`.
    static func enriched(_ suggestion: Suggestion) -> Suggestion {
        // The operand type of a `(T, T) -> T` pick lives in the evidence
        // signature (T), not the carrier (the enclosing type). Consider all
        // three sources.
        let carriers = [
            suggestion.carrier,
            suggestion.carrierTypeName,
            suggestion.evidence.first.flatMap { firstParameterType(from: $0.signature) }
        ].compactMap(\.self)
        var why: [String] = []
        var wrong: [String] = []
        var seenTypes: Set<String> = []
        for carrier in carriers
        where seenTypes.insert(catalogType(carrier)).inserted {
            let (whyLines, wrongLines) = provenance(
                templateName: suggestion.templateName,
                carrier: carrier
            )
            why += whyLines
            wrong += wrongLines
        }
        guard !why.isEmpty || !wrong.isEmpty else { return suggestion }
        return suggestion.withExplainability(
            ExplainabilityBlock(
                whySuggested: suggestion.explainability.whySuggested + why,
                whyMightBeWrong: suggestion.explainability.whyMightBeWrong + wrong
            )
        )
    }

    /// The first parameter type from a `(A, B) -> R` signature — e.g.
    /// `"(Set<Int>, Set<Int>) -> Set<Int>"` → `"Set<Int>"`. Depth-aware so
    /// generics / nested collections don't split early.
    static func firstParameterType(from signature: String) -> String? {
        guard let open = signature.firstIndex(of: "(") else { return nil }
        var depth = 0
        var result = ""
        var index = signature.index(after: open)
        while index < signature.endIndex {
            let char = signature[index]
            if char == "(" || char == "<" || char == "[" {
                depth += 1
                result.append(char)
            } else if char == ")" || char == "]" || char == ">" {
                if char == ")", depth == 0 { break }
                depth -= 1
                result.append(char)
            } else if char == ",", depth == 0 {
                break
            } else {
                result.append(char)
            }
            index = signature.index(after: index)
        }
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Normalize a carrier to a catalog type name: `[Int]` → `Array` (array
    /// syntax, no `:`), `Set<Tag>` → `Set` (strip generics), else unchanged.
    private static func catalogType(_ name: String) -> String {
        if name.hasPrefix("["), name.contains("]"), !name.contains(":") {
            return "Array"
        }
        if let openAngle = name.firstIndex(of: "<") {
            return String(name[..<openAngle])
        }
        return name
    }
}
