import Foundation
@testable import SwiftInferCore
import Testing

/// The strict weak ordering `SourceLocation`'s `<` has to satisfy, because five comparators hand it
/// to `sorted(by:)`.
///
/// It was spelled out by hand in each of those five, as a ladder of
/// `if lhs.x.location.file != rhs.x.location.file { … }`, and every one of them stopped at `line`.
/// Two declarations on the same line therefore compared **equal**, and their relative order in the
/// generated output fell to whatever `sorted(by:)` happened to do. Swift does not guarantee that
/// sort is stable, so nothing pinned the order of a tie in a file people read as a diff.
///
/// `sorted(by:)` requires a strict weak ordering; supplying anything else is undefined behaviour,
/// not merely a wrong answer. These are the laws that says so.
@Suite("Source locations are strictly weakly ordered")
struct SourceLocationOrderingTests {

    /// Swift Testing exports its own `SourceLocation`, so the bare name is ambiguous in a test file.
    private typealias Location = SwiftInferCore.SourceLocation

    private static let locations: [Location] = [
        Location(file: "A.swift", line: 1, column: 1),
        Location(file: "A.swift", line: 1, column: 9),
        Location(file: "A.swift", line: 2, column: 1),
        Location(file: "A.swift", line: 10, column: 1),
        Location(file: "B.swift", line: 1, column: 1),
        Location(file: "B.swift", line: 1, column: 2),
        Location(file: "", line: 0, column: 0),
        Location.testBodyPlaceholder
    ]

    // MARK: - The three laws sorted(by:) requires

    @Test("irreflexive — nothing precedes an equal value")
    func irreflexive() {
        // Stated over a distinct-but-equal value rather than the same binding twice. That is the
        // stronger reading of irreflexivity for a value type — `<` must be false for anything that
        // compares equal, not merely for the identical expression — and it avoids SwiftLint's
        // `identical_operands`, which is right in general and wrong for this one law.
        for location in Self.locations {
            let equal = Location(file: location.file, line: location.line, column: location.column)
            #expect(location == equal)
            #expect(!(location < equal))
            #expect(!(equal < location))
        }
    }

    @Test("asymmetric — at most one of a < b and b < a holds")
    func asymmetric() {
        for lhs in Self.locations {
            for rhs in Self.locations {
                #expect(!((lhs < rhs) && (rhs < lhs)), "\(lhs) and \(rhs) each precede the other")
            }
        }
    }

    @Test("transitive")
    func transitive() {
        for lhs in Self.locations {
            for mid in Self.locations where lhs < mid {
                for rhs in Self.locations where mid < rhs {
                    #expect(lhs < rhs, "\(lhs) < \(mid) < \(rhs) but not \(lhs) < \(rhs)")
                }
            }
        }
    }

    @Test("incomparability is transitive, so the order is a strict weak one")
    func incomparabilityIsTransitive() {
        // The clause that separates a strict weak ordering from a merely strict partial one, and
        // the one `sorted(by:)` actually needs. Here equivalence is equality, so this also says the
        // order is total over distinct locations.
        func equivalent(_ lhs: Location, _ rhs: Location) -> Bool {
            !(lhs < rhs) && !(rhs < lhs)
        }
        for lhs in Self.locations {
            for mid in Self.locations where equivalent(lhs, mid) {
                for rhs in Self.locations where equivalent(mid, rhs) {
                    #expect(equivalent(lhs, rhs))
                }
            }
        }
    }

    // MARK: - What the hand-rolled version could not say

    @Test("distinct locations are never equivalent")
    func distinctLocationsAreOrdered() {
        // The defect the five comparators shared: they compared file then line and stopped, so two
        // declarations on one line were indistinguishable to the sort. Including `column` makes the
        // order total, which is what a deterministic generated file needs.
        for lhs in Self.locations {
            for rhs in Self.locations where lhs != rhs {
                #expect((lhs < rhs) || (rhs < lhs), "\(lhs) and \(rhs) are distinct but unordered")
            }
        }
    }

    @Test("sorting does not depend on the order the locations arrived in")
    func sortIsIndependentOfInputOrder() {
        // What a total order buys and a partial one does not: the same set sorts to the same
        // sequence from any starting permutation. With ties, this held only by grace of whatever
        // `sorted(by:)` does with equal elements — which its documentation does not promise.
        let expected = Self.locations.sorted()
        for _ in 0..<25 {
            #expect(Self.locations.shuffled().sorted() == expected)
        }
    }

    @Test("the order is file, then line, then column")
    func orderIsLexicographic() {
        #expect(Location(file: "A.swift", line: 9, column: 1)
                < Location(file: "B.swift", line: 1, column: 1))
        #expect(Location(file: "A.swift", line: 1, column: 9)
                < Location(file: "A.swift", line: 2, column: 1))
        #expect(Location(file: "A.swift", line: 1, column: 1)
                < Location(file: "A.swift", line: 1, column: 2))
    }
}
