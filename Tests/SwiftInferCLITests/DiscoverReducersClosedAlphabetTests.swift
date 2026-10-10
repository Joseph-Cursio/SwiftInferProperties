import Foundation
@testable import SwiftInferCLI
import Testing

// `unknown-action-is-no-op` is documented never to fire on a closed enum, and
// fired on the first probe below for every non-TCA carrier: discovery captured
// an Action's cases only in the TCA walk, so the open-alphabet gate read every
// other reducer as open (found 2026-10-10).

@Suite("DiscoverReducers — unknown-action-is-no-op over a closed Action enum")
struct DiscoverReducersClosedAlphabetTests {

    private typealias Command = SwiftInferCommand.DiscoverReducers

    private func render(_ source: String) throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscoverReducersClosedAlphabetTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(source.utf8).write(to: directory.appendingPathComponent("R.swift"))
        return try Command.runPipeline(directory: directory)
    }

    @Test("a closed-enum Action gets determinism but not unknown-action-is-no-op, throwing or not")
    func closedEnumActionSuppressesUnknownActionNoOp() throws {
        for effects in ["", " throws"] {
            let rendered = try render("""
            struct CounterState: Equatable { var count = 0; var total = 0; var items: [Int] = [] }
            enum CounterAction: Equatable { case increment, reset }
            func reduce(_ state: CounterState, _ action: CounterAction)\(effects) -> CounterState {
                var s = state
                switch action {
                case .increment: s.count += 1
                case .reset: s = CounterState()
                }
                return s
            }
            """)
            #expect(rendered.contains("carrier:elm-style"))
            #expect(rendered.contains("[determinism]"))
            #expect(rendered.contains("[unknown-action-is-no-op]") == false, "effects: '\(effects)'")
        }
    }

    @Test("a protocol Action still gets unknown-action-is-no-op, saying it is a protocol")
    func protocolActionKeepsUnknownActionNoOp() throws {
        let rendered = try render("""
        protocol CounterAction {}
        struct CounterState: Equatable { var count = 0 }
        func reduce(_ state: CounterState, _ action: CounterAction) -> CounterState { state }
        """)
        #expect(rendered.contains("[unknown-action-is-no-op] CounterAction"))
        #expect(rendered.contains("'CounterAction' is a protocol"))
    }
}
