import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

@Suite("InteractiveTriage — M8.6 per-arm B accept end-to-end")
struct InteractiveTriageRefactorBridgeM8Tests {

    @Test("M8.6: B accept on CommutativeMonoid writes a kit-protocol extension")
    func m8AcceptCommutativeMonoidWritesKitExtension() throws {
        try assertBAcceptWritesArm(
            fixture: M8ArmFixture(
                arm: "CommutativeMonoid",
                typeName: "Tally",
                combineWitness: "merge",
                identityWitness: "empty",
                inverseWitness: nil
            ),
            assertions: { contents in
                #expect(contents.contains("extension Tally: CommutativeMonoid {"))
                #expect(contents.contains("Self.merge(lhs, rhs)"))
                #expect(contents.contains("Self.empty"))
            }
        )
    }

    @Test("M8.6: B accept on Group writes a kit-protocol extension with inverse witness")
    func m8AcceptGroupWritesKitExtension() throws {
        try assertBAcceptWritesArm(
            fixture: M8ArmFixture(
                arm: "Group",
                typeName: "AdditiveInt",
                combineWitness: "plus",
                identityWitness: "zero",
                inverseWitness: "negate"
            ),
            assertions: { contents in
                #expect(contents.contains("extension AdditiveInt: Group {"))
                #expect(contents.contains("Self.plus(lhs, rhs)"))
                #expect(contents.contains("Self.zero"))
                // M8.5 — Group arm threads inverseWitness into the
                // emitter's `static func inverse(_:)` aliasing body.
                #expect(contents.contains("public static func inverse(_ value: AdditiveInt)"))
                #expect(contents.contains("Self.negate(value)"))
            }
        )
    }

    @Test("M8.6: B accept on Semilattice writes a kit-protocol extension")
    func m8AcceptSemilatticeWritesKitExtension() throws {
        try assertBAcceptWritesArm(
            fixture: M8ArmFixture(
                arm: "Semilattice",
                typeName: "MaxInt",
                combineWitness: "combine",
                identityWitness: "minimum",
                inverseWitness: nil
            ),
            assertions: { contents in
                #expect(contents.contains("extension MaxInt: Semilattice {"))
                // `combine` is the canonical kit-required name; no
                // aliasing emitted (open decision in M7.5.a — self-
                // aliasing would recurse infinitely at runtime).
                #expect(contents.contains("public static func combine") == false)
                #expect(contents.contains("Self.minimum"))
            }
        )
    }

    @Test("M8.6: B accept on Numeric (Ring arm) writes a bare stdlib extension")
    func m8AcceptNumericWritesBareStdlibExtension() throws {
        // Numeric is the Ring writeout — bare `extension T: Numeric {}`
        // because the user's existing `+` / `*` operator implementations
        // satisfy stdlib Numeric. M8.4.b.2 + M8.5 + dispatch.
        try assertBAcceptWritesArm(
            fixture: M8ArmFixture(
                arm: "Numeric",
                typeName: "Money",
                combineWitness: "add",
                identityWitness: "zero",
                inverseWitness: nil
            ),
            assertions: { contents in
                #expect(contents.contains("extension Money: Numeric {}"))
                // Bare extension — no aliasing body.
                #expect(contents.contains("public static func combine") == false)
                #expect(contents.contains("public static var identity") == false)
            }
        )
    }

    @Test("M8.6: B accept on SetAlgebra (Semilattice secondary) writes a bare stdlib extension")
    func m8AcceptSetAlgebraWritesBareStdlibExtension() throws {
        try assertBAcceptWritesArm(
            fixture: M8ArmFixture(
                arm: "SetAlgebra",
                typeName: "Bag",
                combineWitness: "union",
                identityWitness: nil,
                inverseWitness: nil
            ),
            assertions: { contents in
                #expect(contents.contains("extension Bag: SetAlgebra {}"))
                #expect(contents.contains("public static func combine") == false)
            }
        )
    }
}

// MARK: - M8.6 fixture types + shared driver

/// Bundle of (arm, typeName, witnesses) for M8.6's per-arm
/// integration tests. Keeps the assertion driver under SwiftLint's
/// 5-parameter cap and clusters related fields.
struct M8ArmFixture {
    let arm: String
    let typeName: String
    let combineWitness: String
    let identityWitness: String?
    let inverseWitness: String?
}

/// Shared driver for the M8.6 per-arm tests. Constructs a single
/// `associativity` suggestion + a hand-crafted RefactorBridgeProposal
/// targeting `fixture.arm`, runs `--interactive` with scripted "B",
/// and verifies the writeout lands at the expected per-protocol path
/// with the expected content. Each arm's unique assertions go in the
/// closure.
private func assertBAcceptWritesArm(
    fixture: M8ArmFixture,
    assertions: (String) -> Void
) throws {
    let directory = try makeRBFixtureDirectory(name: "BAccept\(fixture.arm)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let assoc = makeM8Suggestion(
        template: "associativity",
        funcName: fixture.combineWitness,
        typeName: fixture.typeName
    )
    let proposal = RefactorBridgeProposal(
        typeName: fixture.typeName,
        protocolName: fixture.arm,
        combineWitness: fixture.combineWitness,
        identityWitness: fixture.identityWitness,
        inverseWitness: fixture.inverseWitness,
        explainability: ExplainabilityBlock(
            whySuggested: ["RefactorBridge claim: \(fixture.typeName) → \(fixture.arm)"],
            whyMightBeWrong: ["M8 acceptance test"]
        ),
        relatedIdentities: [assoc.identity]
    )
    let result = try InteractiveTriage.run(
        suggestions: [assoc],
        existingDecisions: .empty,
        context: makeRBContext(
            prompt: TriageRecordingPromptInput(scriptedLines: ["B"]),
            outputDirectory: directory,
            proposalsByType: [fixture.typeName: [proposal]]
        )
    )
    let stored = try #require(result.updatedDecisions.record(for: assoc.identity.normalized))
    #expect(stored.decision == .acceptedAsConformance)
    let path = try #require(result.writtenFiles.first)
    let expected = "Tests/Generated/SwiftInferRefactors/\(fixture.typeName)/\(fixture.arm).swift"
    #expect(path.path.contains(expected))
    let contents = try String(contentsOf: path, encoding: .utf8)
    assertions(contents)
}

/// Variant of `makeBinarySuggestion` that lets the caller specify the
/// type name in the signature. The default helper hardcodes `IntSet`;
/// M8.6's arms test against per-arm canonical types (Tally /
/// AdditiveInt / MaxInt / Money / Bag).
private func makeM8Suggestion(
    template: String,
    funcName: String,
    typeName: String
) -> Suggestion {
    let evidence = Evidence(
        displayName: "\(funcName)(_:_:)",
        signature: "(\(typeName), \(typeName)) -> \(typeName)",
        location: SourceLocation(file: "Test.swift", line: 1, column: 1)
    )
    return Suggestion(
        templateName: template,
        evidence: [evidence],
        score: Score(signals: [Signal(kind: .typeSymmetrySignature, weight: 90, detail: "")]),
        generator: .m1Placeholder,
        explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
        identity: SuggestionIdentity(canonicalInput: "\(template)|\(funcName)|\(typeName)")
    )
}
