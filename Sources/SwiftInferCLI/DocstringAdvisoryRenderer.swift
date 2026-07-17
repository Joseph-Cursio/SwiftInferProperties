import Foundation
import SwiftInferCore

/// Renders the "Reference definitions from docstrings" advisory block for
/// `discover --docstring-advice`.
///
/// Like `EffectAnnotationRenderer`, this is a deliberately separate renderer:
/// the advice is not a scored property-test candidate but a pairing of a
/// documented sentence with the law it defines, so it gets its own labelled
/// block beneath the suggestions.
enum DocstringAdvisoryRenderer {

    /// Returns a rendered advisory block, or the empty string when there is no
    /// advice — so callers can append unconditionally without an empty header.
    static func render(_ items: [SwiftInferCommand.Discover.DocstringAdviceItem]) -> String {
        guard !items.isEmpty else { return "" }

        var lines: [String] = []
        let noun = items.count == 1 ? "function" : "functions"
        lines.append("Reference definitions from docstrings (\(items.count) \(noun)):")
        lines.append(
            "  A property is the code checked against a definition you state in one "
                + "sentence. Where you already wrote that sentence, here it is next to "
                + "the law it defines."
        )
        for item in items {
            lines.append("")
            lines.append("  • \(item.displayName)  \(item.signature)")
            lines.append("    \(item.location.file):\(item.location.line)")
            for line in body(for: item.advisory) {
                lines.append("    \(line)")
            }
            if let scaffold = item.runnableScaffold {
                lines.append("    ── runnable reference oracle (fill the stub, then run it) ──")
                for line in scaffold.split(separator: "\n", omittingEmptySubsequences: false) {
                    lines.append("    \(line)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    /// The per-item body, tailored to which of the two shapes fired.
    private static func body(for advisory: DocstringAdvisory) -> [String] {
        switch advisory {
        case let .referenceDefinition(reference):
            let owed: String
            if reference.fromLiftedTest {
                owed = "the example test lifted for `\(reference.template)` needs the definition it "
                    + "generalizes — your docstring states one:"
            } else if reference.template == "comparator" {
                owed = "the strict-weak-ordering law checks this is a VALID ordering, but not WHICH "
                    + "one — a comparator on the wrong key passes it. Your docstring states the key:"
            } else {
                owed = "the `\(reference.template)` law openly owes a reference definition — your "
                    + "docstring states one:"
            }
            return [
                owed,
                "  \"\(reference.docComment)\"",
                "encode THAT sentence as the property; the law checks the code against it."
            ]

        case let .fallbackContract(contract):
            let preamble: String
            if contract.redHerrings.isEmpty {
                preamble = "the templates could offer only a determinism tautology here "
                    + "(f(x) == f(x), which no wrong code fails). Your docstring is the one "
                    + "refutable contract on this function:"
            } else {
                let matched = contract.redHerrings.joined(separator: ", ")
                preamble = "the templates matched \(matched) by shape, but a correct "
                    + "implementation need not satisfy them — they are guesses, not laws it is "
                    + "owed. Your docstring is the contract that IS owed:"
            }
            return [
                preamble,
                "  \"\(contract.docComment)\"",
                "encode THAT sentence; it is the law the templates could not name."
            ]
        }
    }
}
