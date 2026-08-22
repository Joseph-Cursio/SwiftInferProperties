import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// **A law on a declaration that cannot be called is not a conservative suggestion — it is a
/// wrong one.**
///
/// Discovery read visibility and never availability. The witness was swift-system's
/// `public var dirname`, which is `@available(*, unavailable, renamed: "removingLastComponent()")`
/// and produced a suggestion, a score, and a `build-failed` verdict reading
/// `'dirname' has been renamed to 'removingLastComponent()'`.
///
/// **Most of these arms are the NEGATIVE cases, and deliberately.** The rule is two keywords and
/// the risk is not that it fails to fire — it is that it fires on `@available` generally, which
/// was measured across the corpora at **1,163 `deprecated`** public declarations, 28 `noasync`,
/// and several hundred version floors. All of those are perfectly good law subjects, and a gate
/// that swept them would throw away an order of magnitude more than it saved.
@Suite("Availability — a withdrawn declaration owes no law")
struct UncallableDeclarationTests {

    private func decl(_ source: String) -> DeclSyntax {
        Parser.parse(source: source).statements.first!.item.as(DeclSyntax.self)!
    }

    private func isWithdrawn(_ source: String) -> Bool {
        UncallableDeclaration.isWithdrawn(decl(source))
    }

    // MARK: - Blocks

    @Test("an unavailable function is withdrawn")
    func unavailableFunctionIsWithdrawn() {
        #expect(isWithdrawn("""
        @available(*, unavailable, renamed: "removingLastComponent()")
        public func dirname() -> Path { fatalError() }
        """))
    }

    @Test("an unavailable computed property is withdrawn — the actual witness")
    func unavailablePropertyIsWithdrawn() {
        #expect(isWithdrawn("""
        @available(*, unavailable, renamed: "removingLastComponent()")
        public var dirname: FilePath { removingLastComponent() }
        """))
    }

    @Test("a bare unavailable with no payload is withdrawn")
    func bareUnavailableIsWithdrawn() {
        #expect(isWithdrawn("@available(*, unavailable)\npublic func gone() {}"))
    }

    /// `@available(swift, deprecated: 3.0, obsoleted: 5.0, renamed: …)` — 49+ sites across the
    /// corpora, and note it says BOTH `deprecated` and `obsoleted`. A rule keyed on `deprecated`
    /// would read this as callable; it was removed in Swift 5.0.
    @Test("an obsoleted declaration is withdrawn even though it also says deprecated")
    func obsoletedIsWithdrawn() {
        #expect(isWithdrawn("""
        @available(swift, deprecated: 3.0, obsoleted: 5.0, renamed: "newName")
        public func oldName() {}
        """))
    }

    @Test("a member of an unavailable extension is withdrawn")
    func memberOfUnavailableExtensionIsWithdrawn() {
        let source = """
        @available(*, unavailable)
        extension Thing {
            public func stillHere() -> Int { 0 }
        }
        """
        let tree = Parser.parse(source: source)
        let function = tree.statements.first!.item.as(ExtensionDeclSyntax.self)!
            .memberBlock.members.first!.decl.as(FunctionDeclSyntax.self)!
        #expect(UncallableDeclaration.isWithdrawn(function))
    }

    // MARK: - Does NOT block — the arms that matter most

    /// **1,163 public declarations across the corpora.** A deprecated API still compiles, still
    /// runs, and is still a law subject. This is the single arm that would matter if the rule
    /// were ever loosened to "carries `@available`".
    @Test("a deprecated declaration is NOT withdrawn")
    func deprecatedIsNotWithdrawn() {
        #expect(!isWithdrawn("""
        @available(*, deprecated, renamed: "newName")
        public func oldName() {}
        """))
        #expect(!isWithdrawn("""
        @available(*, deprecated, message: "Use the other one")
        public func oldName() {}
        """))
    }

    /// Version floors — hundreds of sites. `@available(macOS 13, iOS 16, *)` says *this exists
    /// from here on*, which is the opposite of withdrawal.
    @Test("a version floor is NOT withdrawn")
    func versionFloorIsNotWithdrawn() {
        for attribute in [
            "@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)",
            "@available(SwiftStdlib 6.0, *)",
            "@available(macOS, introduced: 10.10)"
        ] {
            #expect(!isWithdrawn("\(attribute)\npublic func present() {}"), "\(attribute) blocked")
        }
    }

    /// 28 sites. `noasync` bars a call from an async context; the emitted stub is synchronous,
    /// so it is callable exactly where the tool calls it.
    @Test("noasync is NOT withdrawn — the emitted stub is synchronous")
    func noasyncIsNotWithdrawn() {
        #expect(!isWithdrawn("@available(*, noasync)\npublic func syncOnly() {}"))
    }

    @Test("an unannotated declaration is NOT withdrawn")
    func plainDeclarationIsNotWithdrawn() {
        #expect(!isWithdrawn("public func ordinary() -> Int { 0 }"))
    }

    /// A member of a merely-deprecated extension must survive: the ancestor walk has to carry
    /// the same two-keyword rule upward, not a looser one.
    @Test("a member of a DEPRECATED extension is NOT withdrawn")
    func memberOfDeprecatedExtensionIsNotWithdrawn() {
        let source = """
        @available(*, deprecated, message: "prefer Other")
        extension Thing {
            public func stillCallable() -> Int { 0 }
        }
        """
        let tree = Parser.parse(source: source)
        let function = tree.statements.first!.item.as(ExtensionDeclSyntax.self)!
            .memberBlock.members.first!.decl.as(FunctionDeclSyntax.self)!
        #expect(!UncallableDeclaration.isWithdrawn(function))
    }

    /// A non-`available` attribute must not be read for these keywords at all.
    @Test("another attribute mentioning the word is NOT withdrawn")
    func anotherAttributeIsNotWithdrawn() {
        #expect(!isWithdrawn("@objc(unavailable)\npublic func named() {}"))
    }
}
