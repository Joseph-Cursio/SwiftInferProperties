import Foundation
@testable import SwiftInferCLI
import Testing

@Suite("InteractiveTriage — RefactorBridge prompt + readChoice (M7.5c + M8.4.b.1)")
struct InteractiveTriageBridgePromptTests {

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
}
