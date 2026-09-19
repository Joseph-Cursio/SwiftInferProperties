@testable import SwiftInferCore
import Testing

/// **A member of a nested type is recorded with its full type path, whatever its declaration kind.**
///
/// The function path joined the whole type stack; the computed-property path passed nothing and
/// so fell back to the innermost name. `ThinkState.Mode.next` recorded its receiver as `Mode`, and
/// its idempotence stub annotated `{ (value: Mode) in … }` — a name a test file cannot see
/// (SwiftAssist, 2026-09-19 corpus funnel).
@Suite("Scanner — nested types are recorded fully qualified")
struct NestedTypeQualificationTests {

    private static let source = """
    struct ThinkState {
        enum Mode {
            case normal, thinking
            var next: Mode { self == .normal ? .thinking : .normal }
            func toggled() -> Mode { next }
        }
    }
    """

    @Test("a computed property on a nested type records the full path")
    func computedProperty() throws {
        let summary = try #require(
            FunctionScanner.scan(source: Self.source, file: "T.swift").first { $0.name == "next" }
        )
        #expect(summary.qualifiedContainingTypeName == "ThinkState.Mode")
        #expect(summary.containingTypeName == "Mode")
    }

    /// The control: the function path already did this, and the two must agree.
    @Test("a method on the same type agrees")
    func methodAgrees() throws {
        let summary = try #require(
            FunctionScanner.scan(source: Self.source, file: "T.swift").first { $0.name == "toggled" }
        )
        #expect(summary.qualifiedContainingTypeName == "ThinkState.Mode")
    }
}
