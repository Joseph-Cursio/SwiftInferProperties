import ArgumentParser
import Foundation
import Testing

@testable import SwiftInferCLI

// V1.50.E.1-2 — argument-parsing + per-entry-iteration tests for the
// `verify --all-from-index` survey flag. Subprocess integration
// coverage lands in V1.50.E.3 (separate suite, tagged .subprocess).

@Suite("V1.50.B — verify --all-from-index argument surface")
struct VerifyAllFromIndexArgumentTests {

    private static func parse(_ args: [String]) throws -> SwiftInferCommand.Verify {
        try SwiftInferCommand.Verify.parse(args)
    }

    @Test("--all-from-index parses without --suggestion")
    func parsesAllFromIndexAlone() throws {
        let verify = try Self.parse(["--all-from-index"])
        #expect(verify.allFromIndex == true)
        #expect(verify.suggestion == nil)
        #expect(verify.maxParallel == 4)
        #expect(verify.template == nil)
    }

    @Test("--max-parallel + --template parse alongside --all-from-index")
    func parsesAllFromIndexWithOptions() throws {
        let verify = try Self.parse([
            "--all-from-index",
            "--max-parallel", "8",
            "--template", "round-trip",
        ])
        #expect(verify.allFromIndex == true)
        #expect(verify.maxParallel == 8)
        #expect(verify.template == "round-trip")
    }

    @Test("--suggestion alone parses (back-compat with v1.42-v1.49)")
    func parsesSuggestionAlone() throws {
        let verify = try Self.parse(["--suggestion", "0xBC43"])
        #expect(verify.allFromIndex == false)
        #expect(verify.suggestion == "0xBC43")
        #expect(verify.maxParallel == 4)
    }
}
