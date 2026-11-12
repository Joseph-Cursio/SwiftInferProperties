import PropertyLawKit
@testable import SwiftUMLBridgeFramework
import Testing

struct NodeIdAllocatorUniquifierTrial {

    @Test func issue_issuesDistinctResults() async {
        // A narrow alphabet on purpose (#692): the law fails only where one drawn name equals another
        // plus the decoration, and a generator drawing realistic names never collides.
        let firstCollision: @Sendable ([String]) -> String? = { names in
            var subject = LayoutGraphBuilder.NodeIdAllocator(reserving: names)
            var issued: [String: Int] = [:]
            for (position, name) in names.enumerated() {
                let result = String(describing: subject.issue(for: name))
                if let earlier = issued[result] {
                    return "calls \(earlier + 1) and \(position + 1), on \(names[earlier]) and \(name), "
                        + "both returned \(result)"
                }
                issued[result] = position
            }
            return nil
        }
        let backend = SwiftPropertyBasedBackend()
        let seed = Seed(
            stateA: 0x7FD67CAB1FF50749,
            stateB: 0xC448BC0D4E34D5C9,
            stateC: 0x6D12E9DBF73E834D,
            stateD: 0x3FB6BBB1FAAA6103
        )
        let result = await backend.check(
            trials: 100,
            seed: seed,
            sample: { rng in
                let dense = Bool.random(using: &rng)
                let pool = dense ? ["a", "a_1", "b", "b_1"] : ["a", "a_0", "a_1", "a_2", "a_10", "a_11", "b", "b_0", "b_1", "b_2", "b_10", "b_11"]
                let count = Int.random(in: dense ? 11 ... 24 : 1 ... 16, using: &rng)
                return (0 ..< count).map { _ in pool.randomElement(using: &rng) ?? "a" }
            },
            property: { names in firstCollision(names) == nil }
        )
        if case let .failed(_, _, input, _) = result {
            Issue.record("issue(for:) issued one result twice: \(firstCollision(input) ?? "")")
        }
    }}
