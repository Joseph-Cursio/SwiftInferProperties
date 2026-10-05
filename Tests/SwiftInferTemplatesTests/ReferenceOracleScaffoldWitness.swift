import Foundation
import PropertyLawKit
import Testing

// A COMPILED witness for the docstring advisory's reference-oracle scaffold.
// `ReferenceOracleScaffoldWitnessTests` emits each case below, replaces its one `fatalError(...)`
// line with a correct body, and checks this file holds the result byte for byte — so the test
// target building is the proof the emitted text compiles once that line is filled in, and the
// `@Test`s passing is the proof the law holds for a right reference. The subjects come first;
// the region after WITNESS-BEGIN is generated, never edited by hand.

/// W1 — a static member over its own nested type, returning an Optional.
enum OracleWitnessInbox {
    struct Message: Sendable {
        let size: Int
    }

    static func largest(in messages: [Message]) -> Int? { messages.map(\.size).max() }
}

enum OracleWitnessError: Error {
    case negativeKelvin
    case notANumber
}

/// W2 — a throwing instance method; the receiver is drawn.
struct OracleWitnessTemperature: Sendable {
    let kelvin: Int

    func celsius(offset: Int) throws -> Int {
        guard kelvin >= 0 else { throw OracleWitnessError.negativeKelvin }
        return kelvin - 273 + offset
    }
}

/// W3 — an actor instance method (one `await`) and a `nonisolated` member (none).
actor OracleWitnessCounter {
    let base: Int

    init(base: Int) {
        self.base = base
    }

    func advanced(by step: Int) -> Int { base &+ step }

    nonisolated func doubled(_ step: Int) -> Int { step &* 2 }
}

/// W4 — a `@MainActor` static, reached through one `MainActor.run` hop.
@MainActor
enum OracleWitnessSidebar {
    static func title(for count: Int) -> String { "Inbox (\(count))" }
}

/// W5 — an async static, and an async throwing one.
enum OracleWitnessLoader {
    static func load(_ text: String) async -> Int {
        await Task.yield()
        return text.count
    }

    static func decode(_ text: String) async throws -> Int {
        await Task.yield()
        guard let value = Int(text) else { throw OracleWitnessError.notANumber }
        return value
    }
}

// WITNESS-BEGIN — emitted text, verbatim; the rules below are the ones it trips.
// swiftlint:disable closure_end_indentation identifier_name line_length
// W1
// Fill in the reference definition below — your docstring already states it:
//   "Returns the size of the largest message, or nil when there are none."
// Then run the test: the generator finds the input where the code disagrees
// with its own documentation.
// (the return type Int? must be Equatable for this to compile)
extension OracleWitnessInbox {
    static func largest_reference(in messages: [Message]) -> Int? {
        messages.map(\.size).max()
    }
}

@Test func OracleWitnessInbox_largest_matchesReferenceDefinition() async {
    let backend = SwiftPropertyBasedBackend()
    let seed = Seed(
        stateA: 0x0000000000005EED,
        stateB: 0x0000000000C0FFEE,
        stateC: 0x000000000000BEEF,
        stateD: 0x000000000000F00D
    )
    let result = await backend.check(
        trials: 100,
        seed: seed,
        sample: { rng in (Gen<Int>.int(in: 0...99).map { OracleWitnessInbox.Message(size: $0) }.array(of: 0...8)).run(using: &rng) },
        property: { value in OracleWitnessInbox.largest(in: value) == OracleWitnessInbox.largest_reference(in: value) }
    )
    if case let .failed(_, _, input, error) = result {
        Issue.record(
            "OracleWitnessInbox.largest(in:) disagrees with its documented reference definition at input \(input). \(error?.message ?? "")"
        )
    }
}

// W2
// Fill in the reference definition below — your docstring already states it:
//   "Returns the temperature in Celsius plus the offset; throws for a negative Kelvin reading."
// Then run the test: the generator finds the input where the code disagrees
// with its own documentation.
// It throws, so both sides are compared through try?: throwing on the same inputs counts as agreeing (which error is not compared).
// (the return type Int must be Equatable for this to compile)
extension OracleWitnessTemperature {
    func celsius_reference(offset: Int) throws -> Int {
        if kelvin < 0 { throw OracleWitnessError.negativeKelvin }; return offset + kelvin - 273
    }
}

@Test func OracleWitnessTemperature_celsius_matchesReferenceDefinition() async {
    let backend = SwiftPropertyBasedBackend()
    let seed = Seed(
        stateA: 0x0000000000005EED,
        stateB: 0x0000000000C0FFEE,
        stateC: 0x000000000000BEEF,
        stateD: 0x000000000000F00D
    )
    let result = await backend.check(
        trials: 100,
        seed: seed,
        sample: { rng in
                    let arg0 = (Gen<Int>.int(in: -300...300).map { OracleWitnessTemperature(kelvin: $0) }).run(using: &rng)
                    let arg1 = (Gen.frequency((3.0, Gen<Int>.boundedForArithmetic()), (2.0, Gen<Int?>.element(of: [0, -1, 1] as [Int]).map { $0! }))).run(using: &rng)
                    return (arg0, arg1)
                },
        property: { (args: (OracleWitnessTemperature, Int)) in (try? args.0.celsius(offset: args.1)) == (try? args.0.celsius_reference(offset: args.1)) }
    )
    if case let .failed(_, _, input, error) = result {
        Issue.record(
            "OracleWitnessTemperature.celsius(offset:) disagrees with its documented reference definition at input \(input). \(error?.message ?? "")"
        )
    }
}

// W3a
// Fill in the reference definition below — your docstring already states it:
//   "Returns the base advanced by the step."
// Then run the test: the generator finds the input where the code disagrees
// with its own documentation.
// (the return type Int must be Equatable for this to compile)
extension OracleWitnessCounter {
    func advanced_reference(by step: Int) -> Int {
        step &+ base
    }
}

@Test func OracleWitnessCounter_advanced_matchesReferenceDefinition() async {
    let backend = SwiftPropertyBasedBackend()
    let seed = Seed(
        stateA: 0x0000000000005EED,
        stateB: 0x0000000000C0FFEE,
        stateC: 0x000000000000BEEF,
        stateD: 0x000000000000F00D
    )
    let result = await backend.check(
        trials: 100,
        seed: seed,
        sample: { rng in
                    let arg0 = (Gen<Int>.int(in: -99...99).map { OracleWitnessCounter(base: $0) }).run(using: &rng)
                    let arg1 = (Gen.frequency((3.0, Gen<Int>.boundedForArithmetic()), (2.0, Gen<Int?>.element(of: [0, -1, 1] as [Int]).map { $0! }))).run(using: &rng)
                    return (arg0, arg1)
                },
        property: { (args: (OracleWitnessCounter, Int)) in await args.0.advanced(by: args.1) == args.0.advanced_reference(by: args.1) }
    )
    if case let .failed(_, _, input, error) = result {
        Issue.record(
            "OracleWitnessCounter.advanced(by:) disagrees with its documented reference definition at input \(input). \(error?.message ?? "")"
        )
    }
}

// W3b
// Fill in the reference definition below — your docstring already states it:
//   "Returns the step doubled, and never reads the counter."
// Then run the test: the generator finds the input where the code disagrees
// with its own documentation.
// (the return type Int must be Equatable for this to compile)
extension OracleWitnessCounter {
    nonisolated func doubled_reference(_ step: Int) -> Int {
        step &+ step
    }
}

@Test func OracleWitnessCounter_doubled_matchesReferenceDefinition() async {
    let backend = SwiftPropertyBasedBackend()
    let seed = Seed(
        stateA: 0x0000000000005EED,
        stateB: 0x0000000000C0FFEE,
        stateC: 0x000000000000BEEF,
        stateD: 0x000000000000F00D
    )
    let result = await backend.check(
        trials: 100,
        seed: seed,
        sample: { rng in
                    let arg0 = (Gen<Int>.int(in: -99...99).map { OracleWitnessCounter(base: $0) }).run(using: &rng)
                    let arg1 = (Gen.frequency((3.0, Gen<Int>.boundedForArithmetic()), (2.0, Gen<Int?>.element(of: [0, -1, 1] as [Int]).map { $0! }))).run(using: &rng)
                    return (arg0, arg1)
                },
        property: { (args: (OracleWitnessCounter, Int)) in args.0.doubled(args.1) == args.0.doubled_reference(args.1) }
    )
    if case let .failed(_, _, input, error) = result {
        Issue.record(
            "OracleWitnessCounter.doubled(_:) disagrees with its documented reference definition at input \(input). \(error?.message ?? "")"
        )
    }
}

// W4
// Fill in the reference definition below — your docstring already states it:
//   "Returns the inbox title, with the count in parentheses."
// Then run the test: the generator finds the input where the code disagrees
// with its own documentation.
// (the return type String must be Equatable for this to compile)
extension OracleWitnessSidebar {
    static func title_reference(for count: Int) -> String {
        "Inbox (" + String(count) + ")"
    }
}

@Test func OracleWitnessSidebar_title_matchesReferenceDefinition() async {
    let backend = SwiftPropertyBasedBackend()
    let seed = Seed(
        stateA: 0x0000000000005EED,
        stateB: 0x0000000000C0FFEE,
        stateC: 0x000000000000BEEF,
        stateD: 0x000000000000F00D
    )
    let result = await backend.check(
        trials: 100,
        seed: seed,
        sample: { rng in (Gen.frequency((3.0, Gen<Int>.boundedForArithmetic()), (2.0, Gen<Int?>.element(of: [0, -1, 1] as [Int]).map { $0! }))).run(using: &rng) },
        property: { value in await MainActor.run { OracleWitnessSidebar.title(for: value) == OracleWitnessSidebar.title_reference(for: value) } }
    )
    if case let .failed(_, _, input, error) = result {
        Issue.record(
            "OracleWitnessSidebar.title(for:) disagrees with its documented reference definition at input \(input). \(error?.message ?? "")"
        )
    }
}

// W5a
// Fill in the reference definition below — your docstring already states it:
//   "Returns the number of characters in the text."
// Then run the test: the generator finds the input where the code disagrees
// with its own documentation.
// (the return type Int must be Equatable for this to compile)
extension OracleWitnessLoader {
    static func load_reference(_ text: String) async -> Int {
        text.count
    }
}

@Test func OracleWitnessLoader_load_matchesReferenceDefinition() async {
    let backend = SwiftPropertyBasedBackend()
    let seed = Seed(
        stateA: 0x0000000000005EED,
        stateB: 0x0000000000C0FFEE,
        stateC: 0x000000000000BEEF,
        stateD: 0x000000000000F00D
    )
    let result = await backend.check(
        trials: 100,
        seed: seed,
        sample: { rng in (Gen<Character>.letterOrNumber.string(of: 0...8)).run(using: &rng) },
        property: { value in (await OracleWitnessLoader.load(value)) == (await OracleWitnessLoader.load_reference(value)) }
    )
    if case let .failed(_, _, input, error) = result {
        Issue.record(
            "OracleWitnessLoader.load(_:) disagrees with its documented reference definition at input \(input). \(error?.message ?? "")"
        )
    }
}

// W5b
// Fill in the reference definition below — your docstring already states it:
//   "Returns the decimal number the text spells, and throws when it spells none."
// Then run the test: the generator finds the input where the code disagrees
// with its own documentation.
// It throws, so both sides are compared through try?: throwing on the same inputs counts as agreeing (which error is not compared).
// (the return type Int must be Equatable for this to compile)
extension OracleWitnessLoader {
    static func decode_reference(_ text: String) async throws -> Int {
        guard let value = Int(text) else { throw OracleWitnessError.notANumber }; return value
    }
}

@Test func OracleWitnessLoader_decode_matchesReferenceDefinition() async {
    let backend = SwiftPropertyBasedBackend()
    let seed = Seed(
        stateA: 0x0000000000005EED,
        stateB: 0x0000000000C0FFEE,
        stateC: 0x000000000000BEEF,
        stateD: 0x000000000000F00D
    )
    let result = await backend.check(
        trials: 100,
        seed: seed,
        sample: { rng in (Gen<Character>.letterOrNumber.string(of: 0...8)).run(using: &rng) },
        property: { value in (try? await OracleWitnessLoader.decode(value)) == (try? await OracleWitnessLoader.decode_reference(value)) }
    )
    if case let .failed(_, _, input, error) = result {
        Issue.record(
            "OracleWitnessLoader.decode(_:) disagrees with its documented reference definition at input \(input). \(error?.message ?? "")"
        )
    }
}
// swiftlint:enable closure_end_indentation identifier_name line_length
