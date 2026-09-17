import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// `state-machine`'s scaffold (#478): the moves spelled right, and nothing live but the issue.
@Suite("State-machine scaffold — the two moves, and a to-do that compiles")
struct StateMachineScaffoldTests {

    private static func move(
        _ name: String,
        labels: [String?] = [],
        types: [String] = [],
        instance: Bool = true,
        isAsync: Bool = false,
        isThrows: Bool = false
    ) -> StateMachineMove {
        StateMachineMove(
            name: name,
            parameterLabels: labels,
            parameterTypes: types,
            isInstanceMethod: instance,
            isAsync: isAsync,
            isThrows: isThrows
        )
    }

    private static let selectDeselect = LiftedTestEmitter.stateMachineScaffold(
        carrier: "InboxViewModel",
        forward: move("select", labels: [nil], types: ["Int"]),
        backward: move("deselect")
    )

    @Test("an unlabelled instance move draws its receiver and a typed placeholder")
    func unlabelledInstanceMove() {
        #expect(Self.selectDeselect.contains("//   subject.select(<#Int#>)"))
        #expect(Self.selectDeselect.contains("//   subject.deselect()"))
    }

    @Test("a labelled move keeps its label; a static move is called on the carrier")
    func labelsAndStatics() {
        let stub = LiftedTestEmitter.stateMachineScaffold(
            carrier: "Navigator",
            forward: Self.move("push", labels: ["to", nil], types: ["Path", "Bool"]),
            backward: Self.move("reset", instance: false)
        )
        #expect(stub.contains("//   subject.push(to: <#Path#>, <#Bool#>)"))
        #expect(stub.contains("//   Navigator.reset()"))
    }

    @Test("an async throwing move is spelled with try await")
    func effects() {
        let stub = LiftedTestEmitter.stateMachineScaffold(
            carrier: "Store",
            forward: Self.move("load", isAsync: true, isThrows: true),
            backward: Self.move("unload")
        )
        #expect(stub.contains("//   try await subject.load()"))
    }

    /// The template states `backward ∘ forward == id`, so the forward move is applied first.
    @Test("the forward move is applied before the backward one")
    func order() throws {
        let forward = try #require(Self.selectDeselect.range(of: "subject.select("))
        let backward = try #require(Self.selectDeselect.range(of: "subject.deselect("))
        #expect(forward.lowerBound < backward.lowerBound)
    }

    /// **The guard that it compiles as written.** Everything the reader supplies is commented out,
    /// and the only live statement is the issue. A placeholder that leaked out of a comment would
    /// be a compile error in the reader's test target — worse than the scaffold it replaces.
    @Test("nothing is live but the test signature, the issue and the brace")
    func onlyTheIssueIsLive() {
        let live = Self.selectDeselect.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") }
        #expect(live.count == 3, "live lines: \(live)")
        #expect(live.first == "@Test func select_deselect_roundTrip() async throws {")
        #expect(live.dropFirst().first?.hasPrefix("Issue.record(\"TODO") == true)
        #expect(live.last == "}")
    }
}
