@testable import SwiftInferCore
import Testing

/// Rewriting a `guard-domain` condition so a test can evaluate it (#468).
///
/// **Every case here is a way a naive `replacingOccurrences` corrupts real text**, and all three
/// mechanisms occur in the 156 measured sites. The rule the type enforces is *rebind or decline* —
/// a partial rewrite is a stub that does not compile, and this project has measured what that
/// costs at 145 of 163.
@Suite("Guard-domain rebinding — a condition evaluated from outside its declaration")
struct GuardDomainRebindingTests {

    // MARK: - The three corruptions a naive replace causes

    /// `s` is a parameter and `source`/`hasPrefix` merely contain its letters. A substring replace
    /// produces `<v>ource.ha<v>Prefix`, which is not Swift.
    @Test("an identifier is matched whole, never as a substring")
    func wholeIdentifiersOnly() {
        let rebound = GuardDomainRebinding.rebind(
            "source.hasPrefix(s)", bindings: ["s": "value", "source": "value"]
        )
        #expect(rebound == "value.hasPrefix(value)")
    }

    /// In `other.count`, `other` is the parameter and `count` is its member. Rebinding `count`
    /// would be meaningless, and demanding a binding for it would decline a site that is fine.
    @Test("a name after a dot is a member and is left alone")
    func membersAreLeftAlone() {
        let bindings = ["other": "args.1", "self": "args.0"]
        #expect(
            GuardDomainRebinding.rebind("self.count == other.underestimatedCount", bindings: bindings)
                == "args.0.count == args.1.underestimatedCount"
        )
        #expect(GuardDomainRebinding.unboundNames(in: "self.count", bindings: bindings).isEmpty)
    }

    /// The letters of a parameter name inside a literal are **what the code tests for**. Rewriting
    /// there changes the meaning rather than the scope.
    @Test("a string literal is skipped whole, escapes included")
    func stringLiteralsAreSkipped() {
        #expect(
            GuardDomainRebinding.rebind("key.hasPrefix(\"key\")", bindings: ["key": "value"])
                == "value.hasPrefix(\"key\")"
        )
        #expect(
            GuardDomainRebinding.rebind("s == \"a\\\"s\\\"b\"", bindings: ["s": "value"])
                == "value == \"a\\\"s\\\"b\""
        )
    }

    // MARK: - The three substitutions the measurement found

    /// 147 of 156 sites need this one.
    @Test("a parameter rebinds to its drawn value")
    func parameterRebinds() {
        #expect(GuardDomainRebinding.rebind("scale > 0", bindings: ["scale": "value"]) == "value > 0")
    }

    /// 57 sites mention `self`; it is the drawn receiver, which for an instance method is the
    /// first argument the stub supplies.
    @Test("`self` rebinds to the drawn receiver")
    func selfRebinds() {
        #expect(
            GuardDomainRebinding.rebind("self === other", bindings: ["self": "args.0", "other": "args.1"])
                == "args.0 === args.1"
        )
    }

    /// 8 sites mention `Self`, almost always as a constructor. It is the declaring type, which the
    /// test can spell.
    @Test("`Self` rebinds to the declaring type")
    func selfTypeRebinds() {
        #expect(
            GuardDomainRebinding.rebind("(Self(), source)", bindings: ["Self": "FrontMatter", "source": "value"])
                == "(FrontMatter(), value)"
        )
    }

    /// `self` and `Self` are different names and binding one must not bind the other — Swift's
    /// case sensitivity is load-bearing here, and a case-insensitive match would produce
    /// `FrontMatter === other` for `self === other`.
    @Test("`self` and `Self` are distinct bindings")
    func selfAndSelfTypeAreDistinct() {
        #expect(
            GuardDomainRebinding.rebind("self.x == Self.y", bindings: ["self": "receiver", "Self": "Owner"])
                == "receiver.x == Owner.y"
        )
    }

    // MARK: - Decline

    /// **The 27 of 156 the feasibility measurement could not bind** are underscored internals and
    /// type references. A partial rewrite would emit a file that does not compile for a reason the
    /// reader would have to work out.
    @Test("an unbindable free name declines, and is named")
    func unbindableNameDeclines() {
        #expect(GuardDomainRebinding.rebind("_fastPath(scale > 0)", bindings: ["scale": "value"]) == nil)
        #expect(
            GuardDomainRebinding.unboundNames(in: "_fastPath(_root > 0)", bindings: [:])
                == ["_fastPath", "_root"]
        )
    }

    /// Reported once each, in first-seen order, so a decline sentence reads as a list rather than
    /// repeating one name per occurrence.
    @Test("a repeated unbound name is reported once")
    func repeatedUnboundNameReportedOnce() {
        #expect(GuardDomainRebinding.unboundNames(in: "_x && _x && _y", bindings: [:]) == ["_x", "_y"])
    }

    /// `true` / `false` / `nil` mean the same thing in every scope, so they need no binding and
    /// must not trigger a decline.
    @Test("the self-evident literals need no binding")
    func literalsNeedNoBinding() {
        #expect(GuardDomainRebinding.rebind("flag == true", bindings: ["flag": "value"]) == "value == true")
        #expect(GuardDomainRebinding.rebind("nil", bindings: [:]) == "nil")
        #expect(GuardDomainRebinding.unboundNames(in: "true || false", bindings: [:]).isEmpty)
    }

    /// An argument label is not a value. Treating it as one would demand a binding that cannot
    /// exist and decline a site that is fine.
    @Test("an argument label is neither rebound nor counted unbound")
    func argumentLabelsPassThrough() {
        #expect(
            GuardDomainRebinding.rebind("f(from: s)", bindings: ["f": "g", "s": "value"])
                == "g(from: value)"
        )
        #expect(GuardDomainRebinding.unboundNames(in: "f(from: s)", bindings: ["f": "g", "s": "v"]).isEmpty)
    }

    /// Numbers are not identifiers, and a name may contain digits after its first character.
    @Test("digits inside and after a name are handled")
    func digitsInNames() {
        #expect(
            GuardDomainRebinding.rebind("value1 > 0x2F", bindings: ["value1": "drawn"])
                == "drawn > 0x2F"
        )
    }

    /// **An interpolation is code.** Measured on pbt-book's `formatDropping(_:)`, whose guard
    /// returns `"\(order.id)"`: the condition was rebound to `arg0` and the interpolation was not,
    /// so the stub failed with `cannot find 'order' in scope`.
    @Test("a name inside an interpolation is rebound")
    func interpolationIsRebound() {
        #expect(
            GuardDomainRebinding.rebind("\"\\(order.id)\"", bindings: ["order": "arg0"])
                == "\"\\(arg0.id)\""
        )
        #expect(
            GuardDomainRebinding.rebind("\"id: \\(f(order, (1)))!\"", bindings: ["order": "arg0", "f": "f"])
                == "\"id: \\(f(arg0, (1)))!\""
        )
    }

    /// And the other half of the same defect: a name there that cannot be bound must decline the
    /// site, not slip past `unboundNames` into a stub that does not compile.
    @Test("an unbound name inside an interpolation is reported")
    func interpolationUnboundIsReported() {
        #expect(GuardDomainRebinding.unboundNames(in: "\"\\(cache.key)\"", bindings: [:]) == ["cache"])
        #expect(GuardDomainRebinding.rebind("\"\\(cache.key)\"", bindings: [:]) == nil)
    }

    /// The template's own documented example, end to end.
    @Test("the template's documented example rebinds whole")
    func documentedExample() {
        let bindings = ["source": "value", "Self": "FrontMatter"]
        #expect(
            GuardDomainRebinding.rebind("source.hasPrefix(\"---\")", bindings: bindings)
                == "value.hasPrefix(\"---\")"
        )
        #expect(
            GuardDomainRebinding.rebind("(Self(), source)", bindings: bindings)
                == "(FrontMatter(), value)"
        )
    }
}
