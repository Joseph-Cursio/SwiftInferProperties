import ArgumentParser
import Testing
@testable import SwiftInferCLI

@Test
func discoverSubcommandIsConfigured() {
    let configuration = SwiftInferCommand.configuration
    #expect(configuration.commandName == "swift-infer")
    #expect(configuration.subcommands.contains { $0 == SwiftInferCommand.Discover.self })
}

@Test
func discoverRequiresTargetOption() throws {
    // Parsing without --target should throw a validation error from
    // ArgumentParser; we don't care about the specific error type, only
    // that a missing required option is rejected.
    #expect(throws: (any Error).self) {
        _ = try SwiftInferCommand.Discover.parse([])
    }
}
