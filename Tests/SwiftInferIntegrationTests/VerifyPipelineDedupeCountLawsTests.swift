@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// #711 — a dedupe's idempotence entry, built and run with #671's count laws as companions.
///
/// The unit suites inspect the emitted text. Only a build shows that the companions compile
/// beside the idempotence pass, and run after it without moving its verdict. So each planted
/// subject is idempotent and checks a different companion:
/// - a correct dedupe passes both laws;
/// - the identity fails C2;
/// - `{ _ in [] }` fails C1.
///
/// In all three, idempotence's own verdict stays `.bothPass`. The kill arm through the whole CLI is
/// `scripts/dedupe_count_laws_verify_kill_arm.py`. This suite spawns real `swift build`s; it is
/// tagged `.subprocess` and lands in batch 3 through the `VerifyPipeline` name.
@Suite("Verify pipeline — a dedupe's count laws as companions", .tags(.subprocess))
struct VerifyPipelineDedupeCountLawsTests {

    private static let preamble = """
    enum Planted {
        static func dedupe(_ xs: [Int]) -> [Int] {
            var seen = Set<Int>()
            return xs.filter { seen.insert($0 % 5).inserted }
        }
        static func identity(_ xs: [Int]) -> [Int] { xs }
        static func empty(_ xs: [Int]) -> [Int] { [] }
        static func byRemainder(_ xs: [Int]) -> [Int] {
            var byKey: [Int: Int] = [:]
            for x in xs { byKey[x % 5] = x }
            return Array(byKey.values)
        }
    }
    """

    private static func run(
        _ call: String, route: DedupeBody.Route
    ) throws -> (VerifyOutcome, [CompanionLawOutcome]) {
        let workdir = try VerifyPipelineIntegrationFixture.makeWorkdir()
        defer { VerifyPipelineIntegrationFixture.cleanUp(workdir) }
        let source = try StrategistDispatchEmitter.emit(
            StrategistDispatchEmitter.Inputs(
                carrier: "[Int]", typeShape: nil, template: "idempotence", functionCalls: [call],
                seedHex: VerifyPipelineIntegrationFixture.canonicalSeed, trialBudget: .small,
                preamble: preamble, dedupeBody: DedupeBody(route: route)
            )
        )
        _ = try VerifierWorkdir.synthesize(
            VerifierWorkdir.Inputs(workdir: workdir, userPackage: nil, stubSource: source)
        )
        let build = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
        guard build.exitCode == 0 else { return (.error(reason: "build failed: \(build.stderr)"), []) }
        let output = try VerifierSubprocess.runVerifierBinary(workdir: workdir)
        return (VerifyResultParser.parse(output), VerifyResultParser.companionLaws(output))
    }

    private static func statuses(_ laws: [CompanionLawOutcome]) -> [String] {
        laws.map { "\($0.law)=\($0.status.rawValue)" }
    }

    @Test("a correct keep-first dedupe holds idempotence and both companions")
    func correctDedupeHolds() throws {
        let (outcome, laws) = try Self.run("Planted.dedupe", route: .set)
        guard case .bothPass = outcome else { Issue.record("expected .bothPass; got \(outcome)"); return }
        #expect(Self.statuses(laws) == ["C1=held", "C2=held"])
    }

    @Test("the identity passes idempotence and fails C2, and idempotence's verdict stands")
    func identityFailsC2() throws {
        let (outcome, laws) = try Self.run("Planted.identity", route: .set)
        guard case .bothPass = outcome else { Issue.record("expected .bothPass; got \(outcome)"); return }
        #expect(laws.refutation?.law == "C2")
        #expect(laws.first { $0.law == "C1" }?.status == .held)
    }

    @Test("`{ _ in [] }` passes idempotence and fails C1, and idempotence's verdict stands")
    func emptyFailsC1() throws {
        let (outcome, laws) = try Self.run("Planted.empty", route: .set)
        guard case .bothPass = outcome else { Issue.record("expected .bothPass; got \(outcome)"); return }
        #expect(laws.refutation?.law == "C1")
        #expect(laws.refutation?.input?.hasPrefix("[") == true, "the singleton that vanished is recorded")
    }

    @Test("a dictionary-route dedupe holds the order-free idempotence and the count form of C2")
    func dictionaryRouteHolds() throws {
        let (outcome, laws) = try Self.run("Planted.byRemainder", route: .dictionary)
        guard case .bothPass = outcome else { Issue.record("expected .bothPass; got \(outcome)"); return }
        #expect(laws.refutation == nil, "\(Self.statuses(laws))")
    }
}
