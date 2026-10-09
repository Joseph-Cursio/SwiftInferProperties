import SwiftInferCore

/// The **structural-round-trip** scaffold: a parser with no printer in the code still owes
/// `parse(render(value)) == value` — with a `render` the author writes (SwiftInferProperties#646).
///
/// `normal-form` and `round-trip` both need a printer, so `parse(String) -> T` with no `T -> String`
/// anywhere gets `input-totality` alone. Totality cannot see a parser that returns the wrong
/// structure: SwiftFormatRuleStudio's `RuleInfoParser` had three surviving mutants, none of which
/// trapped, and each was killed by generating the structure, laying it out with every optional
/// separator drawn at random, and parsing it back.
///
/// ## A scaffold, for two reasons the tool cannot get around
///
/// - **The printer.** The layout `T` is read from is the author's knowledge, not the code's — the
///   point of this template is that the code has no printer.
/// - **The generator's domain.** Generating `T`'s fields independently produces values the parser
///   never produces — strings holding the format's own separators, fields that must agree — and
///   the round trip then fails on correct code. `normal-form-state-machine-writers.md` measured
///   exactly that mechanism on `SwiftFormatConfig.Line`. So the values are the author's too.
///
/// So, like `state-machine`, the stub's only live statement is an `Issue.record` with a to-do: it
/// compiles anywhere, fails until completed, and the file says SCAFFOLD rather than a law.
public enum StructuralRoundTripTemplate {

    public static func suggest(for subject: StructuralRoundTripSubject) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: subject)
    }

    public static func makeConstraint() -> Constraint<StructuralRoundTripSubject> {
        Constraint<StructuralRoundTripSubject>(
            templateName: "structural-round-trip",
            appliesTo: { _ in true },   // `candidates` already gated
            signals: { subject in
                [
                    Signal(
                        kind: .typeSymmetrySignature,
                        weight: 35,
                        detail: "\(subject.parser.name) reads text into `\(subject.structure)` and nothing in "
                            + "the code prints a `\(subject.structure)` back — so the round trip "
                            + "`parse(render(value)) == value` needs a printer you write"
                    )
                ]
            },
            evidence: { [$0.parser.inferenceEvidence] },
            identity: { subject in
                SuggestionIdentity(
                    canonicalInput: "structural-round-trip|"
                        + IdempotenceTemplate.canonicalSignature(of: subject.parser)
                )
            },
            carrier: { $0.structure },
            carrierType: { $0.structure },
            caveats: { _ in Self.makeCaveats() }
        )
    }

    static func makeCaveats() -> [String] {
        [
            "THIS IS A SCAFFOLD, NOT A LAW. The printer is yours to write, and the stub fails "
                + "(via Issue.record) until you do: the code has no printer, which is why this was "
                + "proposed.",
            "GENERATE ONLY VALUES THE PARSER CAN PRODUCE. Fields drawn independently — a string "
                + "holding the format's own separator, two fields that must agree — make the round "
                + "trip fail on correct code. Build values from the format's own vocabulary.",
            "DRAW EVERY OPTIONAL SEPARATOR AT RANDOM in `render`: blank lines, indentation, a "
                + "trailing newline. Leniency about layout is where these bugs live — on "
                + "SwiftFormatRuleStudio's RuleInfoParser, three mutants survived fixtures that "
                + "always had the blank line, and the randomised round trip killed all three.",
            "THE TYPE MUST BE EQUATABLE for the comparison, and if it carries a field the text "
                + "does not (a parse timestamp, a source location), compare a projection instead."
        ]
    }
}

/// A parser `input-totality` proposes for, returning a named type nothing prints back.
public struct StructuralRoundTripSubject: Sendable, Equatable {
    public let parser: FunctionSummary
    /// The parsed type, with `Self` resolved to the declaring type.
    public let structure: String

    public init(parser: FunctionSummary, structure: String) {
        self.parser = parser
        self.structure = structure
    }

    /// Every such parser in `summaries`.
    ///
    /// **A printer is any function from the type to `String`** — the `T -> String` half that
    /// `FunctionPairing` would pair with the parser, checked here in linear time: pairing is
    /// quadratic and has already run once. A type with one is left to `round-trip` and
    /// `normal-form`, which can state the law without a hand-written printer.
    public static func candidates(in summaries: [FunctionSummary]) -> [Self] {
        let declared = FunctionPairing.declaredTypePaths(in: summaries)
        let printed = Set(summaries.compactMap { summary -> String? in
            guard let result = summary.returnTypeText, result == "String" || result == "Substring" else {
                return nil
            }
            return FunctionPairing.transformationDomain(summary)
        })
        return summaries.compactMap { parser in
            guard let structure = parsedStructure(of: parser, declared: declared),
                  !printed.contains(structure),
                  InputTotalityTemplate.suggest(for: parser) != nil else {
                return nil
            }
            return Self(parser: parser, structure: structure)
        }
    }

    /// The named type a single-`String` parser returns: not a collection, an optional, a tuple, a
    /// standard-library scalar, or a generic container — those have no layout of their own to print.
    ///
    /// **A dotted name counts only when its head is a type the scanned code declares.** The census
    /// found swift-foundation's three `ParseStrategy.parse(_:) -> Format.FormatInput`: `Format` is
    /// the strategy's generic parameter, so the result is an associated type with no layout of its
    /// own — and its printer, `FormatStyle.format`, exists under a spelling the textual check cannot
    /// match. `C7ColorCube.Resource` passes, because `C7ColorCube` is declared.
    static func parsedStructure(of parser: FunctionSummary, declared: Set<String>) -> String? {
        guard parser.parameters.count == 1,
              let input = parser.parameters.first?.typeText, input == "String" || input == "Substring",
              let result = parser.returnTypeText else {
            return nil
        }
        let named = result == "Self" ? parser.containingTypeName : result
        guard let named,
              let first = named.first, first.isUppercase,
              !named.contains("<"), !named.contains("?"), !named.contains("("), !named.contains("["),
              !Self.scalars.contains(named) else {
            return nil
        }
        if let head = named.split(separator: ".").first, named.contains("."), !declared.contains(String(head)) {
            return nil
        }
        return named
    }

    private static let scalars: Set<String> = [
        "String", "Substring", "Character", "Bool", "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Double", "Float", "Decimal", "Date",
        "URL", "UUID", "Data"
    ]
}

extension TemplateRegistry {

    /// `StructuralRoundTripTemplate`. Reached from `collectValueLawSuggestions`, because
    /// `TemplateRegistry+Collection`'s collecting function is at its length cap.
    static func collectStructuralRoundTripSuggestions(
        summaries: [FunctionSummary],
        into collector: inout SuggestionCollector
    ) {
        for subject in StructuralRoundTripSubject.candidates(in: summaries) {
            if let suggestion = StructuralRoundTripTemplate.suggest(for: subject) {
                collector.record(suggestion, generatorType: subject.structure)
            }
        }
    }
}
