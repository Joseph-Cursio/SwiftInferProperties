import Foundation
import PropertyLawKit
import Testing

// A COMPILED witness for the reference oracle `discover --docstring-advice` prints.
// `ReferenceOracleDiscoverWitnessTests` scans the subjects below, builds each scaffold through
// discover's own path, fills in its `fatalError(...)` line, and checks this file holds the result
// byte for byte. Keep the subjects above WITNESS-BEGIN, and add new ones after the old: each
// scaffold's seed comes from its law's identity, which names the subject's line.

enum OracleDiscoverInbox {
    struct Message {
        let size: Int
    }

    /// Returns the size of the largest message, or nil when there are none.
    static func largest(in messages: [Message]) -> Int? { messages.map(\.size).max() }
}

struct OracleDiscoverRuler {
    let unit: Int

    /// Returns the length times the unit, never negative.
    func scaled(_ length: Int) -> Int { Swift.max(length &* unit, 0) }
}

final class OracleDiscoverTally {
    let total: Int

    init(total: Int) {
        self.total = total
    }

    /// Returns the total plus the amount, and leaves the tally unchanged.
    func adding(_ amount: Int) -> Int { total &+ amount }
}

enum OracleDiscoverLibrary {
    struct Book: Equatable {
        let pages: Int
    }

    enum Shelf {
        /// Returns the book with its page count doubled, wrapping on overflow.
        static func thickened(_ book: Book) -> Book { Book(pages: book.pages &* 2) }
    }
}

struct OracleDiscoverAccount {
    typealias OwnerID = Int

    let owner: Int

    /// Returns whether the id owns the account, exactly when the two match.
    func isOwned(by id: OwnerID) -> Bool { owner == id }
}

struct OracleDiscoverBead {
    let weight: Int
}

extension [OracleDiscoverBead] {
    /// Returns the total weight plus the bonus, wrapping on overflow.
    func totalWeight(plus bonus: Int) -> Int { reduce(bonus) { $0 &+ $1.weight } }
}

// WITNESS-BEGIN — printed text, verbatim; the rules below are the ones it trips.
// swiftlint:disable closure_end_indentation identifier_name line_length
// Fill in the reference definition below — your docstring already states it:
//   "Returns the size of the largest message, or nil when there are none."
// Then run the test: the generator finds the input where the code disagrees
// with its own documentation.
// (the return type Int? must be Equatable for this to compile)
// Inputs must be Sendable. Declare each of these once per test target, and delete it if SwiftInferSendableShims.swift or another scaffold already does:
extension OracleDiscoverInbox.Message: @unchecked Sendable {}
extension OracleDiscoverInbox {
    static func largest_reference(in messages: [OracleDiscoverInbox.Message]) -> Int? {
        messages.map(\.size).max()
    }
}

@Test func OracleDiscoverInbox_largest_matchesReferenceDefinition() async {
    let backend = SwiftPropertyBasedBackend()
    let seed = Seed(
        stateA: 0x4BA11C1AF892BB01,
        stateB: 0xBD75C94310C96768,
        stateC: 0xB60090859ED5CFE2,
        stateD: 0x670A50325CBFC93A
    )
    let result = await backend.check(
        trials: 100,
        seed: seed,
        sample: { rng in (Gen<Int>.int().map { OracleDiscoverInbox.Message(size: $0) }.array(of: 0...8)).run(using: &rng) },
        property: { value in OracleDiscoverInbox.largest(in: value) == OracleDiscoverInbox.largest_reference(in: value) }
    )
    if case let .failed(_, _, input, error) = result {
        Issue.record(
            "OracleDiscoverInbox.largest(in:) disagrees with its documented reference definition at input \(input). \(error?.message ?? "")"
        )
    }
}

// Fill in the reference definition below — your docstring already states it:
//   "Returns the length times the unit, never negative."
// Then run the test: the generator finds the input where the code disagrees
// with its own documentation.
// (the return type Int must be Equatable for this to compile)
// Inputs must be Sendable. Declare each of these once per test target, and delete it if SwiftInferSendableShims.swift or another scaffold already does:
extension OracleDiscoverRuler: @unchecked Sendable {}
extension OracleDiscoverRuler {
    func scaled_reference(_ length: Int) -> Int {
        Swift.max(unit &* length, 0)
    }
}

@Test func OracleDiscoverRuler_scaled_matchesReferenceDefinition() async {
    let backend = SwiftPropertyBasedBackend()
    let seed = Seed(
        stateA: 0x5693D4F010F0ACE4,
        stateB: 0x65EE1313A13AEE83,
        stateC: 0x414C51D8BBD552BA,
        stateD: 0x26D346AC8C9EA601
    )
    let result = await backend.check(
        trials: 100,
        seed: seed,
        sample: { rng in
                    let arg0 = (Gen<Int>.int().map { OracleDiscoverRuler(unit: $0) }).run(using: &rng)
                    let arg1 = (Gen.frequency((3.0, Gen<Int>.boundedForArithmetic()), (2.0, Gen<Int?>.element(of: [0, -1, 1] as [Int]).map { $0! }))).run(using: &rng)
                    return (arg0, arg1)
                },
        property: { (args: (OracleDiscoverRuler, Int)) in args.0.scaled(args.1) == args.0.scaled_reference(args.1) }
    )
    if case let .failed(_, _, input, error) = result {
        Issue.record(
            "OracleDiscoverRuler.scaled(_:) disagrees with its documented reference definition at input \(input). \(error?.message ?? "")"
        )
    }
}

// Fill in the reference definition below — your docstring already states it:
//   "Returns the total plus the amount, and leaves the tally unchanged."
// Then run the test: the generator finds the input where the code disagrees
// with its own documentation.
// (the return type Int must be Equatable for this to compile)
// Inputs must be Sendable. Declare each of these once per test target, and delete it if SwiftInferSendableShims.swift or another scaffold already does:
extension OracleDiscoverTally: @unchecked Sendable {}
extension OracleDiscoverTally {
    func adding_reference(_ amount: Int) -> Int {
        amount &+ total
    }
}

@Test func OracleDiscoverTally_adding_matchesReferenceDefinition() async {
    let backend = SwiftPropertyBasedBackend()
    let seed = Seed(
        stateA: 0xDA3B00AEB1DD2066,
        stateB: 0x80901CA4E94A8E04,
        stateC: 0x82A7AB111CFF8D1C,
        stateD: 0x275244A6A2AC783B
    )
    let result = await backend.check(
        trials: 100,
        seed: seed,
        sample: { rng in
                    let arg0 = (Gen<Int>.int().map { OracleDiscoverTally(total: $0) }).run(using: &rng)
                    let arg1 = (Gen.frequency((3.0, Gen<Int>.boundedForArithmetic()), (2.0, Gen<Int?>.element(of: [0, -1, 1] as [Int]).map { $0! }))).run(using: &rng)
                    return (arg0, arg1)
                },
        property: { (args: (OracleDiscoverTally, Int)) in args.0.adding(args.1) == args.0.adding_reference(args.1) }
    )
    if case let .failed(_, _, input, error) = result {
        Issue.record(
            "OracleDiscoverTally.adding(_:) disagrees with its documented reference definition at input \(input). \(error?.message ?? "")"
        )
    }
}

// Fill in the reference definition below — your docstring already states it:
//   "Returns the book with its page count doubled, wrapping on overflow."
// Then run the test: the generator finds the input where the code disagrees
// with its own documentation.
// (the return type OracleDiscoverLibrary.Book must be Equatable for this to compile)
// Inputs must be Sendable. Declare each of these once per test target, and delete it if SwiftInferSendableShims.swift or another scaffold already does:
extension OracleDiscoverLibrary.Book: @unchecked Sendable {}
extension OracleDiscoverLibrary.Shelf {
    static func thickened_reference(_ book: OracleDiscoverLibrary.Book) -> OracleDiscoverLibrary.Book {
        OracleDiscoverLibrary.Book(pages: book.pages &* 2)
    }
}

@Test func OracleDiscoverLibrary_Shelf_thickened_matchesReferenceDefinition() async {
    let backend = SwiftPropertyBasedBackend()
    let seed = Seed(
        stateA: 0x0173A8192105121D,
        stateB: 0xE60F5D2A77DB7D01,
        stateC: 0xBF5947150161D9DC,
        stateD: 0xC574236278A5865B
    )
    let result = await backend.check(
        trials: 100,
        seed: seed,
        sample: { rng in (Gen<Int>.int().map { OracleDiscoverLibrary.Book(pages: $0) }).run(using: &rng) },
        property: { value in OracleDiscoverLibrary.Shelf.thickened(value) == OracleDiscoverLibrary.Shelf.thickened_reference(value) }
    )
    if case let .failed(_, _, input, error) = result {
        Issue.record(
            "OracleDiscoverLibrary.Shelf.thickened(_:) disagrees with its documented reference definition at input \(input). \(error?.message ?? "")"
        )
    }
}

// Fill in the reference definition below — your docstring already states it:
//   "Returns whether the id owns the account, exactly when the two match."
// Then run the test: the generator finds the input where the code disagrees
// with its own documentation.
// Inputs must be Sendable. Declare each of these once per test target, and delete it if SwiftInferSendableShims.swift or another scaffold already does:
extension OracleDiscoverAccount: @unchecked Sendable {}
extension OracleDiscoverAccount {
    func isOwned_reference(by id: OracleDiscoverAccount.OwnerID) -> Bool {
        id == owner
    }
}

@Test func OracleDiscoverAccount_isOwned_matchesReferenceDefinition() async {
    let backend = SwiftPropertyBasedBackend()
    let seed = Seed(
        stateA: 0xDD899EE9AD5520A1,
        stateB: 0x80BA439A1E8FA619,
        stateC: 0x99530609D1ABC64C,
        stateD: 0x531EF36F765E1C03
    )
    let result = await backend.check(
        trials: 100,
        seed: seed,
        sample: { rng in
                    let arg0 = (Gen<Int>.int().map { OracleDiscoverAccount(owner: $0) }).run(using: &rng)
                    let arg1 = (Gen<Int>.int()).run(using: &rng)
                    return (arg0, arg1)
                },
        property: { (args: (OracleDiscoverAccount, OracleDiscoverAccount.OwnerID)) in args.0.isOwned(by: args.1) == args.0.isOwned_reference(by: args.1) }
    )
    if case let .failed(_, _, input, error) = result {
        Issue.record(
            "OracleDiscoverAccount.isOwned(by:) disagrees with its documented reference definition at input \(input). \(error?.message ?? "")"
        )
    }
}

// Fill in the reference definition below — your docstring already states it:
//   "Returns the total weight plus the bonus, wrapping on overflow."
// Then run the test: the generator finds the input where the code disagrees
// with its own documentation.
// (the return type Int must be Equatable for this to compile)
// Inputs must be Sendable. Declare each of these once per test target, and delete it if SwiftInferSendableShims.swift or another scaffold already does:
extension OracleDiscoverBead: @unchecked Sendable {}
extension [OracleDiscoverBead] {
    func totalWeight_reference(plus bonus: Int) -> Int {
        map(\.weight).reduce(bonus, &+)
    }
}

@Test func OracleDiscoverBead_totalWeight_matchesReferenceDefinition() async {
    let backend = SwiftPropertyBasedBackend()
    let seed = Seed(
        stateA: 0xABC7634FA75748CB,
        stateB: 0xA9BA628FAD929CBB,
        stateC: 0x199DAAF8495AEA37,
        stateD: 0x942FD316EBAA6B56
    )
    let result = await backend.check(
        trials: 100,
        seed: seed,
        sample: { rng in
                    let arg0 = (Gen<Int>.int().map { OracleDiscoverBead(weight: $0) }.array(of: 0...8)).run(using: &rng)
                    let arg1 = (Gen.frequency((3.0, Gen<Int>.boundedForArithmetic()), (2.0, Gen<Int?>.element(of: [0, -1, 1] as [Int]).map { $0! }))).run(using: &rng)
                    return (arg0, arg1)
                },
        property: { (args: ([OracleDiscoverBead], Int)) in args.0.totalWeight(plus: args.1) == args.0.totalWeight_reference(plus: args.1) }
    )
    if case let .failed(_, _, input, error) = result {
        Issue.record(
            "[OracleDiscoverBead].totalWeight(plus:) disagrees with its documented reference definition at input \(input). \(error?.message ?? "")"
        )
    }
}
// swiftlint:enable closure_end_indentation identifier_name line_length
