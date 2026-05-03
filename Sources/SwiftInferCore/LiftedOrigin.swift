/// Opaque origin tag attached to a `Suggestion` that was promoted from a
/// `LiftedSuggestion` (TestLifter M3.0). Carries the originating test
/// method's name + source location so the M3.3 accept-flow can name the
/// writeout file (`<TestMethodName>_lifted_<TemplateName>.swift`) and
/// emit a provenance comment header pointing back at the test body.
///
/// `nil` for TemplateEngine-originated suggestions (the field on
/// `Suggestion` is `liftedOrigin: LiftedOrigin?` with default `nil`,
/// so existing TemplateEngine call sites are unchanged).
///
/// **Why a Core-side type rather than a TestLifter-side type:** the
/// `Suggestion` record itself lives in `SwiftInferCore`, and the
/// downstream renderer / accept-flow / drift / baseline consumers all
/// see `Suggestion` not `LiftedSuggestion`. Putting `LiftedOrigin` in
/// Core lets the field hang off `Suggestion` without forcing
/// `SwiftInferCore` to depend on `SwiftInferTestLifter` (which would be
/// a layering inversion). The field is opaque to Core — Core never
/// reads it; only `SwiftInferCLI`'s accept-flow does.
public struct LiftedOrigin: Sendable, Equatable {

    /// Name of the originating test method (e.g. `"testRoundTrip"`).
    /// Used by `InteractiveTriage+Accept`'s file-naming function (M3.3)
    /// to produce the `<TestMethodName>_lifted_<TemplateName>.swift`
    /// infix that disambiguates lifted writeouts from TemplateEngine-
    /// accepted writeouts within the same `Tests/Generated/SwiftInfer/
    /// <template>/` subdirectory.
    public let testMethodName: String

    /// Source location of the test method declaration (the `func`
    /// keyword for an XCTest method or the `@Test func` for a Swift
    /// Testing test). Used by the M3.3 accept-flow's provenance comment
    /// header — "Lifted from `<file>:<line>` `<testMethodName>()`".
    public let sourceLocation: SourceLocation

    public init(testMethodName: String, sourceLocation: SourceLocation) {
        self.testMethodName = testMethodName
        self.sourceLocation = sourceLocation
    }
}
