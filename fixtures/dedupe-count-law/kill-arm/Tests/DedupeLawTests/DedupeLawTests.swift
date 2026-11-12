// #671's kill arm (`docs/plans/dedupe-count-law-census-scope.md` §1.3). Three laws and a sanity case over
// SwiftUMLBridge's `dedupe(relationships:)`. Each test is named after its law, so the runner can attribute a
// failure to one cell.
@testable import DedupeSubject
import PropertyBased
import PropertyLawKit
import Testing

/// §1.2: what the stub would draw, written out. `String` leaves are 0–8 letters and digits, the cardinalities
/// are the kit's `.enumCases` (uniform over the four), and `[T]` is `.array(of: 0...8)`.
func relationships() -> Generator<[ERRelationship], some SendableSequenceType> {
    let leaf = Gen<Character>.letterOrNumber.string(of: 0 ... 8)
    let cardinality = Gen<ERCardinality?>.element(of: [.zeroOrOne, .exactlyOne, .zeroOrMany, .oneOrMany] as [ERCardinality])
        .map { $0! }
    let endpoints = zip(leaf, leaf, cardinality, cardinality)
    let labels = zip(leaf, leaf.optional)
    return zip(endpoints, labels).map { ends, names in
        ERRelationship(
            from: ends.0, toEntity: ends.1, fromCardinality: ends.2, toCardinality: ends.3,
            label: names.0, inverseLabel: names.1
        )
    }
    .array(of: 0 ... 8)
}

let seed = Seed(stateA: 0x6710_0001, stateB: 0x6710_0002, stateC: 0x6710_0003, stateD: 0x6710_0004)
let dedupe = CoreDataModelExtractor.dedupe(relationships:)

func check(_ law: String, _ property: @escaping @Sendable ([ERRelationship]) -> Bool) async {
    let result = await SwiftPropertyBasedBackend().check(
        trials: 100, seed: seed, sample: { rng in relationships().run(using: &rng) }, property: property
    )
    if case let .failed(_, _, input, _) = result { Issue.record("\(law) failed at \(input)") }
}

/// C1: a singleton survives. `xs.allSatisfy { f([$0]).count == 1 }`.
@Test func c1() async {
    await check("C1") { xs in xs.allSatisfy { dedupe([$0]).count == 1 } }
}

/// C2: a duplicate of everything adds nothing. `f(xs + xs).count == f(xs).count`.
@Test func c2() async {
    await check("C2") { xs in dedupe(xs + xs).count == dedupe(xs).count }
}

/// The law the run scored: `f(f(xs)) == f(xs)`. The control row.
@Test func idempotence() async {
    await check("idempotence") { xs in dedupe(dedupe(xs)) == dedupe(xs) }
}

/// Not a law: the Bookstore shape, a relationship and its inverse, which the code exists to fold into one.
/// The correct code must return one and pass C1 and C2 on it.
@Test func sanity() {
    let books = ERRelationship(
        from: "Author", toEntity: "Book", fromCardinality: .exactlyOne, toCardinality: .zeroOrMany,
        label: "books", inverseLabel: "author"
    )
    let author = ERRelationship(
        from: "Book", toEntity: "Author", fromCardinality: .zeroOrMany, toCardinality: .exactlyOne,
        label: "author", inverseLabel: "books"
    )
    let pair = [books, author]
    #expect(dedupe(pair) == [books])
    #expect(pair.allSatisfy { dedupe([$0]).count == 1 })
    #expect(dedupe(pair + pair).count == dedupe(pair).count)
}
