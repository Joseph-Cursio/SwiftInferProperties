import Foundation

/// Why a property test written in another module cannot call a function.
///
/// The scanner drops these from discovery, and rightly: an external verifier compiles its test in
/// a separate module and imports the target, so a symbol it cannot name is a suggestion that can
/// only fail later as `architectural-coverage-pending`. Per PRD §3.5 — high precision, fewer
/// suggestions — surfacing them unsolicited would be noise.
///
/// But *silently* dropping them is a different thing, and it is what turned the tool blind on
/// application code. The access rules were calibrated against library corpora (swift-numerics,
/// swift-collections, swift-algorithms), where `private` genuinely is an implementation detail and
/// the interesting surface is the public API. An **app has no public API**. Its pure logic lives
/// almost entirely in `private` helpers inside views and view models — `private func
/// isValidFolderName`, `private func getFileIcon` — which are precisely its best property
/// candidates, and precisely what this drops. The precision lever tuned on libraries is the thing
/// that hides the properties in an app.
///
/// So the reason is kept rather than thrown away. When a **seed** names one of these functions the
/// producer has explicitly asked for it, and silently overruling an explicit request is not
/// precision — it is a confident zero. The suggestion is surfaced with the access caveat attached,
/// naming the one refactor that unlocks it.
public enum AccessRestriction: String, Sendable, Equatable, Codable {
    /// `private` or `fileprivate`. Not even `@testable import` reaches these.
    case notVisibleToTests

    /// An explicit `internal` modifier, an `@_spi` attribute, an `_`-prefixed carrier, or a
    /// deliberately non-public enclosing type — deliberately-marked internal surface.
    case internalOrSPI

    /// A function declared inside another body, reachable only through it.
    case nestedLocal

    /// What a reader has to do to make this function property-testable.
    public var remedy: String {
        switch self {
        case .notVisibleToTests:
            return "it is `private` or `fileprivate`, so no test can call it — not even with "
                + "`@testable import`. Widen it to `internal` (a test target using `@testable "
                + "import` will see it), or lift the logic into a type of its own."

        case .internalOrSPI:
            return "it is marked internal or SPI, so a test in another module cannot call it. A "
                + "same-package test target using `@testable import` can — otherwise widen it."

        case .nestedLocal:
            return "it is a local function inside another body, so nothing can call it directly. "
                + "Lift it out to a member or a free function."
        }
    }
}

/// A function the scan found and set aside because no external test could call it, kept with the
/// reason so a seed that names it can rescue it — with the caveat attached.
public struct RestrictedFunction: Sendable, Equatable {
    public let summary: FunctionSummary
    public let restriction: AccessRestriction

    public init(summary: FunctionSummary, restriction: AccessRestriction) {
        self.summary = summary
        self.restriction = restriction
    }
}
