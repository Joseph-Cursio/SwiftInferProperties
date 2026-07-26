import Foundation
import SwiftInferCore

// Extracted from `StrategistDispatchEmitter.swift` to keep that file under
// the `file_length` cap. Holds the stub's header-comment composer and the
// multi-line commenting helper the self-dogfood road test added — see
// `commented(_:label:)` for the bug it fixes.
extension StrategistDispatchEmitter {

    /// Header comment block — names the strategist source, the chosen
    /// strategy summary, and the template under test.
    static func headerSection(inputs: Inputs, recipe: GeneratorRecipe) -> String {
        """
        // V1.47.E — strategist-routed verify stub.
        // Template: \(inputs.template)
        // Carrier:  \(inputs.carrier) (bound to \(recipe.carrierTypeName))
        \(commented(recipe.expression, label: "Generator expression: "))
        // Single-pass — integral/string carriers have no NaN/Inf semantic.
        """
    }

    /// Comment out **every** line of `text`, not just the first.
    ///
    /// A derived-composite recipe for a struct with several stored properties
    /// is emitted across several lines. Interpolating it after a single `//`
    /// commented the first line and left the rest as bare top-level code, so
    /// the stub failed to parse — `consecutive statements on a line must be
    /// separated by ';'` at line 5, pointing at a *comment*.
    ///
    /// Found by the self-dogfood road test (`docs/roadtest-self-dogfood.md` §9),
    /// and it had stayed hidden because every carrier in the frozen
    /// cycle27-surface corpus derives a single-line recipe. The first
    /// multi-property struct to reach this path is the first one that breaks.
    private static func commented(_ text: String, label: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines
            .enumerated()
            .map { index, line in
                "// " + (index == 0 ? label : "") + line.trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
    }
}
