import Foundation
import PropertyLawCore
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// **An initializer a test cannot call must never reach the strategist.**
///
/// Measured on `swift-http-types` @ `5b99e00` (`docs/measurements/criterion-a-unmet-subject.md`):
/// `HTTPField.Name` declares two `public init?`s and one
/// `private init(rawName:canonicalName:)` whose labels match its stored members exactly.
/// The strategist preferred the memberwise-shaped candidate — the private one — and the
/// emitted stub did not compile. **95 of 163 laws on that subject died this way**, and the
/// reported error was a cascade (`value of optional type 'HTTPField.Name?' must be
/// unwrapped`) rather than the real one (`extra argument 'canonicalName' in call`).
///
/// `InitializerSignature` carries no access level, so this has to be decided at capture.
@Suite("Initializer capture — inaccessible initializers are not candidates")
struct InaccessibleInitializerTests {

    static func initializers(in source: String) -> [InitializerSignature] {
        let tree = Parser.parse(source: source)
        let finder = FirstMemberBlockFinder(viewMode: .sourceAccurate)
        finder.walk(tree)
        guard let block = finder.found else { return [] }
        return MemberBlockInspector.initializers(in: block)
    }

    /// **The measured case, reduced.** Both `public init?`s survive; the private
    /// memberwise-shaped one does not.
    @Test("a private memberwise-shaped initializer is not captured")
    func privateInitializerIsDropped() {
        let captured = Self.initializers(in: """
        public struct Name {
            let rawName: String
            let canonicalName: String
            public init?(_ name: String) { self.rawName = name; self.canonicalName = name }
            public init?(parsed name: String) { self.rawName = name; self.canonicalName = name }
            private init(rawName: String, canonicalName: String) {
                self.rawName = rawName
                self.canonicalName = canonicalName
            }
        }
        """)
        #expect(captured.count == 2, "captured \(captured.count) — the private init leaked through")
        let allFailable = captured.allSatisfy(\.isFailable)
        #expect(allFailable, "the survivors must be the two `public init?`s")
        let memberwiseLeaked = captured.contains { $0.parameters.map(\.label) == ["rawName", "canonicalName"] }
        #expect(!memberwiseLeaked, "the private memberwise-shaped initializer leaked through")
    }

    /// `fileprivate` is file-scoped too, and a test lives in another file.
    @Test("a fileprivate initializer is not captured")
    func fileprivateInitializerIsDropped() {
        let captured = Self.initializers(in: """
        public struct S {
            let value: Int
            fileprivate init(value: Int) { self.value = value }
        }
        """)
        #expect(captured.isEmpty, "captured \(captured.count)")
    }

    /// **`internal` is KEPT, and that is deliberate.** `@testable import` reaches it —
    /// the same line `AccessRestriction.internalOrSPI` and `SpeculativeWidening` draw.
    /// Dropping it would silently narrow every derivation on every internal type.
    @Test("internal and public initializers are still captured")
    func reachableInitializersSurvive() {
        let captured = Self.initializers(in: """
        public struct S {
            let value: Int
            init(value: Int) { self.value = value }
            public init(other: Int) { self.value = other }
        }
        """)
        #expect(captured.count == 2, "captured \(captured.count) — a reachable initializer was dropped")
    }

    /// `private(set)` restricts the setter, not the initializer. Checked rather than
    /// assumed: reading a modifier by name alone is how `isReadOnlyGetter` came to admit
    /// `_modify` coroutines as read-only.
    @Test("a detail-bearing private modifier does not suppress the initializer")
    func privateSetDoesNotSuppress() {
        let source = """
        public struct S {
            public private(set) var value: Int
            public init(value: Int) { self.value = value }
        }
        """
        #expect(Self.initializers(in: source).count == 1)
    }
}

/// The first `MemberBlockSyntax` in a tree — enough for these single-type fixtures.
final class FirstMemberBlockFinder: SyntaxVisitor {
    private(set) var found: MemberBlockSyntax?

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if found == nil { found = node.memberBlock }
        return .skipChildren
    }
}
