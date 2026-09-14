import Foundation
import SwiftInferCore
import SwiftParser
import SwiftSyntax
import Testing

/// **How often are a law's counterexamples a handful of literals the generator cannot reach?**
///
/// #453: `mimeType_idempotence` was emitted, compiled, ran 100 trials and **passed**, and the
/// law is false. The subject is a four-arm switch whose counterexamples are exactly
/// `{css, js, woff2}`; everything else lands on the default where the law holds trivially, and
/// a generator drawing alphanumerics will never produce the literal `"css"`.
///
/// That is worse than the vacuity this walk already records — a vacuous test tells the reader
/// nothing, this one tells them something untrue, and it is indistinguishable from a real pass
/// in every count the pipeline reports.
///
/// ## What this census decides
///
/// #453's first candidate direction is to seed the generator from the subject's **own string
/// literals**, which would have found this in one trial. That is the obvious fix, and this walk
/// has twice measured an obvious fix as far smaller than it looked — parameterised idempotence
/// at 1 602 sites was **6** through its gate, and a removal-verb generator was **16** functions
/// in 32 369. **So the population comes before the build.**
///
/// ## What is counted, and why the denominator is narrow
///
/// The denominator is `(String) -> String` — the shape `idempotence` fires on, and the shape
/// the defect appeared in. Widening it to every law-carrying function would inflate the
/// numerator with subjects whose laws are not literal-sensitive.
///
/// The numerator is a body that **branches on its own parameter against string literals**: a
/// `switch` over the parameter (or a method call on it) with string-literal cases, or an `==`
/// against a literal. That is the shape whose witness set is closed and small.
///
/// ⚠ **A floor.** The scan does not resolve types, follow calls, or see literals reached
/// through a helper. Under-counting makes the direction look like a worse investment, which is
/// the safe direction for a build decision.
@Suite("Census — are a law's counterexamples hiding in the subject's own literals?", .serialized)
struct LiteralWitnessCensusMeasuredTests {

    /// A named type rather than a 3-tuple: SwiftLint's `large_tuple` is right that three
    /// positional fields stop being readable at the call site.
    struct Finding {
        let corpus: String
        let name: String
        let literals: Int
    }

    static let excludedDirectories = [".build", ".git", "checkouts", ".swiftinfer"]

    static func isExcluded(_ url: URL) -> Bool {
        url.pathComponents.contains { Self.excludedDirectories.contains($0) }
    }

    /// Collects string literals that a function's body tests its own parameter against.
    private final class LiteralWitnessVisitor: SyntaxVisitor {
        let parameterNames: Set<String>
        var literals: Set<String> = []
        var branchesOnParameter = false

        init(parameterNames: Set<String>) {
            self.parameterNames = parameterNames
            super.init(viewMode: .sourceAccurate)
        }

        /// `switch ext.lowercased() { case "css": … }` — the measured shape.
        override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
            guard mentionsParameter(node.subject) else { return .visitChildren }
            for caseItem in node.cases {
                guard let switchCase = caseItem.as(SwitchCaseSyntax.self),
                      let label = switchCase.label.as(SwitchCaseLabelSyntax.self) else { continue }
                for item in label.caseItems {
                    if let literal = item.pattern.as(ExpressionPatternSyntax.self)?
                        .expression.as(StringLiteralExprSyntax.self) {
                        literals.insert(literal.segments.description)
                        branchesOnParameter = true
                    }
                }
            }
            return .visitChildren
        }

        /// `if ext == "css"` and its `!=` twin.
        ///
        /// **Matched on `SequenceExprSyntax`, not `InfixOperatorExprSyntax`.** SwiftSyntax only
        /// folds a binary expression into the infix form when an operator table is supplied, and
        /// a plain `Parser.parse` supplies none — so `value == "legacy"` arrives as a flat
        /// sequence of `[ref, ==, literal]`. The first version of this visitor matched the folded
        /// form, fired **zero times**, and the census it fed would have reported a population of
        /// switches while claiming to count equality too. The control caught it.
        override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
            let elements = Array(node.elements)
            guard elements.count >= 3 else { return .visitChildren }
            for (index, element) in elements.enumerated() {
                guard let symbol = element.as(BinaryOperatorExprSyntax.self)?.operator.text,
                      symbol == "==" || symbol == "!=",
                      index > 0, index + 1 < elements.count
                else { continue }
                let sides = [elements[index - 1], elements[index + 1]]
                guard sides.contains(where: mentionsParameter) else { continue }
                for side in sides {
                    if let literal = side.as(StringLiteralExprSyntax.self) {
                        literals.insert(literal.segments.description)
                        branchesOnParameter = true
                    }
                }
            }
            return .visitChildren
        }

        private func mentionsParameter(_ expression: some SyntaxProtocol) -> Bool {
            expression.description
                .split { !$0.isLetter && !$0.isNumber && $0 != "_" }
                .contains { parameterNames.contains(String($0)) }
        }
    }

    private final class FunctionCollector: SyntaxVisitor {
        var findings: [(name: String, literals: Int)] = []
        var stringToString = 0

        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            let params = node.signature.parameterClause.parameters
            let returns = node.signature.returnClause?.type.trimmedDescription
            guard params.count == 1,
                  params.first?.type.trimmedDescription == "String",
                  returns == "String",
                  let body = node.body
            else { return .visitChildren }
            stringToString += 1

            var names: Set<String> = []
            if let first = params.first {
                names.insert(first.secondName?.text ?? first.firstName.text)
            }
            let visitor = LiteralWitnessVisitor(parameterNames: names)
            visitor.walk(body)
            if visitor.branchesOnParameter, !visitor.literals.isEmpty {
                findings.append((node.name.text, visitor.literals.count))
            }
            return .visitChildren
        }
    }

    /// **The positive control, and it is not optional.** A census that reports zero without one
    /// is the "confident zero" this repo has recorded repeatedly: a broken detector and an empty
    /// population are the same number. This is `KaTeXSchemeHandler.mimeType(forExtension:)`
    /// verbatim — the subject of #453, whose law is false and whose witness set is
    /// `{css, js, woff2}`.
    @Test func theDetectorFindsTheKnownWitness() {
        let source = """
        enum Handler {
            static func mimeType(forExtension ext: String) -> String {
                switch ext.lowercased() {
                case "css": "text/css"
                case "js": "text/javascript"
                case "woff2": "font/woff2"
                default: "application/octet-stream"
                }
            }
        }
        """
        let collector = FunctionCollector(viewMode: .sourceAccurate)
        collector.walk(Parser.parse(source: source))
        #expect(collector.stringToString == 1, "the denominator must see this function")
        #expect(collector.findings.count == 1, "the detector must find the known witness")
        #expect(collector.findings.first?.literals == 3, "witness set is {css, js, woff2}")
    }

    /// The `==` arm, which the switch arm does not cover.
    @Test func theDetectorFindsAnEqualityComparison() {
        let source = """
        func normalise(_ value: String) -> String {
            if value == "legacy" { return "modern" }
            return value
        }
        """
        let collector = FunctionCollector(viewMode: .sourceAccurate)
        collector.walk(Parser.parse(source: source))
        #expect(collector.findings.count == 1)
    }

    /// **The negative control.** A function that switches on something *other* than its
    /// parameter is not this shape, and counting it would inflate the numerator.
    @Test func aSwitchOnSomethingElseIsNotCounted() {
        let source = """
        func render(_ value: String) -> String {
            switch Locale.current.identifier {
            case "en_US": return value.uppercased()
            default: return value
            }
        }
        """
        let collector = FunctionCollector(viewMode: .sourceAccurate)
        collector.walk(Parser.parse(source: source))
        #expect(collector.stringToString == 1)
        #expect(collector.findings.isEmpty, "the switch subject is not the parameter")
    }

    @Test("size the literal-witness shape across the manifest corpora")
    func censusLiteralWitnesses() {
        var totalStringToString = 0
        var findings: [Finding] = []
        var scanned: [String] = []

        for corpus in CorpusManifest.available {
            scanned.append(corpus.id)
            let files = FileManager.default
                .enumerator(at: corpus.primaryRoot, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" && !Self.isExcluded($0) } ?? []
            for file in files {
                guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
                let collector = FunctionCollector(viewMode: .sourceAccurate)
                collector.walk(Parser.parse(source: source))
                totalStringToString += collector.stringToString
                for found in collector.findings {
                    findings.append(Finding(corpus: corpus.id, name: found.name, literals: found.literals))
                }
            }
        }

        let share = totalStringToString == 0 ? 0.0
            : Double(findings.count) / Double(totalStringToString) * 100
        print("\n=== LITERAL-WITNESS CENSUS (#453) ===")
        print("corpora scanned: \(scanned.count)")
        print("(String) -> String functions      : \(totalStringToString)")
        print("…branching on their own literals  : \(findings.count)  (\(String(format: "%.1f", share))%)")
        if findings.isEmpty == false {
            let sizes = findings.map(\.literals).sorted()
            let median = sizes[sizes.count / 2]
            print("witness-set size — min \(sizes.first ?? 0), median \(median), max \(sizes.last ?? 0)")
            print("examples:")
            for found in findings.prefix(12) {
                print("   \(found.corpus): \(found.name) — \(found.literals) literal(s)")
            }
        }
        print("=== END CENSUS ===\n")

        #expect(
            totalStringToString > 50,
            "a census that finds almost no denominator reports a silent zero"
        )
        #expect(CorpusManifest.available.isEmpty == false)
    }
}
