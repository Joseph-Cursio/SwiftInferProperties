import Foundation
import SwiftEffectInference
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// **Phase 0.7 of `plans/declaration-claims-plan.md`: do `consuming` and
/// `borrowing` carry purity evidence in this analyzer, or is the population zero?**
///
/// The plan proposes two Family C edges resting on parameter ownership:
///
/// - **`consuming` → in-place mutation unobservable**, scored by *"count of
///   `consuming`-parameter mutations currently refuting purity"*.
/// - **`borrowing` → non-escape evidence**, scored by *"overlap between
///   inferred-`borrowing` params and functions refuted on capture"*.
///
/// Both scorers presuppose that something in the purity oracle reacts to a
/// parameter. **Reading `verdict(for:)` says nothing does** — it consults body
/// presence, `async`, body markers, body totality, default arguments, and the
/// `throws` clause, in that order, and `mutatesCapturedState` is reachable only
/// through `isPure(_ closure:)`. But *"reading the code cannot tell you how many
/// refuters are queued up"* is this repo's standing rule, and item 33 was declined
/// only after its premise was **measured** false rather than argued false. So this
/// probes it.
///
/// ## Why a premise probe is cheap and worth doing first
///
/// Three times in this line of work the documented error direction has been
/// backwards, always permissive. Item 33's premise — *chains terminate at a
/// higher-order call* — measured **false**: nine of ten probe shapes reached
/// `.pure`. A row whose scorer counts a population of zero cannot be built, and
/// finding that out costs an afternoon rather than a phase.
@Suite("Census — do ownership modifiers carry purity evidence?", .serialized)
struct OwnershipPremiseCensusMeasuredTests {

    // MARK: - Probes

    /// The verdict for the first function declaration in `source`.
    static func verdict(ofFirstFunctionIn source: String) -> PurityVerdict? {
        let tree = Parser.parse(source: source)
        let finder = OwnershipFunctionFinder(viewMode: .sourceAccurate)
        finder.walk(tree)
        return finder.found.first.map { SoundPurity.verdict(for: $0) }
    }

    /// Ten shapes, each naming what it is testing. Ownership and `inout` shapes
    /// alongside controls that must refute, so *"nothing refutes"* can be told from
    /// *"the oracle is not running."*
    static let probes: [(label: String, source: String)] = [
        ("inout, mutated", "func f(_ value: inout Int) { value += 1 }"),
        ("inout, read only", "func f(_ value: inout Int) -> Int { value }"),
        ("consuming", """
            struct Box { var value: Int }
            func f(_ box: consuming Box) -> Int { box.value }
            """),
        ("consuming, mutated", """
            struct Box { var value: Int }
            func f(_ box: consuming Box) -> Int {
                var local = box
                local.value += 1
                return local.value
            }
            """),
        ("borrowing", """
            struct Box { var value: Int }
            func f(_ box: borrowing Box) -> Int { box.value }
            """),
        ("mutates module state", """
            var counter = 0
            func f(_ value: Int) -> Int { counter += value; return counter }
            """),
        ("mutates static state", """
            struct S { static var total = 0 }
            func f(_ value: Int) -> Int { S.total += value; return S.total }
            """),
        ("control: plain value param", "func f(_ value: Int) -> Int { value + 1 }"),
        ("control: marker in body", "func f(_ value: Int) -> Int { print(value); return value }"),
        ("control: force unwrap", "func f(_ value: Int?) -> Int { value! }")
    ]

    /// **The premise, asserted.** No ownership or `inout` shape may refute — if one
    /// does, the plan's two rows have a mechanism and this census is the wrong
    /// answer. The controls must refute, or the probe proves nothing.
    @Test("no parameter shape refutes purity, and the controls confirm the oracle is running")
    func parameterShapesDoNotRefute() {
        let answers = Dictionary(
            uniqueKeysWithValues: Self.probes.map { ($0.label, Self.verdict(ofFirstFunctionIn: $0.source)) }
        )

        for label in ["inout, mutated", "inout, read only", "consuming", "consuming, mutated", "borrowing"] {
            #expect(
                answers[label] == .pure,
                "`\(label)` answered \(answers[label].map { "\($0)" } ?? "nil") — an ownership shape now refutes"
            )
        }

        #expect(answers["control: marker in body"] == .refuted, "the oracle is not refuting anything")
        #expect(answers["control: force unwrap"] == .refuted, "totality refuter is not running")
        #expect(answers["control: plain value param"] == .pure)
    }

    /// **The finding this probe was not looking for, and it is narrower and sharper
    /// than expected.** A function mutating a **module-level `var`** is judged
    /// `.pure`. A function mutating **`static` state is refuted** —
    /// `ReducerPurityAnalyzer` covers *"a write to static or `Self` state"*, which is
    /// the `reducerEffect` cause the item 29 census attributes 26 rows to.
    ///
    /// So the gap is not *"nothing refutes state mutation"*. It is exactly one shape:
    ///
    /// | shape | verdict | covered by |
    /// |---|---|---|
    /// | `S.total += value` (static member) | `.refuted` | `ReducerPurityAnalyzer` |
    /// | `counter += value` (file-scope `var`) | **`.pure`** | **nothing** |
    /// | `{ counter += 1 }` (closure capture) | refuted | `refuteIfCaptured` |
    ///
    /// **The same write is refuted inside a closure and admitted inside a function**,
    /// which makes this an asymmetry between two code paths in one type rather than a
    /// limit of the analysis — and it needs no ownership modifier to occur, so it is a
    /// larger population than the rows this probe was sent to check.
    ///
    /// Pinned as a standing claim that the hole is open. Both assertions fail the day a
    /// module-state refuter lands for functions, which is the notification a comment
    /// would not give.
    @Test("module-level var mutation is judged pure, though static mutation is refuted")
    func moduleStateMutationIsNotRefuted() {
        #expect(
            Self.verdict(ofFirstFunctionIn: Self.probes.first { $0.label == "mutates module state" }?.source ?? "")
                == .pure,
            "a module-state refuter has landed for FUNCTIONS — retire this test and re-take the census"
        )
        #expect(
            Self.verdict(ofFirstFunctionIn: Self.probes.first { $0.label == "mutates static state" }?.source ?? "")
                == .refuted,
            "static-state mutation stopped refuting — ReducerPurityAnalyzer's static clause regressed"
        )
    }

    /// The control for the asymmetry: the **closure** oracle does refute the same
    /// shape, so the gap is a difference between two code paths in one type rather
    /// than a limitation of the analysis.
    @Test("the closure oracle DOES refute captured mutation, which is the asymmetry")
    func closureOracleRefutesCapturedMutation() throws {
        let tree = Parser.parse(source: "let f = { counter += 1 }")
        let finder = OwnershipClosureFinder(viewMode: .sourceAccurate)
        finder.walk(tree)
        let closure = try #require(finder.found.first)
        #expect(
            PurityInferrer().isPure(closure) == false,
            "the closure oracle stopped refuting captured mutation; this census's asymmetry closed from the other side"
        )
    }

    // MARK: - Population

    /// Parameters carrying an ownership modifier or `inout`, over this repo's
    /// `Sources/`. Counted by scanning the parameter's own source text, which is
    /// exact enough for a population question and robust across SwiftSyntax's
    /// changing representation of specifiers.
    struct Population {
        let inoutParams: Int
        let consuming: Int
        let borrowing: Int
        let subjects: Int
    }

    static let population: Population = {
        var inoutCount = 0
        var consumingCount = 0
        var borrowingCount = 0
        var subjects = 0
        for subject in PurityRefutationCensusMeasuredTests.corpus {
            var touched = false
            for parameter in subject.function.signature.parameterClause.parameters {
                let text = parameter.trimmedDescription
                if text.contains("inout ") { inoutCount += 1; touched = true }
                if text.contains("consuming ") { consumingCount += 1; touched = true }
                if text.contains("borrowing ") { borrowingCount += 1; touched = true }
            }
            if touched { subjects += 1 }
        }
        return Population(
            inoutParams: inoutCount,
            consuming: consumingCount,
            borrowing: borrowingCount,
            subjects: subjects
        )
    }()

    /// **The population question, which decides the rows even if the premise had
    /// held.** A scorer over zero declarations is unbuildable regardless of
    /// mechanism.
    @Test("census — the ownership population, and the premise verdict")
    func census() {
        var lines: [String] = ["", "OWNERSHIP PREMISE CENSUS", ""]
        lines.append("probe verdicts:")
        for probe in Self.probes {
            let answer = Self.verdict(ofFirstFunctionIn: probe.source).map { "\($0)" } ?? "nil"
            lines.append("  \(probe.label.padding(toLength: 30, withPad: " ", startingAt: 0)) -> \(answer)")
        }
        lines.append("")
        lines.append("population over Sources/ (\(PurityRefutationCensusMeasuredTests.corpus.count) functions):")
        lines.append("  parameters declared `inout`:      \(Self.population.inoutParams)")
        lines.append("  parameters declared `consuming`:  \(Self.population.consuming)")
        lines.append("  parameters declared `borrowing`:  \(Self.population.borrowing)")
        lines.append("  functions using any of the three: \(Self.population.subjects)")
        print(lines.joined(separator: "\n"))

        #expect(
            PurityRefutationCensusMeasuredTests.corpus.count > 2_000,
            "corpus is \(PurityRefutationCensusMeasuredTests.corpus.count) — the population figure has no denominator"
        )
    }
}

/// Top-level function declarations, for addressing a probe's subject.
private final class OwnershipFunctionFinder: SyntaxVisitor {
    private(set) var found: [FunctionDeclSyntax] = []

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        found.append(node)
        return .visitChildren
    }
}

/// Closure literals, for the asymmetry control.
private final class OwnershipClosureFinder: SyntaxVisitor {
    private(set) var found: [ClosureExprSyntax] = []

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        found.append(node)
        return .visitChildren
    }
}
