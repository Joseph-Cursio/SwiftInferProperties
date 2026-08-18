import Foundation
import Testing

@testable import SwiftInferCore

/// **What does consulting the callee's verdict actually retract?**
///
/// Open item 43, built after `docs/measurements/purity-refuting-fixpoint-census.md`
/// measured it: 18 rows at one hop over 2,396 `.pure` subjects. This is the A/B for the
/// shipped rule, which is **stricter than the census's** — the census could read SEI's
/// refutation causes through a test-only replica, and shipped code cannot, so the witness
/// is established from public API alone (`.refuted` and not throwing). It therefore
/// under-retracts by construction, and the measured gap is the price of that soundness.
///
/// ## The baseline is the per-file path, which is unjoined by design
///
/// `scanCorpus(file:)` cannot run the join — a single file is not a package, and the
/// unanimity rule the join depends on would be checked against a fraction of a name's
/// declarations. Merging the per-file results is therefore the honest "before", and it
/// exercises the real API rather than a test-only switch.
@Suite("Join — what consulting the callee's verdict retracts", .serialized)
struct PackagePurityJoinMeasuredTests {

    struct Arm {
        let corpus: String
        let summaries: Int
        let purebefore: Int
        let pureAfter: Int
        var retracted: Int { purebefore - pureAfter }
    }

    static let corpora = PartialPurityConsumerMeasuredTests.corpora

    /// Merged per-file scan — every summary the package produces, with no join applied.
    static func unjoined(_ root: URL) throws -> [FunctionSummary] {
        try SwiftSourceFiles.sorted(in: root).flatMap { try FunctionScanner.scanCorpus(file: $0).summaries }
    }

    static let measured: [Arm] = corpora.compactMap { corpus in
        guard let before = try? unjoined(corpus.root),
              let after = try? FunctionScanner.scanCorpus(directory: corpus.root).summaries else {
            return nil
        }
        return Arm(
            corpus: corpus.name,
            summaries: before.count,
            purebefore: before.filter { $0.purityVerdict == .pure }.count,
            pureAfter: after.filter { $0.purityVerdict == .pure }.count
        )
    }

    /// **The control.** The two paths must agree on everything except the join, or the
    /// difference below is measuring two different scans rather than one rule.
    @Test("control — the joined and unjoined scans see the same declarations")
    func bothPathsSeeTheSameCorpus() throws {
        for corpus in Self.corpora {
            let before = try Self.unjoined(corpus.root)
            let after = try FunctionScanner.scanCorpus(directory: corpus.root).summaries
            #expect(before.count == after.count, """
            \(corpus.name): \(before.count) summaries per-file against \(after.count) \
            per-directory. The join must not add or drop a declaration.
            """)
            #expect(before.map(\.location) == after.map(\.location), "\(corpus.name): order or identity differs")
        }
    }

    @Test("the join retracts, and never on a corpus it was not given")
    func theJoinRetracts() {
        #expect(!Self.measured.isEmpty, "no corpus scanned — every number here is vacuous")
        #expect(Self.measured.contains { $0.retracted > 0 }, """
        The join retracted nothing anywhere. Either the seed rule found no settled-impure \
        name, or `calledFreeFunctionNames` is not being collected — both make open item \
        43's build inert.
        """)
        for arm in Self.measured {
            #expect(arm.retracted >= 0, "\(arm.corpus): the join PROMOTED a verdict, which it must never do")
        }
    }

    /// The census's named example, and the reason the item was filed:
    /// `standardOutputViaEnv` calls a `standardOutput` that spawns a subprocess, and was
    /// judged `.pure`. SwiftProjectLint stopped seeding it on 2026-08-17; this is the
    /// same fact reaching this side.
    @Test("the witness the census named is now refuted")
    func theSubprocessSpawnerIsRefuted() throws {
        let root = PurityRefutationCensusMeasuredTests.packageRoot.appendingPathComponent("Sources")
        let joined = try FunctionScanner.scanCorpus(directory: root).summaries
        let subject = joined.first { $0.name == "standardOutputViaEnv" }

        let verdict = try #require(subject?.purityVerdict, "`standardOutputViaEnv` is no longer in Sources/")
        #expect(verdict != .pure, """
        `DrainedProcess.standardOutputViaEnv` is judged `.pure` again. It calls a function \
        that spawns a subprocess and drains two pipes on a global queue, and this repo's \
        advisory would recommend `/// @lint.effect pure` for it — while SwiftProjectLint \
        refuses to seed it. Two consumers, one oracle, opposite answers.
        """)
    }

    @Test("census — rows retracted by the one-hop join")
    func census() {
        for arm in Self.measured {
            print("""
            \(arm.corpus): \(arm.summaries) summaries · \
            .pure \(arm.purebefore) → \(arm.pureAfter) (−\(arm.retracted))
            """)
        }
    }
}
