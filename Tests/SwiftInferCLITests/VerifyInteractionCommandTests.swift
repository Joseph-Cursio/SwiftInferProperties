import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// V2.0 M3.D — `verify-interaction` subcommand smoke tests. The
// orchestration is tested in `VerifyInteractionPipelineTests`;
// these tests pin the CLI surface (argument parsing + the
// subcommand's place in the SwiftInferCommand tree).

@Suite("VerifyInteraction subcommand — V2.0 M3.D CLI surface")
struct VerifyInteractionCommandTests {

    @Test("VerifyInteraction is registered in SwiftInferCommand subcommands")
    func subcommandIsRegistered() {
        let registered = SwiftInferCommand.configuration.subcommands
        let names = registered.map { $0.configuration.commandName ?? "" }
        #expect(names.contains("verify-interaction"))
    }

    @Test("VerifyInteraction parses --target and optional --reducer / --user-module / --sequence-count")
    func argumentParsing() throws {
        let parsed = try SwiftInferCommand.VerifyInteraction.parse([
            "--target", "MyApp",
            "--reducer", "Inbox.reduce",
            "--user-module", "MyAppLib",
            "--sequence-count", "100"
        ])
        #expect(parsed.target == ["MyApp"])
        #expect(parsed.reducer == "Inbox.reduce")
        #expect(parsed.userModule == "MyAppLib")
        #expect(parsed.sequenceCount == 100)
    }

    @Test("--target is required; absent --target fails validation")
    func targetIsRequired() {
        // M3 — --target is a repeatable [String]; an empty array parses but
        // validate() rejects it (ArgumentParser calls validate() before run()).
        #expect(throws: (any Error).self) {
            var parsed = try SwiftInferCommand.VerifyInteraction.parse([])
            try parsed.validate()
        }
    }

    @Test("optional flags default to nil / default-sequence-count")
    func optionalFlagsDefault() throws {
        let parsed = try SwiftInferCommand.VerifyInteraction.parse(["--target", "MyApp"])
        #expect(parsed.reducer == nil)
        #expect(parsed.userModule == nil)
        #expect(parsed.sequenceCount == ActionSequenceStubEmitter.defaultSequenceCount)
    }
}
