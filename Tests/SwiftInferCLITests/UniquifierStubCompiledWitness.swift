import PropertyLawKit
import Testing

// A COMPILED witness for the uniquifier stubs accept writes (#692). `UniquifierStubCompiledWitnessTests`
// scans the subjects below out of this file, has accept write each stub, and checks this file holds that
// text. The test target building is the proof the emitted text compiles. The three stubs at file scope
// running green is the proof the law holds on correct uniquifiers; the fourth, held in a disabled suite and
// run under `withKnownIssue`, is the proof it refutes #669's defect. Keep the subjects at the top: the seed
// is derived from the law's identity, which names the subject's location.

/// A correct uniquifier: every candidate is re-checked against what was issued.
final class UniquifierWitnessNamer {
    private var issued: Set<String> = []
    private var counter = 0

    func freshName(_ base: String) -> String {
        var candidate = base
        while issued.contains(candidate) {
            candidate = "\(base)\(counter)"
            counter += 1
        }
        issued.insert(candidate)
        return candidate
    }
}

/// A correct memoizing uniquifier: the id stored for a seen key comes back.
struct UniquifierWitnessIdentifiers {
    private var byKey: [String: String] = [:]
    private var taken: Set<String> = []

    mutating func id(forKey key: String) -> String {
        if let existing = byKey[key] { return existing }
        var candidate = key
        var suffix = 2
        while taken.contains(candidate) {
            candidate = "\(key)_\(suffix)"
            suffix += 1
        }
        taken.insert(candidate)
        byKey[key] = candidate
        return candidate
    }
}

/// A correct uniquifier over the caller's `inout` set.
func uniquifierWitnessCaseName(for base: String, taken: inout Set<String>) -> String {
    var name = base
    var suffix = 2
    while taken.contains(name) {
        name = "\(base)\(suffix)"
        suffix += 1
    }
    taken.insert(name)
    return name
}

/// #669's defect: the suffixed name is never re-checked, and one counter serves every name, so `a0`, `a`,
/// `a` issues `a0` twice.
final class UniquifierWitnessDefectiveNamer {
    private var seen: [String] = []
    private var index = 0

    func uniqName(_ name: String) -> String {
        var newName = name
        if seen.contains(name) {
            newName += "\(index)"
            index += 1
        } else {
            seen.append(name)
        }
        return newName
    }
}

/// A correct uniquifier whose contract owes distinct results over the names it reserved, shaped like
/// SwiftUMLStudio's `NodeIdAllocator`: the stub builds it from the drawn names.
struct UniquifierWitnessAllocator {
    private var taken: Set<String>
    private var issuedNames: Set<String> = []

    init(reserving names: [String]) {
        taken = Set(names)
    }

    mutating func issue(for name: String) -> String {
        var nodeId = name
        if issuedNames.contains(name) {
            var counter = 1
            repeat {
                nodeId = "\(name)_\(counter)"
                counter += 1
            } while taken.contains(nodeId)
        }
        issuedNames.insert(name)
        taken.insert(nodeId)
        return nodeId
    }
}

// The stubs accept writes for the subjects above, laid out as the written file is.

struct UniquifierWitnessNamerFreshNameUniquifierTests {

    @Test func freshName_issuesDistinctResults() async {
        // A narrow alphabet on purpose (#692): the law fails only where one drawn name equals another
        // plus the decoration, and a generator drawing realistic names never collides.
        let firstCollision: @Sendable ([String]) -> String? = { names in
            let subject = UniquifierWitnessNamer()
            var issued: [String: Int] = [:]
            for (position, name) in names.enumerated() {
                let result = String(describing: subject.freshName(name))
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
            stateA: 0x22CD1F517E545D25,
            stateB: 0x6A7908FEA576322E,
            stateC: 0xF71037174261AA95,
            stateD: 0xE87CA413AAFD6AE4
        )
        let result = await backend.check(
            trials: 100,
            seed: seed,
            sample: { rng in
                let dense = Bool.random(using: &rng)
                let pool = dense ? ["a", "a1", "b", "b1"] : [
                    "a", "a0", "a1", "a2", "a10", "a11", "b", "b0", "b1", "b2", "b10", "b11"
                ]
                let count = Int.random(in: dense ? 11 ... 24 : 1 ... 16, using: &rng)
                return (0 ..< count).map { _ in pool.randomElement(using: &rng) ?? "a" }
            },
            property: { names in firstCollision(names) == nil }
        )
        if case let .failed(_, _, input, _) = result {
            Issue.record("freshName(_:) issued one result twice: \(firstCollision(input) ?? "")")
        }
    }
}

struct UniquifierWitnessIdentifiersIdUniquifierTests {

    @Test func id_givesEqualIdsExactlyForEqualKeys() async {
        // A narrow alphabet on purpose (#692): the law fails only where one drawn name equals another
        // plus the decoration, and a generator drawing realistic names never collides.
        let firstMismatch: @Sendable ([String]) -> String? = { names in
            var subject = UniquifierWitnessIdentifiers()
            let ids = names.map { name in String(describing: subject.id(forKey: name)) }
            for later in names.indices {
                for earlier in names.indices where earlier < later && (
                    names[earlier] == names[later]
                ) != (ids[earlier] == ids[later]) {
                    return "keys \(names[earlier]) and \(names[later]) (calls \(earlier + 1) and " + "\(later + 1)) gave ids \(ids[earlier]) and \(ids[later])"
                }
            }
            return nil
        }
        let backend = SwiftPropertyBasedBackend()
        let seed = Seed(
            stateA: 0x89CEEFAA66A6EFBA,
            stateB: 0x191D67D05A2F721E,
            stateC: 0x8AAB9B310D1351A2,
            stateD: 0x881698F50BCFCAA1
        )
        let result = await backend.check(
            trials: 100,
            seed: seed,
            sample: { rng in
                let dense = Bool.random(using: &rng)
                let pool = dense ? ["a", "a_1", "b", "b_1"] : [
                    "a", "a_0", "a_1", "a_2", "a_10", "a_11", "b", "b_0", "b_1", "b_2", "b_10", "b_11"
                ]
                let count = Int.random(in: dense ? 11 ... 24 : 1 ... 16, using: &rng)
                return (0 ..< count).map { _ in pool.randomElement(using: &rng) ?? "a" }
            },
            property: { names in firstMismatch(names) == nil }
        )
        if case let .failed(_, _, input, _) = result {
            Issue.record("id(forKey:) gave ids that do not follow its keys: \(firstMismatch(input) ?? "")")
        }
    }
}

struct UniquifierWitnessCaseNameUniquifierTests {

    @Test func uniquifierWitnessCaseName_issuesDistinctResults() async {
        // A narrow alphabet on purpose (#692): the law fails only where one drawn name equals another
        // plus the decoration, and a generator drawing realistic names never collides.
        let firstCollision: @Sendable ([String]) -> String? = { names in
            var state: Set<String> = []
            var issued: [String: Int] = [:]
            for (position, name) in names.enumerated() {
                let result = String(describing: uniquifierWitnessCaseName(for: name, taken: &state))
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
            stateA: 0x7469A1F81D4A045A,
            stateB: 0xC19B085C20BF3536,
            stateC: 0xC43981C591AE7625,
            stateD: 0x2E4620137D5C0FDF
        )
        let result = await backend.check(
            trials: 100,
            seed: seed,
            sample: { rng in
                let dense = Bool.random(using: &rng)
                let pool = dense ? ["a", "a1", "b", "b1"] : [
                    "a", "a0", "a1", "a2", "a10", "a11", "b", "b0", "b1", "b2", "b10", "b11"
                ]
                let count = Int.random(in: dense ? 11 ... 24 : 1 ... 16, using: &rng)
                return (0 ..< count).map { _ in pool.randomElement(using: &rng) ?? "a" }
            },
            property: { names in firstCollision(names) == nil }
        )
        if case let .failed(_, _, input, _) = result {
            Issue.record(
                "uniquifierWitnessCaseName(for:taken:) issued one result twice: \(firstCollision(input) ?? "")"
            )
        }
    }
}

struct UniquifierWitnessAllocatorIssueUniquifierTests {

    @Test func issue_issuesDistinctResults() async {
        // A narrow alphabet on purpose (#692): the law fails only where one drawn name equals another
        // plus the decoration, and a generator drawing realistic names never collides.
        let firstCollision: @Sendable ([String]) -> String? = { names in
            var subject = UniquifierWitnessAllocator(reserving: names)
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
            stateA: 0x7C9BE29EB0FACE3A,
            stateB: 0x04EA97A6B5DF129E,
            stateC: 0x562C71973C0DD97B,
            stateD: 0xDFD7BB00A68D20D5
        )
        let result = await backend.check(
            trials: 100,
            seed: seed,
            sample: { rng in
                let dense = Bool.random(using: &rng)
                let pool = dense ? ["a", "a_1", "b", "b_1"] : [
                    "a", "a_0", "a_1", "a_2", "a_10", "a_11", "b", "b_0", "b_1", "b_2", "b_10", "b_11"
                ]
                let count = Int.random(in: dense ? 11 ... 24 : 1 ... 16, using: &rng)
                return (0 ..< count).map { _ in pool.randomElement(using: &rng) ?? "a" }
            },
            property: { names in firstCollision(names) == nil }
        )
        if case let .failed(_, _, input, _) = result {
            Issue.record("issue(for:) issued one result twice: \(firstCollision(input) ?? "")")
        }
    }
}

// The defect's stub fails by design, so it runs only under `withKnownIssue`, from
// `UniquifierStubCompiledWitnessTests.theStubRefutesTheDefect`.
@Suite(.disabled("refutes #669's defect by design; run under withKnownIssue"))
struct UniquifierWitnessRefuted {
    struct UniquifierWitnessDefectiveNamerUniqNameUniquifierTests {

        @Test func uniqName_issuesDistinctResults() async {
            // A narrow alphabet on purpose (#692): the law fails only where one drawn name equals another
            // plus the decoration, and a generator drawing realistic names never collides.
            let firstCollision: @Sendable ([String]) -> String? = { names in
                let subject = UniquifierWitnessDefectiveNamer()
                var issued: [String: Int] = [:]
                for (position, name) in names.enumerated() {
                    let result = String(describing: subject.uniqName(name))
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
                stateA: 0x3DFDE58B35D595E8,
                stateB: 0x79E7A9986CC06182,
                stateC: 0x0911D72AD40D16B1,
                stateD: 0xD7F20FDC3CA7A54B
            )
            let result = await backend.check(
                trials: 100,
                seed: seed,
                sample: { rng in
                    let dense = Bool.random(using: &rng)
                    let pool = dense ? ["a", "a1", "b", "b1"] : [
                        "a", "a0", "a1", "a2", "a10", "a11", "b", "b0", "b1", "b2", "b10", "b11"
                    ]
                    let count = Int.random(in: dense ? 11 ... 24 : 1 ... 16, using: &rng)
                    return (0 ..< count).map { _ in pool.randomElement(using: &rng) ?? "a" }
                },
                property: { names in firstCollision(names) == nil }
            )
            if case let .failed(_, _, input, _) = result {
                Issue.record("uniqName(_:) issued one result twice: \(firstCollision(input) ?? "")")
            }
        }
    }
}
