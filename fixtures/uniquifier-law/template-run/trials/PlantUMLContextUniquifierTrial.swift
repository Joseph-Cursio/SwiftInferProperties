import PropertyLawKit
@testable import SwiftPlantUMLFramework
import Testing

// The stub accept writes for uniqName, with its two placeholders filled as the census's repro builds them.
struct PlantUMLContextUniquifierTrial {
    @Test func uniqName_issuesDistinctResults() async {
        // A narrow alphabet on purpose (#692): the law fails only where one drawn name equals another
        // plus the decoration, and a generator drawing realistic names never collides.
        let firstCollision: @Sendable ([String]) -> String? = { names in
            let subject = PlantUMLContext()
            var issued: [String: Int] = [:]
            for (position, name) in names.enumerated() {
                let result = String(describing: subject.uniqName(item: SyntaxStructure(kind: .struct, name: name), relationship: "inherits"))
                if result == "" { continue }
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
            stateA: 0x2EB260AF05EF3E8E,
            stateB: 0x2C66DA4C5B26B691,
            stateC: 0x66432209B8568A38,
            stateD: 0xD608DC21FA81D07D
        )
        let result = await backend.check(
            trials: 100,
            seed: seed,
            sample: { rng in
                let dense = Bool.random(using: &rng)
                let pool = dense ? ["a", "a1", "b", "b1"] : ["a", "a0", "a1", "a2", "a10", "a11", "b", "b0", "b1", "b2", "b10", "b11"]
                let count = Int.random(in: dense ? 11 ... 24 : 1 ... 16, using: &rng)
                return (0 ..< count).map { _ in pool.randomElement(using: &rng) ?? "a" }
            },
            property: { names in firstCollision(names) == nil }
        )
        if case let .failed(_, _, input, _) = result {
            Issue.record("uniqName(item:relationship:) issued one result twice: \(firstCollision(input) ?? "")")
        }
    }
}
