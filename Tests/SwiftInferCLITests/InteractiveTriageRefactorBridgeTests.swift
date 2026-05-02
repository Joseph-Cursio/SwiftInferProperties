import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

// swiftlint:disable type_body_length file_length
// M8.4.b.1 added 5 new tests covering the [A/B/B'/s/n/?] prompt
// extension + b'/c choice parsing; M8.6 added 5 per-arm B-accept
// integration tests (CMon / Group / Semilattice / Numeric /
// SetAlgebra). Both grew the suite past the body / file caps. Suite
// coheres around its subject — splitting along the limits would
// scatter the prompt-UI + accept-end-to-end tests across multiple
// files.

@Suite("InteractiveTriage — RefactorBridge [A/B/s/n/?] arm (M7.5c)")
struct InteractiveTriageRefactorBridgeTests {

    // MARK: - Prompt rendering

    @Test("Prompt collapses to [A/s/n/?] when no proposal is attached")
    func promptOmitsBWhenNoProposal() {
        let line = InteractiveTriage.promptLine(position: 1, total: 1, primaryAvailable: false)
        #expect(line == "[1/1] Accept (A) / Skip (s) / Reject (n) / Help (?)")
    }

    @Test("Prompt extends to [A/B/s/n/?] when proposal is attached")
    func promptIncludesBWhenProposalAttached() {
        let line = InteractiveTriage.promptLine(position: 2, total: 5, primaryAvailable: true)
        #expect(line == "[2/5] Accept (A) / Conformance (B) / Skip (s) / Reject (n) / Help (?)")
    }

    @Test("Help text mentions B only when proposal is attached")
    func helpTextConditional() {
        let withB = InteractiveTriage.helpText(primaryAvailable: true)
        let withoutB = InteractiveTriage.helpText(primaryAvailable: false)
        #expect(withB.contains("B — accept Option B (RefactorBridge"))
        #expect(withoutB.contains("B —") == false)
    }

    // MARK: - M8.4.b.1 — extended [A/B/B'/s/n/?] prompt

    @Test("Prompt extends to [A/B/B'/s/n/?] when secondary proposal is attached")
    func promptExtendsWithSecondary() {
        let line = InteractiveTriage.promptLine(
            position: 1,
            total: 1,
            primaryAvailable: true,
            secondaryAvailable: true
        )
        #expect(line.contains("Conformance' (B')"))
    }

    @Test("Prompt only shows B' when both primary AND secondary are available")
    func promptDoesNotShowBPrimeWithoutPrimary() {
        // Defensive: if only secondary is true (impossible by current
        // dispatch but worth pinning), prompt doesn't surface B'.
        let lineSecondaryOnly = InteractiveTriage.promptLine(
            position: 1,
            total: 1,
            primaryAvailable: false,
            secondaryAvailable: true
        )
        #expect(lineSecondaryOnly.contains("Conformance' (B')") == false)
    }

    @Test("Help text mentions B' only when secondaryAvailable is true")
    func helpTextMentionsBPrimeOnlyWhenSecondaryAvailable() {
        let withBPrime = InteractiveTriage.helpText(
            primaryAvailable: true,
            secondaryAvailable: true
        )
        let withoutBPrime = InteractiveTriage.helpText(
            primaryAvailable: true,
            secondaryAvailable: false
        )
        #expect(withBPrime.contains("B' — accept the secondary"))
        #expect(withoutBPrime.contains("B' —") == false)
    }

    @Test("`b'` and `c` both return .conformancePrime when secondaryAvailable is true")
    func bPrimeAndCAreEquivalent() {
        let outputBPrime = TriageRecordingOutput()
        let promptBPrime = TriageRecordingPromptInput(scriptedLines: ["b'"])
        let choiceBPrime = InteractiveTriage.readChoice(
            prompt: promptBPrime,
            output: outputBPrime,
            primaryAvailable: true,
            secondaryAvailable: true
        )
        switch choiceBPrime {
        case .conformancePrime: break
        default: Issue.record("expected .conformancePrime for b', got \(choiceBPrime)")
        }

        let outputC = TriageRecordingOutput()
        let promptC = TriageRecordingPromptInput(scriptedLines: ["c"])
        let choiceC = InteractiveTriage.readChoice(
            prompt: promptC,
            output: outputC,
            primaryAvailable: true,
            secondaryAvailable: true
        )
        switch choiceC {
        case .conformancePrime: break
        default: Issue.record("expected .conformancePrime for c, got \(choiceC)")
        }
    }

    @Test("`b'` is rejected when secondaryAvailable is false")
    func bPrimeRequiresSecondaryAvailable() {
        let output = TriageRecordingOutput()
        // Script: `b'` (rejected — no secondary) → `s` advances.
        let prompt = TriageRecordingPromptInput(scriptedLines: ["b'", "s"])
        let choice = InteractiveTriage.readChoice(
            prompt: prompt,
            output: output,
            primaryAvailable: true,
            secondaryAvailable: false
        )
        switch choice {
        case .skip: break
        default: Issue.record("expected .skip fallthrough, got \(choice)")
        }
        #expect(output.lines.contains { $0.contains("Unrecognized input 'b''") })
    }

    // MARK: - readChoice gating

    @Test("`b` is recognized only when primaryAvailable is true")
    func bRequiresProposalAvailable() {
        let outputWithProposal = TriageRecordingOutput()
        let promptWithProposal = TriageRecordingPromptInput(scriptedLines: ["b"])
        let choiceWith = InteractiveTriage.readChoice(
            prompt: promptWithProposal,
            output: outputWithProposal,
            primaryAvailable: true
        )
        switch choiceWith {
        case .conformance: break
        default: Issue.record("expected .conformance when proposal available, got \(choiceWith)")
        }

        let outputWithout = TriageRecordingOutput()
        // Script: `b` (rejected) → `s` (default). The `b` should fall to
        // the unrecognized-input branch and re-prompt; `s` advances.
        let promptWithout = TriageRecordingPromptInput(scriptedLines: ["b", "s"])
        let choiceWithout = InteractiveTriage.readChoice(
            prompt: promptWithout,
            output: outputWithout,
            primaryAvailable: false
        )
        switch choiceWithout {
        case .skip: break
        default: Issue.record("expected fallthrough to .skip when no proposal, got \(choiceWithout)")
        }
        #expect(outputWithout.lines.contains { $0.contains("Unrecognized input 'b'") })
    }

    // MARK: - B accept end-to-end

    @Test("B accept writes a Semigroup conformance file and records .acceptedAsConformance")
    func bAcceptWritesSemigroupExtension() throws {
        let directory = try makeFixtureDirectory(name: "BAcceptSemigroup")
        defer { try? FileManager.default.removeItem(at: directory) }
        let assoc = makeBinarySuggestion(template: "associativity", funcName: "merge")
        let proposal = RefactorBridgeProposal(
            typeName: "IntSet",
            protocolName: "Semigroup",
            combineWitness: "merge",
            identityWitness: nil,
            explainability: ExplainabilityBlock(whySuggested: ["op match"], whyMightBeWrong: ["assoc not verified"]),
            relatedIdentities: [assoc.identity]
        )
        let result = try InteractiveTriage.run(
            suggestions: [assoc],
            existingDecisions: .empty,
            context: makeContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["B"]),
                outputDirectory: directory,
                proposalsByType: ["IntSet": [proposal]]
            )
        )
        let stored = try #require(result.updatedDecisions.record(for: assoc.identity.normalized))
        #expect(stored.decision == .acceptedAsConformance)
        let path = try #require(result.writtenFiles.first)
        #expect(path.path.contains("Tests/Generated/SwiftInferRefactors/IntSet/Semigroup.swift"))
        let contents = try String(contentsOf: path, encoding: .utf8)
        // M7.5.a — emitter aliases the user's `merge` op into the
        // kit's required `static func combine(_:_:)`.
        #expect(contents.contains("extension IntSet: Semigroup {"))
        #expect(contents.contains("public static func combine(_ lhs: IntSet, _ rhs: IntSet) -> IntSet {"))
        #expect(contents.contains("Self.merge(lhs, rhs)"))
        #expect(contents.contains("import ProtocolLawKit"))
        #expect(contents.contains("RefactorBridge proposal: IntSet → Semigroup"))
    }

    @Test("B accept on Monoid proposal writes a Monoid extension with combine + identity aliasing")
    func bAcceptWritesMonoidExtension() throws {
        let directory = try makeFixtureDirectory(name: "BAcceptMonoid")
        defer { try? FileManager.default.removeItem(at: directory) }
        let assoc = makeBinarySuggestion(template: "associativity", funcName: "merge")
        let proposal = RefactorBridgeProposal(
            typeName: "IntSet",
            protocolName: "Monoid",
            combineWitness: "merge",
            identityWitness: "empty",
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            relatedIdentities: [assoc.identity]
        )
        let result = try InteractiveTriage.run(
            suggestions: [assoc],
            existingDecisions: .empty,
            context: makeContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["B"]),
                outputDirectory: directory,
                proposalsByType: ["IntSet": [proposal]]
            )
        )
        let path = try #require(result.writtenFiles.first)
        #expect(path.path.contains("Tests/Generated/SwiftInferRefactors/IntSet/Monoid.swift"))
        let contents = try String(contentsOf: path, encoding: .utf8)
        // M7.5.a — emitter aliases both `merge` (binary op) and
        // `empty` (identity element) into the kit's required statics.
        #expect(contents.contains("extension IntSet: Monoid {"))
        #expect(contents.contains("Self.merge(lhs, rhs)"))
        #expect(contents.contains("public static var identity: IntSet { Self.empty }"))
    }

    // MARK: - Per-type aggregation (open decision #7)

    @Test("Once user picks B for type T, subsequent suggestions on T collapse to [A/s/n/?]")
    func perTypeAggregationCollapsesPromptAfterB() throws {
        let directory = try makeFixtureDirectory(name: "PerType")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = makeBinarySuggestion(template: "associativity", funcName: "merge")
        let second = makeBinarySuggestion(template: "identity-element", funcName: "merge")
        let proposal = RefactorBridgeProposal(
            typeName: "IntSet",
            protocolName: "Monoid",
            combineWitness: "merge",
            identityWitness: "empty",
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            relatedIdentities: [first.identity, second.identity]
        )
        let output = TriageRecordingOutput()
        // First prompt: B (accept conformance). Second prompt: should
        // collapse to [A/s/n/?]; user types s. If the prompt doesn't
        // collapse, the next line would be `[A/B/s/n/?]` and the test
        // assertion below catches it.
        _ = try InteractiveTriage.run(
            suggestions: [first, second],
            existingDecisions: .empty,
            context: makeContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["B", "s"]),
                output: output,
                outputDirectory: directory,
                proposalsByType: ["IntSet": [proposal]]
            )
        )
        let promptLines = output.lines.filter { $0.contains("/2]") }
        #expect(promptLines.count == 2)
        #expect(promptLines[0].contains("Conformance (B)"))
        #expect(promptLines[1].contains("Conformance (B)") == false)
    }

    // MARK: - Proposal not attached

    @Test("Suggestion whose identity is NOT in relatedIdentities sees only [A/s/n/?]")
    func proposalDoesNotShowForUnrelatedSuggestion() throws {
        let directory = try makeFixtureDirectory(name: "Unrelated")
        defer { try? FileManager.default.removeItem(at: directory) }
        let assoc = makeBinarySuggestion(template: "associativity", funcName: "merge")
        let unrelated = makeBinarySuggestion(template: "commutativity", funcName: "swap")
        let proposal = RefactorBridgeProposal(
            typeName: "IntSet",
            protocolName: "Semigroup",
            combineWitness: "merge",
            identityWitness: nil,
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            relatedIdentities: [assoc.identity]  // unrelated.identity NOT in set
        )
        let output = TriageRecordingOutput()
        _ = try InteractiveTriage.run(
            suggestions: [unrelated],
            existingDecisions: .empty,
            context: makeContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["s"]),
                output: output,
                outputDirectory: directory,
                proposalsByType: ["IntSet": [proposal]]
            )
        )
        let promptLines = output.lines.filter { $0.contains("/1]") }
        #expect(promptLines.first?.contains("Conformance (B)") == false)
    }

    // MARK: - Dry-run

    @Test("B accept under --dry-run logs the would-be path but writes no file")
    func bAcceptDryRunSkipsFileWrite() throws {
        let directory = try makeFixtureDirectory(name: "BDryRun")
        defer { try? FileManager.default.removeItem(at: directory) }
        let assoc = makeBinarySuggestion(template: "associativity", funcName: "merge")
        let proposal = RefactorBridgeProposal(
            typeName: "IntSet",
            protocolName: "Semigroup",
            combineWitness: "merge",
            identityWitness: nil,
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            relatedIdentities: [assoc.identity]
        )
        let output = TriageRecordingOutput()
        let result = try InteractiveTriage.run(
            suggestions: [assoc],
            existingDecisions: .empty,
            context: makeContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["B"]),
                output: output,
                outputDirectory: directory,
                dryRun: true,
                proposalsByType: ["IntSet": [proposal]]
            )
        )
        #expect(result.writtenFiles.isEmpty)
        // Decisions also not updated under dry-run (matches A-arm behaviour).
        #expect(result.updatedDecisions == .empty)
        #expect(output.lines.contains { $0.contains("[dry-run] would write") })
    }

    // MARK: - M8.6 — per-arm B accept end-to-end (CMon / Group / Semilattice / Numeric / SetAlgebra)

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
        // satisfy stdlib Numeric. The §4.5 caveat carries the
        // FloatingPoint warning. M8.4.b.2 + M8.5 + dispatch.
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

    /// Bundle of (arm, typeName, witnesses) for M8.6's per-arm
    /// integration tests. Keeps `assertBAcceptWritesArm` under
    /// SwiftLint's 5-parameter cap and clusters related fields.
    private struct M8ArmFixture {
        let arm: String
        let typeName: String
        let combineWitness: String
        let identityWitness: String?
        let inverseWitness: String?
    }

    /// Shared helper for the M8.6 per-arm tests. Constructs a single
    /// `associativity` suggestion + a hand-crafted RefactorBridgeProposal
    /// targeting `fixture.arm`, runs `--interactive` with scripted "B",
    /// and verifies the writeout lands at the expected per-protocol
    /// path with the expected content. Each arm's unique assertions go
    /// in the closure.
    private func assertBAcceptWritesArm(
        fixture: M8ArmFixture,
        assertions: (String) -> Void
    ) throws {
        let directory = try makeFixtureDirectory(name: "BAccept\(fixture.arm)")
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
            context: makeContext(
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

    /// Variant of `makeBinarySuggestion` that lets the caller specify
    /// the type name in the signature. The default helper hardcodes
    /// `IntSet`; M8.6's arms test against per-arm canonical types
    /// (Tally / AdditiveInt / MaxInt / Money / Bag).
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

    // MARK: - Helpers

    private func makeContext(
        prompt: TriageRecordingPromptInput,
        output: TriageRecordingOutput = TriageRecordingOutput(),
        diagnostics: TriageRecordingDiagnosticOutput = TriageRecordingDiagnosticOutput(),
        outputDirectory: URL,
        dryRun: Bool = false,
        proposalsByType: [String: [RefactorBridgeProposal]] = [:]
    ) -> InteractiveTriage.Context {
        InteractiveTriage.Context(
            prompt: prompt,
            output: output,
            diagnostics: diagnostics,
            outputDirectory: outputDirectory,
            dryRun: dryRun,
            clock: { Date(timeIntervalSince1970: 0) },
            proposalsByType: proposalsByType
        )
    }

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("RBTriageTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
// swiftlint:enable type_body_length file_length
