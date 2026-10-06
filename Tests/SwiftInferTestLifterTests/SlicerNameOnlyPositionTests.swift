@testable import SwiftInferTestLifter
import SwiftSyntax
import Testing

/// The backward slice follows names that READ a binding, and only those.
///
/// ⚠ **The collector recorded every `DeclReferenceExprSyntax`**, member names and key-path
/// component names included, so the `id` in `.map(\.id)` and in `{ $0.id }` reached back to an
/// unrelated `let id = 7`. That binding moved into the property region, and a literal the
/// assertion never reads became a parameterized value. Its own doc says member accesses
/// contribute their BASE, which is what it does now.
@Suite("Slicer — key-path and member names are not references")
struct SlicerNameOnlyPositionTests {

    /// A body binding an unrelated `let id = 7` and the `items` the assertion reads.
    private static func slice(asserting assertion: String) -> SlicedTestBody {
        SlicerTestHelper.sliceFirstBody(in: """
        import XCTest
        final class T: XCTestCase {
            func testSortKeepsIDs() {
                let id = 7
                let items = makeItems()
                \(assertion)
            }
        }
        """)
    }

    /// `let id = 7` stays in setup; `let items` and the assertion are the property region.
    private static func expectIDLeftInSetup(_ slice: SlicedTestBody) {
        #expect(slice.setup.map(\.trimmedDescription) == ["let id = 7"])
        #expect(slice.propertyRegion.map(\.trimmedDescription).first == "let items = makeItems()")
        #expect(slice.propertyRegion.count == 2)
        #expect(slice.parameterizedValues.isEmpty)
    }

    @Test("a key-path component sharing a local's name does not pull the local into the slice")
    func keyPathComponentNameIsNotAReference() {
        Self.expectIDLeftInSetup(Self.slice(
            asserting: #"XCTAssertEqual(sortItems(items).map(\.id).sorted(), items.map(\.id).sorted())"#
        ))
    }

    @Test("a member name sharing a local's name does not pull the local into the slice")
    func memberNameIsNotAReference() {
        Self.expectIDLeftInSetup(Self.slice(
            asserting: "XCTAssertEqual(sortItems(items).map { $0.id }.sorted(), items.map { $0.id }.sorted())"
        ))
    }

    /// A test-local is never reached through `self`, so `self.id` is a member name like any other.
    @Test("a member of self sharing a local's name does not pull the local into the slice")
    func selfMemberIsNotAReference() {
        Self.expectIDLeftInSetup(Self.slice(asserting: "XCTAssertEqual(items.count, self.id)"))
    }

    /// The control: a member no local is named after leaves the slice exactly where it was.
    @Test("a member of $0 with no matching local leaves the local in setup")
    func unrelatedMemberLeavesSetupAlone() {
        Self.expectIDLeftInSetup(Self.slice(
            asserting: "XCTAssertEqual(sortItems(items).map { $0.key }.sorted(), items.map { $0.key }.sorted())"
        ))
    }

    /// The BASE of a member access is still a reference, and so is a key-path subscript's
    /// argument, which is evaluated when the key path is formed.
    @Test("a member's base and a key-path subscript's argument are still references")
    func basesAndSubscriptArgumentsAreReferences() {
        let base = Self.slice(asserting: "XCTAssertEqual(items.count, id)")
        #expect(base.setup.isEmpty)
        #expect(base.propertyRegion.count == 3)

        let subscripted = Self.slice(asserting: #"XCTAssertEqual(items.map(\.[id]), [])"#)
        #expect(subscripted.setup.isEmpty)
        #expect(subscripted.propertyRegion.count == 3)
        #expect(subscripted.parameterizedValues.map(\.bindingName) == ["id"])
    }
}
