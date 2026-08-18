import Foundation
import Testing

@testable import SwiftInferCore

/// **Which computed properties are admitted as read-only `self -> T` maps.**
///
/// `makeSummary(fromComputedProperty:)` models a read-only computed property as a nullary
/// method, which is what lets `involution`, `round-trip` and friends fire on `var
/// conjugate: Self`. The modelling is only sound while the property really is read-only.
///
/// Open item 50: the gate was `contains("get") && !contains("set")`, and Swift has more
/// mutating accessors than `set`. `_modify` is a coroutine yielding an inout projection —
/// `set.unordered.insert(x)` writes through it — so six OrderedCollections properties were
/// admitted and carried eight laws that assume a value cannot change under them.
///
/// **The rule is an allowlist**, so an accessor kind it does not know about makes the
/// property writable rather than read-only. Naming the mutating ones would admit each new
/// kind by default, which is the wrong direction for a tool whose posture is *when in
/// doubt, fewer suggestions*.
@Suite("Scanner — only genuinely read-only computed properties are summarised")
struct ReadOnlyAccessorTests {

    static func summarised(_ accessors: String) -> Bool {
        let source = """
        struct Carrier {
            var projection: Carrier {
        \(accessors)
            }
        }
        """
        return FunctionScanner.scan(source: source, file: "F.swift")
            .contains { $0.name == "projection" && $0.isComputedProperty }
    }

    // MARK: - Admitted

    @Test("an implicit getter is read-only")
    func implicitGetterIsAdmitted() {
        #expect(Self.summarised("        Carrier()"))
    }

    @Test("an explicit get-only block is read-only")
    func explicitGetIsAdmitted() {
        #expect(Self.summarised("        get { Carrier() }"))
    }

    /// `_read` yields a borrowed value and `unsafeAddress` hands back an immutable
    /// pointer. Neither can write, so neither makes the property mutable.
    @Test("a borrowing coroutine beside a getter stays read-only")
    func borrowingAccessorsAreAdmitted() {
        #expect(Self.summarised("        get { Carrier() }\n        _read { yield self }"))
    }

    // MARK: - Rejected

    @Test("a setter is not read-only")
    func setterIsRejected() {
        #expect(!Self.summarised("        get { Carrier() }\n        set { }"))
    }

    /// **The open item 50 case.** A `_modify` coroutine is a mutating accessor, and the
    /// previous `!contains(\"set\")` gate did not know the word.
    @Test("a `_modify` coroutine is not read-only")
    func modifyCoroutineIsRejected() {
        #expect(!Self.summarised("        get { Carrier() }\n        _modify { yield &self }"), """
        A property with a `_modify` accessor was admitted as a read-only computed property. \
        It is writable through that accessor, so every law modelling it as a pure `self -> T` \
        map is unsound — six such properties in OrderedCollections carried eight laws.
        """)
    }

    @Test("a mutable addressor is not read-only")
    func mutableAddressorIsRejected() {
        #expect(!Self.summarised(
            "        get { Carrier() }\n        unsafeMutableAddress { fatalError() }"
        ))
    }

    /// **The allowlist's whole point**: an accessor kind Swift has that the rule does not
    /// name makes the property writable rather than silently read-only. `didSet` stands in
    /// for "the next accessor keyword" — it is a real specifier `SwiftSyntax` parses, and
    /// it is not in the allowlist.
    ///
    /// **The rule's reach stops at what the parser recognises, and that is worth stating.**
    /// An *invented* token — `_futureAccessor { }` — is not parsed as an accessor at all;
    /// the block collapses to the implicit-getter form and the property is admitted. So the
    /// fail-closed property holds for accessor kinds `SwiftSyntax` knows, which is every
    /// one Swift ships, and not for syntax it cannot parse. The first version of this test
    /// asserted the stronger claim and failed — the premise was wrong, not the rule.
    @Test("an accessor keyword outside the allowlist is not read-only")
    func unlistedAccessorIsRejected() {
        #expect(!Self.summarised("        get { Carrier() }\n        didSet { }"), """
        An accessor keyword the allowlist does not name was treated as read-only. The rule \
        must fail closed: a denylist admits every accessor Swift adds after it was written.
        """)
    }

    // MARK: - Unchanged behaviour

    @Test("a throwing getter is still not admitted")
    func throwingGetterIsRejected() {
        #expect(!Self.summarised("        get throws { Carrier() }"))
    }
}
