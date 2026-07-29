import Foundation
import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// The recursive-carrier stub is **built and run**, not just string-matched.
///
/// `RecursiveCarrierStubTests` asserts the emitted text. That is necessary and
/// not sufficient: a string-emission test cannot tell a compiling stub from an
/// uncompilable one, and an uncompilable stub surfaces downstream as
/// `measured-error: build-failed` — which the report renders as an
/// *architectural* non-verdict, indistinguishable from "this carrier is out of
/// reach". That is exactly how the kit's `CaseIterable`-in-member-position bug
/// survived: every consumer that reached it emitted a stub that failed to
/// build, and the failure never pointed at codegen.
///
/// Two things are checked here that no string test can reach:
///
/// 1. **It compiles.** The depth-budgeted helper names a two-parameter generic
///    return type (`Generator<Node, AnySequence<Any>>`) and erases both arms;
///    get either wrong and there is no spellable return type.
/// 2. **It terminates.** `Gen.array(of:)` evaluates its element generator
///    eagerly, so a budget check written inside the expression rather than as
///    an early return recurses forever at generator-*construction* time. That
///    failure mode is a hang, not an error — a string test would pass while the
///    stub spun.
@Suite(.tags(.subprocess))
struct RecursiveCarrierMeasuredTests {

    private static let recursiveSubject = """
        struct Node: Equatable {
            var name: String
            var kids: [Node]
        }

        /// Idempotent by construction: sorting children by name is a fixpoint.
        func normalize(_ n: Node) -> Node {
            Node(name: n.name, kids: n.kids.map(normalize).sorted { $0.name < $1.name })
        }
        """

    private static func shape() -> IndexedTypeShape {
        IndexedTypeShape(
            name: "Node",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: [
                IndexedTypeShape.StoredMember(name: "name", typeName: "String"),
                IndexedTypeShape.StoredMember(name: "kids", typeName: "[Node]")
            ]
        )
    }

    @Test("a recursive carrier builds, runs, and reaches a verdict")
    func recursiveCarrierRunsEndToEnd() throws {
        let typeShape = Self.shape()
        let stub = try StrategistDispatchEmitter.emit(
            StrategistDispatchEmitter.Inputs(
                carrier: "Node",
                typeShape: typeShape,
                template: "idempotence",
                functionCalls: ["normalize"],
                seedHex: .init(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
                trialBudget: .small,
                preamble: Self.recursiveSubject,
                allShapes: ["Node": typeShape]
            )
        )

        // The generator must actually be the helper, or this test would pass
        // while measuring the old dead end.
        #expect(stub.contains("func __genNode(_ budget: Int)"))

        let workdir = FileManager.default.temporaryDirectory
            .appendingPathComponent("recursive-carrier-measured/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workdir) }

        _ = try VerifierWorkdir.synthesize(
            VerifierWorkdir.Inputs(workdir: workdir, userPackage: nil, stubSource: stub)
        )

        let build = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
        #expect(build.exitCode == 0, """
            The recursive stub did not compile — the whole point of this suite.
            stderr:
            \(build.stderr.suffix(2_000))
            """)
        guard build.exitCode == 0 else { return }

        let run = try VerifierSubprocess.runVerifierBinary(workdir: workdir)
        let outcome = VerifyResultParser.parse(run)

        // `normalize` genuinely is idempotent, so the expected verdict is a
        // pass. What is being measured is that a verdict was *reached at all*:
        // before this change the carrier could not be generated, and a hang or
        // a build failure would both land as a non-verdict here.
        #expect(run.stdout.contains("VERIFY_DEFAULT_RESULT"), """
            No verdict marker — the stub built but produced nothing, which is
            what a non-terminating generator looks like from outside.
            stdout: \(run.stdout.suffix(1_000))
            """)
        if case .error(let reason) = outcome {
            Issue.record("verify reported an error outcome: \(reason)")
        }
    }
}
