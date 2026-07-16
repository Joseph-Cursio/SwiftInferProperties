import ArgumentParser
@testable import SwiftInferCLI
import Testing

@Test
func discoverSubcommandIsConfigured() {
    let configuration = SwiftInferCommand.configuration
    #expect(configuration.commandName == "swift-infer")
    #expect(configuration.subcommands.contains { $0 == SwiftInferCommand.Discover.self })
}

@Test
func discoverRejectsARunWithNoScope() throws {
    // --target is no longer required at parse time: --sources (C1) is a peer way to name the scan
    // scope, so both are optional and parsing an empty argument list now succeeds. The requirement —
    // never scan without an explicit scope — moved to resolve time, where passing NEITHER is a hard
    // error. Both halves are pinned here so a future edit can't silently reinstate a default scope.
    _ = try SwiftInferCommand.Discover.parse([])
    #expect(throws: (any Error).self) {
        _ = try SwiftInferCommand.Discover.resolveScanDirectory(target: nil, sources: nil)
    }
}
