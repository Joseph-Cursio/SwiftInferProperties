import Foundation
import SwiftEffectInference
import Testing

@testable import SwiftInferCore
@testable import SwiftInferTemplates

/// **A trap is not an impurity to `input-totality`.**
///
/// Before this rule, a non-throwing parser whose body held an `assert`, a `precondition`, a
/// `fatalError` or a `!` was `.refuted` with a witness, and the impure-subject veto withheld its
/// `input-totality` row — silently, on exactly the subjects that law is likeliest to refute.
/// SwiftFormat's `tokenize(_:)` (six `assert`s) was one. `docs/measurements/totality-trap-exemption.md`
/// has the A/B.
///
/// Every arm runs the real scanner over real source, so the wiring is under test and not only the
/// veto: a `soleTrap` the scanner never fills would pass a hand-built suite and fix nothing.
///
/// ## The negative arms outnumber the positive ones on purpose
///
/// The exemption is only sound because SEI reports its FIRST witness and checks every effect
/// before the trap scan — so each way a trap could hide an effect gets an arm: a marker beside
/// the trap, a refuting default argument (checked after the body), a settled-impure callee (seen
/// only by the package join), and another template on the same subject.
@Suite("Exemption — the impure-subject veto spares input-totality when its only refuter is a trap")
struct TotalityTrapExemptionTests {

    /// `input-totality`'s suggestions for `source`, after the veto, keyed by bare subject name
    /// (`parse`, not the `parse(_:)` the evidence row displays).
    static func totality(in source: String) -> [String: Suggestion] {
        let summaries = FunctionScanner.scan(source: source, file: "Lexer.swift")
        let proposed = summaries.compactMap(InputTotalityTemplate.suggest(for:))
        let vetoed = TemplateRegistry.applyImpureSubjectVeto(to: proposed, summaries: summaries)
        let named = vetoed.map { suggestion in
            (String(suggestion.evidence[0].displayName.prefix { $0 != "(" }), suggestion)
        }
        return Dictionary(named) { first, _ in first }
    }

    static func isVetoed(_ suggestion: Suggestion?) -> Bool {
        suggestion?.score.signals.contains { $0.kind == .impureSubject && $0.isVeto } ?? false
    }

    // MARK: - Positive

    @Test("an `assert` in a parser's body no longer withholds its totality law, and the row says why")
    func assertIsNotAnImpurity() throws {
        let rows = Self.totality(in: """
        func tokenize(_ source: String) -> [String] {
            assert(!source.contains("\\0"))
            return [source]
        }
        """)
        let row = try #require(rows["tokenize"], "the template did not propose the subject at all")

        #expect(!Self.isVetoed(row))
        #expect(row.score.tier != .suppressed)
        #expect(row.explainability.whySuggested.contains { $0.contains("`assert`") }, """
        The exempted row does not name its trap. A withheld veto is a decision too, and the reader \
        should see the line that read the body.
        """)
    }

    @Test("a force unwrap is a trap too")
    func forceUnwrapIsNotAnImpurity() throws {
        let rows = Self.totality(in: """
        func parse(_ text: String) -> Int {
            Int(text)!
        }
        """)
        #expect(!Self.isVetoed(try #require(rows["parse"])))
    }

    // MARK: - Negative — each way a trap could hide an effect

    @Test("a side effect still vetoes — the control")
    func sideEffectStillVetoes() throws {
        let rows = Self.totality(in: """
        func parse(_ text: String) -> Int {
            print(text)
            return 0
        }
        """)
        #expect(Self.isVetoed(try #require(rows["parse"])))
    }

    /// SEI scans markers before traps, so a body with both reports the marker. This pins that
    /// the exemption rests on that order rather than on the trap being present.
    @Test("a trap beside a side effect still vetoes")
    func trapBesideSideEffectStillVetoes() throws {
        let rows = Self.totality(in: """
        func parse(_ text: String) -> Int {
            precondition(!text.isEmpty)
            print(text)
            return 0
        }
        """)
        #expect(Self.isVetoed(try #require(rows["parse"])))
    }

    /// SEI checks default arguments AFTER the body, so a trap is the witness even when a default
    /// reads the clock. Any default keeps the veto: under-claiming is the safe direction.
    @Test("a trap beside a refuting default argument still vetoes")
    func trapHidingADefaultStillVetoes() throws {
        let rows = Self.totality(in: """
        import Foundation
        func parse(_ text: String, stamp: Double = Date().timeIntervalSince1970) -> Int {
            assert(stamp > 0)
            return text.count
        }
        """)
        #expect(Self.isVetoed(try #require(rows["parse"])))
    }

    /// A leaf witness cannot see a callee's effect; the package join can.
    @Test("a trap in a body that calls a settled-impure function still vetoes")
    func trapCallingImpureCalleeStillVetoes() throws {
        let rows = Self.totality(in: """
        func log(_ message: String) {
            print(message)
        }
        func parse(_ text: String) -> Int {
            assert(!text.isEmpty)
            log(text)
            return text.count
        }
        """)
        #expect(Self.isVetoed(try #require(rows["parse"])))
    }

    /// The exemption is for the law about traps. Any other law on a trapping subject keeps the
    /// veto: there the trap is a precondition the generator does not know about.
    @Test("another template on the same trap-only subject still vetoes")
    func otherTemplatesKeepTheVeto() throws {
        let summaries = FunctionScanner.scan(source: """
        func parse(_ text: String) -> Int {
            assert(!text.isEmpty)
            return text.count
        }
        """, file: "Lexer.swift")
        let subject = try #require(summaries.first { $0.name == "parse" })
        let other = ImpureSubjectVetoTests.suggestion(on: subject)
        let vetoed = TemplateRegistry.applyImpureSubjectVeto(to: [other], summaries: summaries)[0]

        #expect(other.templateName != TemplateRegistry.totalityTemplateName)
        #expect(Self.isVetoed(vetoed))
    }
}
