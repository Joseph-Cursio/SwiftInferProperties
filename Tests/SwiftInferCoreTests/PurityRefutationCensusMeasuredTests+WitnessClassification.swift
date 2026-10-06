import SwiftEffectInference
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// The guard `verdictAgreesWithSoundPurity` cannot be: one on the **classification**.
///
/// A refuter that fires only on already-refuted functions moves no verdict, so a replica missing
/// it still reassembles every verdict correctly — and files the row on the wrong side of the
/// witness/ignorance split. That is not hypothetical. Measured when SEI's `ConstructionFacts` was
/// wired in (2026-10-06): **0 verdicts moved on `Sources/`, and 2 rows changed their first witness
/// from `propagatedTry` to a construction** (`dispatchSideOrchestrator`, `runInteractiveBranch`,
/// both through a defaulted `Date`). An unchanged replica would have kept every guard above green
/// while filing both as actionable ignorance — the "misattributing quietly" CLAUDE.md says the
/// verdict guard prevents, arriving through a door it does not watch.
///
/// So this compares the replica's classification with **SEI's own** first witness, row by row.
/// It can be exact where the construction tally cannot: SEI's witness is consulted, not replicated.
extension PurityRefutationCensusMeasuredTests {

    /// Whether SEI's first witness names something in the source. `noBody` and `propagatedTry` are
    /// the two ignorance witnesses `refutation(for:)` can produce (`declaredThrows` belongs to the
    /// whole-domain question only).
    static func seiNamesAWitness(_ refutation: PurityRefutation?) -> Bool {
        switch refutation {
        case .none, .propagatedTry, .noBody: false
        default: true
        }
    }

    /// Refuted, reducer-pure rows the replica files on the other side of the split from SEI's
    /// configured first witness. Reducer-refuted rows are excluded: `ReducerPurityAnalyzer` is a
    /// witness the replica names itself, and SEI has no say in them.
    static func misclassified(by attributor: Attributor) -> [String] {
        zip(corpus, verdicts).compactMap { subject, verdict in
            guard verdict == .refuted, ReducerPurityAnalyzer.analyze(subject.function) == .pure else { return nil }
            let replica = attributor.causes(of: subject.function).contains(where: \.isWitness)
            let sei = seiNamesAWitness(CensusPurity.oracle.inferrerRefutation(for: subject.function))
            return replica == sei ? nil : "\(subject.file):\(subject.name) replica=\(replica) sei=\(sei)"
        }
    }

    @Test("the replica files every refuted row on the same side of the split as SEI's first witness")
    func classificationAgreesWithSEIWitness() {
        let wrong = Self.misclassified(by: Attributor(inferrer: CensusPurity.inferrer))
        #expect(wrong.isEmpty, """
        \(wrong.count) rows misfiled — the witness/ignorance split this census reports is void until \
        the replica is re-derived: \(wrong.prefix(10).joined(separator: " | "))
        """)
    }

    /// The control: the same replica given an unconfigured inferrer must be caught. On this
    /// corpus it misfiles exactly the two re-witnessed rows; zero would mean the guard above
    /// cannot fail.
    @Test("a replica blind to construction is detected as misfiling")
    func constructionBlindReplicaIsDetected() {
        let wrong = Self.misclassified(by: Attributor(inferrer: PurityInferrer()))
        print("construction-blind replica misfiles \(wrong.count): \(wrong.joined(separator: " | "))")
        #expect(!wrong.isEmpty, "dropping the construction table from the replica must be detectable")
    }

    /// The same control on a snippet, so it does not depend on what `Sources/` happens to hold.
    /// `make` throws and `try`s into a callee, so without facts its first witness is
    /// `propagatedTry` — ignorance. With facts it constructs `Item`, whose stored `id` mints a
    /// `UUID`, and SEI reports that first: a witness.
    @Test("snippet — a construction witness flips the classification, and only with the table")
    func snippetClassificationNeedsTheTable() throws {
        let tree = Parser.parse(source: """
        struct Item { let id = UUID(); let title: String }
        func check(_ title: String) throws {}
        func make(_ title: String) throws -> Item {
            try check(title)
            return Item(title: title)
        }
        """)
        let make = try #require(CensusFunctionCollector.functions(in: tree).first { $0.name.text == "make" })
        let configured = CensusPurity.snippetOracle(tree)
        let table = PurityInferrer(constructionFacts: configured.constructionFacts)

        #expect(configured.verdict(for: make) == .refuted)
        #expect(Self.seiNamesAWitness(configured.inferrerRefutation(for: make)))
        #expect(Attributor(inferrer: table).causes(of: make) == [.construction, .propagatedTry])
        #expect(Attributor(inferrer: PurityInferrer()).causes(of: make) == [.propagatedTry])
        #expect(!Self.seiNamesAWitness(SoundPurity.unconfigured.inferrerRefutation(for: make)))
    }
}

extension CensusFunctionCollector {
    /// The functions `tree` declares, by this collector's traversal rules.
    static func functions(in tree: SourceFileSyntax) -> [FunctionDeclSyntax] {
        let collector = CensusFunctionCollector(viewMode: .sourceAccurate)
        collector.walk(tree)
        return collector.functions
    }
}
