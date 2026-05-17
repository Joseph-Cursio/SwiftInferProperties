import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

// V1.109 (cycle-103c) — tests for the --interactive-bridges flag
// on discover-interaction: argument parsing + the flag-mutex
// helper. The bridge-triage namespace itself is tested separately
// in InteractionBridgeInteractiveTriageTests; this file covers the
// CLI wiring layer.

@Suite("DiscoverInteraction — V1.109 --interactive-bridges flag")
struct DiscoverInteractionBridgesFlagTests {

    private typealias Command = SwiftInferCommand.DiscoverInteraction

    // MARK: - Argument parsing

    @Test func interactiveBridgesFlagDefaultsToFalse() throws {
        let parsed = try Command.parse(["--target", "MyApp"])
        #expect(parsed.interactiveBridges == false)
    }

    @Test func interactiveBridgesFlagSetsTrue() throws {
        let parsed = try Command.parse([
            "--target", "MyApp",
            "--interactive-bridges"
        ])
        #expect(parsed.interactiveBridges == true)
    }

    @Test func interactiveBridgesParsesAlongsideOtherFlags() throws {
        let parsed = try Command.parse([
            "--target", "MyApp",
            "--reducer", "Inbox.body",
            "--include-possible",
            "--interactive-bridges",
            "--dry-run"
        ])
        #expect(parsed.interactiveBridges == true)
        #expect(parsed.dryRun == true)
        #expect(parsed.includePossible == true)
        #expect(parsed.reducer == "Inbox.body")
    }

    // MARK: - Flag-mutex resolution

    @Test func mutexInteractiveBeatsBridges() {
        let diagnostics = TriageRecordingDiagnosticOutput()
        let result = Command.warnAndResolveFlagMutex(
            interactive: true,
            interactiveBridges: true,
            updateBaseline: false,
            diagnostics: diagnostics
        )
        #expect(result.interactive == true)
        #expect(result.interactiveBridges == false)
        #expect(diagnostics.lines.contains {
            $0.contains("--interactive-bridges ignored")
        })
    }

    @Test func mutexBridgesBeatsBaseline() {
        let diagnostics = TriageRecordingDiagnosticOutput()
        let result = Command.warnAndResolveFlagMutex(
            interactive: false,
            interactiveBridges: true,
            updateBaseline: true,
            diagnostics: diagnostics
        )
        #expect(result.interactiveBridges == true)
        #expect(result.updateBaseline == false)
        #expect(diagnostics.lines.contains {
            $0.contains("--update-baseline ignored")
        })
    }

    @Test func mutexInteractiveBeatsBaseline() {
        let diagnostics = TriageRecordingDiagnosticOutput()
        let result = Command.warnAndResolveFlagMutex(
            interactive: true,
            interactiveBridges: false,
            updateBaseline: true,
            diagnostics: diagnostics
        )
        #expect(result.interactive == true)
        #expect(result.updateBaseline == false)
        #expect(diagnostics.lines.contains {
            $0.contains("--update-baseline ignored")
        })
    }

    @Test func mutexAllThreeFlagsInteractiveWinsAndBothDowngradesWarn() {
        let diagnostics = TriageRecordingDiagnosticOutput()
        let result = Command.warnAndResolveFlagMutex(
            interactive: true,
            interactiveBridges: true,
            updateBaseline: true,
            diagnostics: diagnostics
        )
        #expect(result.interactive == true)
        #expect(result.interactiveBridges == false)
        #expect(result.updateBaseline == false)
        // Both downgrade warnings emit.
        let bridgesWarning = diagnostics.lines.contains {
            $0.contains("--interactive-bridges ignored")
        }
        let baselineWarning = diagnostics.lines.contains {
            $0.contains("--update-baseline ignored")
        }
        #expect(bridgesWarning)
        #expect(baselineWarning)
    }

    @Test func mutexNoFlagsPassesThrough() {
        let diagnostics = TriageRecordingDiagnosticOutput()
        let result = Command.warnAndResolveFlagMutex(
            interactive: false,
            interactiveBridges: false,
            updateBaseline: false,
            diagnostics: diagnostics
        )
        #expect(result.interactive == false)
        #expect(result.interactiveBridges == false)
        #expect(result.updateBaseline == false)
        #expect(diagnostics.lines.isEmpty)
    }

    @Test func mutexBaselineAloneNoWarning() {
        let diagnostics = TriageRecordingDiagnosticOutput()
        let result = Command.warnAndResolveFlagMutex(
            interactive: false,
            interactiveBridges: false,
            updateBaseline: true,
            diagnostics: diagnostics
        )
        #expect(result.updateBaseline == true)
        #expect(diagnostics.lines.isEmpty)
    }

    @Test func mutexBridgesAloneNoWarning() {
        let diagnostics = TriageRecordingDiagnosticOutput()
        let result = Command.warnAndResolveFlagMutex(
            interactive: false,
            interactiveBridges: true,
            updateBaseline: false,
            diagnostics: diagnostics
        )
        #expect(result.interactiveBridges == true)
        #expect(diagnostics.lines.isEmpty)
    }
}
