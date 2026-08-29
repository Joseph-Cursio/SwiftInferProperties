import Foundation
import PropertyLawCore
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// **A precondition one hop away is still a precondition — and this side computed the
/// flag that says so nowhere.**
///
/// `InitializerPreconditionDetector` offers two questions, and the kit's strategist asks
/// them together: *does this initializer assert* and *does it delegate to a sibling that
/// does*. `MemberBlockInspector` here answered only the first, from the day the port was
/// written until 2026-08-28, so the second clause of
/// `InitializerBasedDerivation.isDeclined` could never fire on anything this repo
/// scanned.
///
/// **Measured on `Euclid.Plane` @ `0b00927`.** `Sources/Plane.swift:235` declares
///
/// ```swift
/// init(unchecked normal: Vector, pointOnPlane: Vector) {
///     self.init(unchecked: normal, w: normal.dot(pointOnPlane))
/// }
/// ```
///
/// and the initializer it forwards to, four lines above, opens with
/// `assert(normal.isNormalized)`. The strategist picked the delegating one, derived a
/// generator drawing four random doubles, and the first generated kit suite anyone has
/// compiled died on that assertion — signal 5, with every law after it unrun
/// (`docs/measurements/kit-scaffold-conversion.md` §3.2).
///
/// **A trap is worse than a refutation**, which is why this is a decline rather than a
/// retry: a refuted law reports a counterexample and the suite continues, while an
/// aborted process reports nothing about the laws it never reached.
///
/// The projection half of the same bug — both flags dropped between the shape and
/// `index.json` — is guarded by `IndexedTypeShapeParityPropertyTests`. This suite guards
/// the capture half: that the flags are computed from source at all.
@Suite("Initializer capture — a delegating initializer records that it delegates")
struct DelegatingInitializerCaptureTests {

    /// Reads the first `extension` body, not the first `struct` body — `Euclid` declares
    /// `Plane`'s initializers in an extension, and `FirstMemberBlockFinder` next door
    /// visits `StructDeclSyntax` only.
    static func initializers(in source: String) -> [InitializerSignature] {
        let tree = Parser.parse(source: source)
        let finder = ExtensionMemberBlockFinder(viewMode: .sourceAccurate)
        finder.walk(tree)
        guard let block = finder.found else { return [] }
        return MemberBlockInspector.initializers(in: block)
    }

    /// **The measured case, reduced from `Euclid/Sources/Plane.swift:228–238`.** Kept in
    /// an `extension`, which is where Euclid declares them — the merge in
    /// `TypeShapeBuilder` folds unconditional extension initializers into the primary
    /// shape, so the flags have to survive that map too.
    @Test("the Plane shape records both flags")
    func planeShapeRecordsBothFlags() throws {
        let captured = Self.initializers(in: """
        extension Plane {
            init(unchecked normal: Vector, w: Double) {
                assert(normal.isNormalized)
                self.normal = normal
                self.w = w
            }

            init(unchecked normal: Vector, pointOnPlane: Vector) {
                self.init(unchecked: normal, w: normal.dot(pointOnPlane))
            }
        }
        """)
        #expect(captured.count == 2)

        let asserting = try #require(captured.first { $0.parameters.map(\.label) == ["unchecked", "w"] })
        #expect(asserting.assertsPrecondition, "the `assert(normal.isNormalized)` was not seen")
        #expect(!asserting.delegatesToSelf)

        let delegating = try #require(
            captured.first { $0.parameters.map(\.label) == ["unchecked", "pointOnPlane"] }
        )
        #expect(
            delegating.delegatesToSelf,
            "the `self.init(…)` forward was not recorded — the kit's second decline clause cannot fire"
        )
        #expect(
            !delegating.assertsPrecondition,
            "this initializer asserts nothing itself, which is exactly why the pairing is needed"
        )
    }

    /// The negative control. An initializer that neither asserts nor forwards records
    /// `false` for both, so the assertions above cannot be passing because the detector
    /// answers `true` to everything.
    @Test("a plain initializer records neither flag")
    func plainInitializerRecordsNeitherFlag() throws {
        let captured = Self.initializers(in: """
        extension Point {
            init(x: Double, y: Double) { self.x = x; self.y = y }
        }
        """)
        let signature = try #require(captured.first)
        #expect(!signature.assertsPrecondition)
        #expect(!signature.delegatesToSelf)
    }

    /// **The consequence, end to end from source.** Capture → `TypeShapeBuilder` →
    /// `IndexedTypeShape` → `toKitShape()` → strategy. The `Plane` shape must reach the
    /// strategist declined; before the fix it arrived with both flags `false` and derived
    /// a live generator whose every draw was an unnormalized vector.
    @Test("the Plane shape is declined by the strategist through the whole projection")
    func planeShapeIsDeclinedThroughTheProjection() throws {
        let captured = Self.initializers(in: """
        extension Plane {
            init(unchecked normal: Vector, w: Double) {
                assert(normal.isNormalized)
                self.normal = normal
                self.w = w
            }

            init(unchecked normal: Vector, pointOnPlane: Vector) {
                self.init(unchecked: normal, w: normal.dot(pointOnPlane))
            }
        }
        """)

        let plane = TypeDecl(
            name: "Plane",
            kind: .struct,
            inheritedTypes: ["Hashable"],
            location: SourceLocation(file: "Plane.swift", line: 1, column: 1),
            hasUserGen: false,
            storedMembers: [
                StoredMember(name: "normal", typeName: "Vector"),
                StoredMember(name: "w", typeName: "Double")
            ],
            hasUserInit: true,
            initializers: captured
        )

        let shape = try #require(TypeShapeBuilder.shapes(from: [plane]).first)
        let anyDelegates = shape.initializers.contains(where: \.delegatesToSelf)
        let anyAsserts = shape.initializers.contains(where: \.assertsPrecondition)
        #expect(anyDelegates, "the merge into the primary shape dropped `delegatesToSelf`")
        #expect(anyAsserts, "the merge into the primary shape dropped `assertsPrecondition`")

        let viaIndex = IndexedTypeShape(from: shape).toKitShape()
        #expect(viaIndex.initializers == shape.initializers)

        if case .initializerBased(let arguments) = DerivationStrategist.strategy(for: viaIndex) {
            let message = "`Plane` derived \(arguments.count) arguments through the index —"
                + " this is the derivation that traps at `assert(normal.isNormalized)`"
            Issue.record(Comment(rawValue: message))
        }
    }
}

/// First `extension` member block in a parsed file.
final class ExtensionMemberBlockFinder: SyntaxVisitor {
    private(set) var found: MemberBlockSyntax?

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        if found == nil { found = node.memberBlock }
        return .skipChildren
    }
}
