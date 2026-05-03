import SwiftInferCore
import SwiftSyntax

/// The result of `Slicer.slice(_:)` — partitions a test method body
/// into the property region (statements that contribute to the
/// terminal assertion's argument values) and the setup region
/// (everything else). Plus the parameterized values found inside the
/// property region — literals + `let x = <literal>` patterns the
/// generated property would generalize over.
///
/// Per PRD §15: an empty property region is the failure mode for tests
/// with no terminal assertion. The slicer never throws.
public struct SlicedTestBody {

    /// Statements that don't contribute to the assertion's argument
    /// values: encoder configuration, mock instantiation, fixture
    /// loading, side-effecting mutations on objects whose bindings
    /// aren't transitively in the slice, etc.
    public let setup: [CodeBlockItemSyntax]

    /// Statements that the assertion transitively depends on, plus the
    /// assertion itself (when one was found). Computed by an SSA-like
    /// backward walk from the assertion's argument names through any
    /// `let`/`var` binding whose pattern names are in the live set.
    /// Mutating assignments and bindings whose names are never touched
    /// by the assertion fall through to `setup`.
    public let propertyRegion: [CodeBlockItemSyntax]

    /// Literals and `let x = <literal>` bindings inside the property
    /// region — the candidate inputs the lifted property generalizes
    /// over (PRD §7.2 rule 4). M1's round-trip detector consumes
    /// `bindingName` for the input-binding candidate; M2+ patterns
    /// consume the `kind` for generator-shape inference.
    public let parameterizedValues: [ParameterizedValue]

    /// The terminal assertion the slicer anchored on. `nil` when the
    /// body had no recognized assertion call — `propertyRegion` is
    /// empty and the entire body falls through to `setup` in that
    /// case.
    public let assertion: AssertionInvocation?

    public init(
        setup: [CodeBlockItemSyntax],
        propertyRegion: [CodeBlockItemSyntax],
        parameterizedValues: [ParameterizedValue],
        assertion: AssertionInvocation?
    ) {
        self.setup = setup
        self.propertyRegion = propertyRegion
        self.parameterizedValues = parameterizedValues
        self.assertion = assertion
    }

    /// Empty slice — for bodies with no terminal assertion. Setup
    /// holds the original body items in source order; property region
    /// is empty.
    public static func emptySlice(setup: [CodeBlockItemSyntax]) -> SlicedTestBody {
        SlicedTestBody(
            setup: setup,
            propertyRegion: [],
            parameterizedValues: [],
            assertion: nil
        )
    }
}

/// One literal-or-binding-of-literal value found in the property
/// region. The lifted property would generalize over these — the
/// `kind` informs which generator shape to suggest in M3+.
public struct ParameterizedValue {

    public enum Kind: Equatable, Sendable {
        case integer
        case string
        case boolean
        case float
    }

    /// `nil` for inline literal expressions used directly as
    /// assertion / call arguments. Set when the literal appears as a
    /// `let x = 42`-shaped binding the property region uses.
    public let bindingName: String?

    /// The literal's surface text (e.g. `"42"`, `"\"hello\""`).
    public let literalText: String

    public let kind: Kind

    public init(bindingName: String?, literalText: String, kind: Kind) {
        self.bindingName = bindingName
        self.literalText = literalText
        self.kind = kind
    }
}

/// A recognized assertion call — what the slicer anchored on.
/// `kind` discriminates between XCTest's `XCTAssert*` family and
/// Swift Testing's `#expect` / `#require` macros so M1.3's round-trip
/// detector can choose the right argument-shape walk per assertion
/// kind.
public struct AssertionInvocation {

    public enum Kind: Equatable, Sendable {
        case xctAssertEqual
        case xctAssertTrue
        case xctAssert
        case xctAssertNotNil
        case xctAssertLessThan
        case xctAssertLessThanOrEqual
        // M7.0 — negative-form assertion kinds for the
        // `AsymmetricAssertionDetector` counter-signal pass.
        case xctAssertNotEqual
        case xctAssertGreaterThan
        case xctAssertGreaterThanOrEqual
        case expectMacro
        case requireMacro
    }

    public let kind: Kind

    /// The argument expressions passed to the assertion. M1.3 reads
    /// these to detect the round-trip shape — one argument per side
    /// for `XCTAssertEqual(x, y)`, one boolean expression for
    /// `XCTAssertTrue(...)` / `#expect(...)`.
    public let arguments: [ExprSyntax]

    public let location: SwiftInferCore.SourceLocation

    public init(
        kind: Kind,
        arguments: [ExprSyntax],
        location: SwiftInferCore.SourceLocation
    ) {
        self.kind = kind
        self.arguments = arguments
        self.location = location
    }
}
