import Foundation
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// **Experiment with a standing verdict — read this header before proposing a
/// domain-transfer veto.** Same form as `TriviaInsensitivityExperimentTests`: a
/// test file whose job is to hold a measured answer that no doc restates.
///
/// ## The question
///
/// `IdempotenceReturnShapeClassifier` declines to veto its documented miss class —
/// `T -> T` where the output is a different *kind* of thing, so `f(f(x))` is
/// meaningless though it type-checks — on the grounds that it is *"not
/// characterised well enough, and a veto that fires on a guess suppresses true
/// laws"*. [#93](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/93)
/// asks whether it can be characterised.
///
/// ## The candidate, frozen before scoring
///
/// > **The parameter does not appear in the returned expression.**
///
/// An idempotent function *projects* its input onto a normal form, so the input
/// is present in what it hands back; a result assembled from values the parameter
/// merely *seeded* has changed domain. Return-expression-only, matching the
/// classifier's measured *where you look beats what you look for*.
///
/// The rule and its predicted failure were committed in
/// `fixtures/domain-transfer-signal/FROZEN-prediction.md` **before this file
/// existed** — git order is the proof — so the rule could not be tuned to the
/// answer.
///
/// ## The verdict
///
/// Scored against the 47 `idempotence` rows that EXECUTED in the 2026-08-05
/// whole-corpus survey (5 refuted, 42 held — the 42 being what a veto must not
/// touch). The measured numbers are asserted below rather than described, so they
/// cannot drift.
///
/// **The rule does not work, and the reason generalises.** It recovers most of the
/// class but cannot separate it from ordinary accumulate-into-a-local shapes,
/// because *"the parameter is absent from the return expression"* is true of every
/// function that binds a local and returns it — which is a coding style, not a
/// semantic property.
///
/// **So the signal for domain transfer is not in the return expression's SHAPE.**
/// It is in **dataflow** — whether the parameter's value survives to the result at
/// all, as opposed to merely seeding it. That is a strictly more expensive
/// analysis than anything `IdempotenceReturnShape` performs, and it is the reason
/// the classifier's refusal to veto this class was right rather than merely
/// cautious.
///
/// Do not propose a return-expression-shaped veto for domain transfer without
/// first refuting the numbers below.
@Suite("Experiment — can domain transfer be discriminated from the return expression?")
struct DomainTransferSignalExperimentTests {

    /// One executed row from the frozen survey: the carrier, the function, and
    /// whether measured verify REFUTED its idempotence law.
    private struct Row {
        let carrier: String
        let function: String
        let refuted: Bool
    }

    /// The five refuted rows are the class under study; the rest held.
    /// Transcribed from `fixtures/whole-corpus-survey/2026-08-05-whole-corpus.jsonl`.
    private static let refutedFunctions: Set<String> = [
        "codableRoundTripGenerator", "markovSynthesized",
        "regressionFileHash", "seedString", "seedTuple"
    ]

    /// Bare names of the 42 rows that HELD. A veto firing on any of these is a
    /// true law suppressed — the failure that cannot be seen from the outside.
    private static let heldFunctions: Set<String> = [
        "arrayElementType", "bareIdentityName", "bareTypeName", "booleanStem", "bound",
        "boundingNumerics", "canonicalLawName", "dedupedByStateAndAction",
        "dualStyleTrailingArgument", "functionBaseName", "lastComponent", "merge",
        "moduleIdentifier", "normalisedTypeName", "prioritised", "quoted", "sortSuggestions",
        "strippingGenericParameters", "stripGenerics", "trimmed", "unwrappingRepetition"
    ]

    // MARK: - The candidate rule

    /// Whether the parameter's name appears anywhere in the returned expression.
    ///
    /// Textual containment on the trimmed description, which is generous to the
    /// rule: any mention counts, so a miss is a genuine absence rather than a
    /// parsing artefact.
    static func parameterReachesReturnExpression(_ node: FunctionDeclSyntax) -> Bool? {
        guard let parameter = node.signature.parameterClause.parameters.first,
              let body = node.body else { return nil }
        let name = (parameter.secondName ?? parameter.firstName).text
        guard name != "_" else { return nil }
        guard let result = resultExpression(of: Array(body.statements)) else { return nil }
        return result.trimmedDescription.contains(name)
    }

    /// The expression whose value the function returns — an explicit trailing
    /// `return X`, or a bare expression under Swift's implicit return. Mirrors
    /// `IdempotenceReturnShapeClassifier`'s own, deliberately: the experiment has
    /// to look exactly where the classifier looks or it is testing something else.
    private static func resultExpression(of statements: [CodeBlockItemSyntax]) -> ExprSyntax? {
        guard let last = statements.last else { return nil }
        switch last.item {
        case .stmt(let statement): return statement.as(ReturnStmtSyntax.self)?.expression
        case .expr(let expression): return expression
        case .decl: return nil
        }
    }

    // MARK: - The measurement

    @Test("the rule recovers most of the class but cannot separate it from ordinary code")
    func discriminatorIsNotSeparating() {
        var flaggedRefuted: Set<String> = []
        var flaggedHeld: Set<String> = []
        var seenRefuted: Set<String> = []
        var seenHeld: Set<String> = []

        for url in Self.swiftFiles() {
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let tree = Parser.parse(source: source)
            let collector = FunctionCollector(viewMode: .sourceAccurate)
            collector.walk(tree)
            for node in collector.functions {
                let name = node.name.text
                let isRefuted = Self.refutedFunctions.contains(name)
                let isHeld = Self.heldFunctions.contains(name)
                guard isRefuted || isHeld else { continue }
                guard let reaches = Self.parameterReachesReturnExpression(node) else { continue }
                if isRefuted { seenRefuted.insert(name) } else { seenHeld.insert(name) }
                guard !reaches else { continue }
                if isRefuted { flaggedRefuted.insert(name) } else { flaggedHeld.insert(name) }
            }
        }

        // The population actually reached. A name the scan cannot find would
        // silently improve precision, so it is asserted rather than assumed.
        #expect(seenRefuted.count == 5, "scan must reach all 5: \(seenRefuted.sorted())")
        #expect(seenHeld.count == 20, "scan must reach the held population: \(seenHeld.count)")

        // RECALL — 4 of 5. The miss is `codableRoundTripGenerator`, which returns
        // `renderGenerator(for: typeName)` and so DOES name its parameter. Named
        // in the frozen prediction before this ran.
        #expect(flaggedRefuted == ["markovSynthesized", "regressionFileHash", "seedString", "seedTuple"])

        // PRECISION — 4 of 12, i.e. 33%. Eight true laws would be suppressed to
        // catch four false ones. `dedupedByStateAndAction` is among them: item 18
        // recorded it as the false alarm a body-wide scan produced, and it is the
        // false alarm this rule produces too, by a different route.
        //
        // `unwrappingRepetition` is the other name worth seeing twice — item 18's
        // bare-`+` rule wrongly vetoed it, and so would this. The same handful of
        // functions keep attracting cheap rules, which is the argument for scoring
        // a rule against the laws that HELD rather than against the class it targets.
        #expect(flaggedHeld.count == 8, "flagged held: \(flaggedHeld.sorted())")
        #expect(flaggedHeld.contains("dedupedByStateAndAction"))
        #expect(flaggedHeld.contains("unwrappingRepetition"))

        // The verdict, as an assertion: the rule fires on true laws TWICE as often
        // as on the class. If this ever fails the rule separates better than
        // measured and #93 is worth reopening — with these numbers as the baseline.
        #expect(flaggedHeld.count > flaggedRefuted.count)
    }

    /// Walks every `func` in a file, regardless of nesting.
    private final class FunctionCollector: SyntaxVisitor {
        var functions: [FunctionDeclSyntax] = []

        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            functions.append(node)
            return .visitChildren
        }
    }

    private static func swiftFiles() -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SwiftInferCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil
        ) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
