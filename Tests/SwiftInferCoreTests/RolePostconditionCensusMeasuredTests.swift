import Foundation
import Testing

@testable import SwiftInferCore

/// **Which ROLES have a postcondition the catalogue can supply without discovering it?**
///
/// `postcondition-law-declined.md` declined two routes, and both tried to **discover** the
/// predicate — pairing it by name (~5 genuine) or reading it from a body guard (~13, nine
/// of them one file). Neither is how the one postcondition template that already works
/// finds its predicate.
///
/// **`measure-non-negativity` does not discover `>= 0`.** It recognises a *role* —
/// `count` / `size` / `magnitude` — and the catalogue supplies the law. It has **401 rows
/// across the 17 corpora**, among the largest in the catalogue. The pattern that works is:
/// Measured at the **17** corpora resolving then; `CorpusManifest` resolves **20** since
/// 2026-08-23 and this has NOT been re-taken — `docs/measurements/census-universe-17-to-20.md`.
///
/// > role recognised by name → predicate supplied by the catalogue → asserted on the output
///
/// That sidesteps both declines. No pairing, no guard-reading, and no
/// control-versus-postcondition ambiguity, because the template *writes* the check.
///
/// This census asks the only remaining question: **do the other such roles have
/// populations?** It is name-and-signature only — no body parsing — so it is cheap and
/// directly comparable to `measure`'s 401.
///
/// ## What it deliberately does not claim
///
/// A name match is a **candidate**, not a law. `sorted` on a type whose order is not the
/// obvious one, or a `trimmed` that trims something other than whitespace, would be a
/// false positive. **This measures population, and precision is a separate question** —
/// the mistake `parameter-role` made was reading a population as a precision.
@Suite("Census — roles whose postcondition the catalogue can supply", .serialized)
struct RolePostconditionCensusMeasuredTests {

    /// Role → the law the catalogue would supply. Each is a property of the OUTPUT that a
    /// template can assert without finding anything in the subject's code.
    static let roles: [(name: String, law: String)] = [
        ("sorted", "isSorted(result)"),
        ("trimmed", "result has no leading/trailing whitespace"),
        ("trimming", "result has no leading/trailing whitespace"),
        ("lowercased", "result contains no uppercase"),
        ("uppercased", "result contains no lowercase"),
        ("deduplicated", "result contains no duplicates"),
        ("uniqued", "result contains no duplicates"),
        ("clamped", "result lies within the bound"),
        ("rounded", "result is integral"),
        ("normalized", "result is in normal form"),
        ("canonicalized", "result is canonical"),
        ("escaped", "result contains no unescaped occurrence"),
        ("unescaped", "result contains no escape sequence"),
        ("reversed", "result.count == input.count"),
        ("shuffled", "result is a permutation of the input")
    ]

    struct Hit {
        let corpus: String
        let container: String
        let function: String
        let role: String
        /// **The name IS the role**, so the catalogue's law applies unmodified.
        ///
        /// A prefix match does not qualify: `trimmingLeadingWhitespace` leads with
        /// `trimming`, and the supplied law *"no leading OR trailing whitespace"* is too
        /// strong for it — the suffix narrows what was trimmed. Same for
        /// `trimmingTrailingWhitespace` and `trimmingSuperfluousNewlines`, which trims
        /// newlines rather than whitespace. **The suffix modifies the law, and a
        /// catalogue that ignores it supplies a FALSE postcondition** — which would be a
        /// refutation of correct code, the worst failure this tool has.
        var isExact: Bool { function.lowercased() == role }
    }

    /// The leading camelCase word of a name — `sortedKeys` leads with `sorted`.
    static func leadingWord(_ name: String) -> String {
        var word = ""
        for character in name {
            if character.isUppercase, !word.isEmpty { break }
            word.append(character)
        }
        return word.lowercased()
    }

    static let hits: [Hit] = {
        let roleNames = Set(roles.map(\.name))
        var found: [Hit] = []
        for corpus in CorpusManifest.available {
            guard let scanned = try? FunctionScanner.scanCorpus(directory: corpus.primaryRoot)
            else { continue }
            for summary in scanned.summaries {
                // A postcondition needs something to assert about, so a `Void` return is out.
                guard let returnType = summary.returnTypeText, returnType != "Void", returnType != "()"
                else { continue }
                let word = leadingWord(summary.name)
                guard roleNames.contains(word) else { continue }
                found.append(
                    Hit(
                        corpus: corpus.id,
                        container: summary.containingTypeName ?? "(free)",
                        function: summary.name,
                        role: word
                    )
                )
            }
        }
        return found
    }()

    /// **The instrument fires**, asserted on names rather than on a corpus — a role table
    /// that matched nothing would report the same zero as an absent population.
    @Test("the role matcher fires on the leading camelCase word")
    func matcherFires() {
        #expect(Self.leadingWord("sortedKeys") == "sorted")
        #expect(Self.leadingWord("trimmingCharacters") == "trimming")
        #expect(Self.leadingWord("resorted") == "resorted", "a role must LEAD the name, not appear in it")
        #expect(Self.leadingWord("normalized") == "normalized")
    }

    @Test("the census scans the corpora the manifest resolves")
    func universeIsTheManifest() {
        #expect(CorpusManifest.available.count >= 8)
    }

    @Test("census — catalogue-supplied postcondition roles")
    func census() {
        var byRole: [String: Int] = [:]
        for hit in Self.hits { byRole[hit.role, default: 0] += 1 }
        var byCorpus: [String: Int] = [:]
        for hit in Self.hits { byCorpus[hit.corpus, default: 0] += 1 }
        // Concentration is what declined the body-guard route: nine of thirteen in one
        // file. So it is reported here rather than discovered later.
        var byContainer: [String: Int] = [:]
        for hit in Self.hits { byContainer["\(hit.corpus):\(hit.container)", default: 0] += 1 }

        var lines: [String] = ["", "CATALOGUE-SUPPLIED POSTCONDITION ROLES — ALL MANIFEST CORPORA", ""]
        let exact = Self.hits.filter(\.isExact)
        lines.append("total candidate sites: \(Self.hits.count)")
        lines.append("of those EXACT-name matches, where the supplied law applies unmodified: \(exact.count)")
        lines.append("prefix matches, where the SUFFIX narrows the law: \(Self.hits.count - exact.count)")
        lines.append("comparator: measure-non-negativity, the postcondition template that works, has 401")
        lines.append("")
        var exactByRole: [String: Int] = [:]
        for hit in exact { exactByRole[hit.role, default: 0] += 1 }
        lines.append("by role — count / EXACT — the law is supplied, not discovered:")
        for (role, law) in Self.roles {
            let count = byRole[role] ?? 0
            guard count > 0 else { continue }
            let tally = String(count).padding(toLength: 6, withPad: " ", startingAt: 0)
            let exactTally = String(exactByRole[role] ?? 0).padding(toLength: 6, withPad: " ", startingAt: 0)
            lines.append("  \(tally)\(exactTally)\(role.padding(toLength: 16, withPad: " ", startingAt: 0))\(law)")
        }
        let silent = Self.roles.filter { (byRole[$0.name] ?? 0) == 0 }.map(\.name)
        lines.append("  (no sites: \(silent.joined(separator: ", ")))")
        lines.append("")
        lines.append("by corpus:")
        for (corpus, count) in byCorpus.sorted(by: { $0.value > $1.value }) {
            lines.append("  \(count)  \(corpus)")
        }
        lines.append("")
        lines.append("CONCENTRATION — top containers (the body-guard route died here):")
        for (container, count) in byContainer.sorted(by: { $0.value > $1.value }).prefix(8) {
            lines.append("  \(count)  \(container)")
        }
        lines.append("")
        lines.append("sample:")
        for hit in Self.hits.prefix(20) {
            lines.append("  [\(hit.corpus)] \(hit.container).\(hit.function)  → \(hit.role)")
        }
        print(lines.joined(separator: "\n"))
    }
}
