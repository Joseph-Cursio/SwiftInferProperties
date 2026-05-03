import SwiftInferCore
import SwiftSyntax

/// One test method's parsed shape — the M1.1 product the M1.2 slicer
/// consumes. Mirrors `SwiftInferCore.FunctionSummary`'s role for
/// production code but covers test methods only.
///
/// `body` retains the SwiftSyntax `CodeBlockSyntax` directly so the
/// slicer can walk it without re-parsing. This couples `TestMethodSummary`
/// to SwiftSyntax internally — fine because the type is consumed by
/// other files in `SwiftInferTestLifter` only; the public TestLifter
/// API surface (M1.4 `LiftedSuggestion`, M1.5 `TestLifter.Artifacts`)
/// holds Sendable value types instead.
public struct TestMethodSummary {

    public enum Harness: Equatable, Sendable {
        /// Method on a class declaring direct inheritance from
        /// `XCTestCase` whose name starts with `test`. Custom test bases
        /// (e.g. project-specific `MyTestCase: XCTestCase`) aren't
        /// recognized in M1; PRD §7.9 doesn't promise transitive
        /// XCTestCase resolution.
        case xctest
        /// Function annotated `@Test` (Swift Testing). Recognized at
        /// any nesting depth — file scope, inside a `@Suite` class /
        /// struct / actor, or inside a non-`@Suite` enclosing type.
        case swiftTesting
    }

    public let harness: Harness

    /// `nil` only for `@Test func` declarations at file scope. XCTest
    /// methods always have a containing class; Swift Testing methods
    /// inside a `@Suite` (or any enclosing type) carry the type name.
    public let className: String?

    public let methodName: String
    public let body: CodeBlockSyntax
    public let location: SwiftInferCore.SourceLocation

    public init(
        harness: Harness,
        className: String?,
        methodName: String,
        body: CodeBlockSyntax,
        location: SwiftInferCore.SourceLocation
    ) {
        self.harness = harness
        self.className = className
        self.methodName = methodName
        self.body = body
        self.location = location
    }
}
