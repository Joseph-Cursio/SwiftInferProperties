import Foundation
import SwiftInferCore

/// A numeric result whose doc comment states the range it lies in — and the law that it does.
///
/// ## Why this template exists
///
/// Measured on SwiftLintRuleStudioCore's `AnalysisProgress`:
///
/// ```swift
/// /// Fraction of files processed (0.0 to 1.0)
/// public var progress: Double {
///     guard let total = totalFiles, total > 0 else { return 0.0 }
///     return Double(filesProcessed) / Double(total)
/// }
/// ```
///
/// No test called it, and the doc comment is the only contract it has. It is also one the code
/// does not keep: nothing clamps `filesProcessed` to `totalFiles`, so the fraction exceeds 1.0
/// for any snapshot that over-counts. A guard negated by a mutant divides by zero and returns
/// NaN or infinity, which the range rejects too.
///
/// ## Not a conjecture
///
/// Every other name-read law in the catalogue guesses at intent. This one does not: the author
/// wrote the range down. A failure is either a bug in the code or a doc comment that no longer
/// describes it — and both are worth a reader's time. So it scores Likely on the docstring alone.
///
/// The bounds are read from the shapes doc comments use — `(0.0 to 1.0)`, `0...1`, `[0, 1]`,
/// `between 0 and 100`, `from 0 to 100` — and only when exactly one range is stated, with the
/// lower bound below the upper. A half-open `0..<1` states a different law and is not read.
public enum DocumentedRangeTemplate {

    public static let templateName = "documented-range"

    public static let numericCodomains: Set<String> = FixedWidthIntegerNames.signed
        .union(["UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Double", "Float", "CGFloat"])

    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: summary)
    }

    public static func makeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "documented-range",
            appliesTo: { statedRange(for: $0) != nil },
            signals: Self.signals(for:),
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(
                    canonicalInput: "documented-range|" + IdempotenceTemplate.canonicalSignature(of: summary)
                )
            },
            carrier: { $0.containingTypeName },
            carrierType: { $0.parameters.first?.typeText ?? $0.containingTypeName },
            caveats: { summary in Self.makeCaveats(for: summary) },
            match: { statedRange(for: $0).map(TemplateMatch.documentedRange) }
        )
    }

    /// The range `summary`'s doc comment states, when the shape admits the law.
    static func statedRange(for summary: FunctionSummary) -> DocumentedRange? {
        guard !summary.isMutating, !summary.isAsync, !summary.isThrows,
              let returnType = summary.returnTypeText, numericCodomains.contains(returnType),
              summary.parameters.allSatisfy({ !$0.isInout }),
              !summary.parameters.isEmpty || summary.containingTypeName != nil,
              let doc = summary.docComment else { return nil }
        return statedRange(in: doc)
    }

    private static let number = #"(-?\d+(?:\.\d+)?)"#

    private static let shapes: [String] = [
        #"\(\s*"# + number + #"\s+(?:to|through)\s+"# + number + #"\s*\)"#,
        number + #"\s*(?:\.\.\.|…)\s*"# + number,
        #"\[\s*"# + number + #"\s*,\s*"# + number + #"\s*\]"#,
        #"\bbetween\s+"# + number + #"\s+and\s+"# + number,
        #"\bfrom\s+"# + number + #"\s+(?:to|through)\s+"# + number
    ]

    /// The one range `doc` states, or `nil` for none or several.
    public static func statedRange(in doc: String) -> DocumentedRange? {
        guard !doc.contains("..<") else { return nil }
        var found: Set<[Double]> = []
        var first: DocumentedRange?
        for shape in shapes {
            guard let regex = try? NSRegularExpression(pattern: shape) else { continue }
            let range = NSRange(doc.startIndex..., in: doc)
            for match in regex.matches(in: doc, range: range) {
                guard let lowRange = Range(match.range(at: 1), in: doc),
                      let highRange = Range(match.range(at: 2), in: doc) else { continue }
                let lower = String(doc[lowRange])
                let upper = String(doc[highRange])
                guard let low = Double(lower), let high = Double(upper), low < high else { continue }
                found.insert([low, high])
                if first == nil { first = DocumentedRange(lower: lower, upper: upper) }
            }
        }
        return found.count == 1 ? first : nil
    }

    static func signals(for summary: FunctionSummary) -> [Signal] {
        guard let range = statedRange(for: summary), let returnType = summary.returnTypeText else { return [] }
        return [
            Signal(
                kind: .docstringCorroboration,
                weight: 40,
                detail: "The doc comment states the range: \(range.lower)...\(range.upper)"
            ),
            Signal(
                kind: .orderedCodomainSignature,
                weight: 20,
                detail: "Numeric result: \(summary.name) -> \(returnType)"
            )
        ]
    }

    static func makeCaveats(for summary: FunctionSummary) -> [String] {
        let range = statedRange(for: summary).map { "\($0.lower)...\($0.upper)" } ?? "the stated range"
        return [
            "THE LAW IS THE DOC COMMENT'S: the result lies in \(range). It is refutable wherever the "
                + "code does not enforce what the comment promises — an unclamped ratio, a "
                + "division whose guard can be bypassed, NaN or infinity from a zero denominator.",
            "A FAILURE IS A DISAGREEMENT, and either side may be wrong: clamp the code to the "
                + "range, or correct the comment. Inputs the type admits but callers never pass — "
                + "a count above its total — still count; if they are impossible, make the type say so."
        ]
    }
}
