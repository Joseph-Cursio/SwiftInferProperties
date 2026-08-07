import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// **An immediately-applied closure literal has no type context, and Swift
/// gives up on it.**
///
/// `functionCalls` is sometimes a bare reference (`SeedFocus.functionBaseName`)
/// and sometimes a closure literal (`{ SeedFocus.seedIndependent(in: $0) }`,
/// which is how a labelled or non-static call is expressed). Applying the
/// second form inline — `{ … }(value)` — asks the compiler to infer `$0` from
/// the argument, and on a large derived generator it reports
/// *"cannot infer type of closure parameter '$0' without a type annotation"*
/// and the whole verify run comes back `measured-error: build-failed`.
///
/// This is the third distinct failure the same `SeedFocus` idempotence entry
/// has produced (`docs/measurements/roadtest-self-dogfood.md` §13.4): first a SIGTRAP, then
/// a masked build failure, now this. Each one read as a different kind of
/// problem, and only the last is the emitter's own.
///
/// The fix binds the function once, with an explicit type, and calls the bound
/// name everywhere. The binding is what supplies the context the literal lacks.
///
/// These assertions are about the *shape* of the emitted stub rather than any
/// single spelling, because the defect class is "a closure literal is applied
/// where nothing tells it what it takes" — a mutant that changed the closure's
/// body while keeping the inline application would still be broken.
@Suite("Emitted stubs never apply a closure literal inline")
struct AppliedClosureLiteralTests {

    /// The real shape from the road test: a labelled static call, which the
    /// emitter must wrap in a closure, over an array carrier whose derived
    /// generator is large enough that inference genuinely fails.
    private static func emit(
        template: String,
        carrier: String = "[Suggestion]",
        call: String = "{ SeedFocus.seedIndependent(in: $0) }"
    ) throws -> String {
        try StrategistDispatchEmitter.emit(
            StrategistDispatchEmitter.Inputs(
                carrier: carrier,
                typeShape: IndexedTypeShape(
                    name: "SeedFocus",
                    kind: .struct,
                    inheritedTypes: ["Equatable"],
                    hasUserGen: false,
                    storedMembers: [IndexedTypeShape.StoredMember(name: "value", typeName: "Int")]
                ),
                template: template,
                functionCalls: [call],
                seedHex: .init(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
                trialBudget: .small
            )
        )
    }

    /// A closing brace immediately followed by `(` is the defect, wherever it
    /// appears — default pass, collision sweep, or shrink oracle.
    ///
    /// Comment lines are excluded, and that exclusion was earned: the first
    /// version flagged the emitter's own explanatory comment, which names the
    /// broken form `{ … }(value)` in order to warn about it. A detector that
    /// cannot tell code from prose reports the documentation as the bug.
    private static func inlineApplications(in stub: String) -> [String] {
        stub.split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .filter { $0.contains("}(") }
            .map(String.init)
    }

    @Test("idempotence never applies the closure literal inline")
    func idempotenceBindsTheFunction() throws {
        let stub = try Self.emit(template: "idempotence")
        let offenders = Self.inlineApplications(in: stub)
        #expect(
            offenders.isEmpty,
            """
            Applied a closure literal inline, which cannot infer its parameter:
            \(offenders.joined(separator: "\n"))
            """
        )
    }

    /// The collision sweep is where it actually surfaced, so it gets its own
    /// assertion rather than relying on the whole-stub scan above.
    /// **The raw `contains` this used to do was the same bug the helper above
    /// was written to fix.** It relied on the emitter's `{ … }(value)` comment
    /// sitting *before* `Pass 1b` in the stub. When the advisory edge pass
    /// learned to reach composed carriers it re-emitted the whole body — comment
    /// included — after that point, and the test reported the documentation as
    /// the bug, exactly as `inlineApplications`' docstring warns. Scan through
    /// the helper so prose can never be mistaken for code again.
    @Test("the collision sweep calls the bound function, not the literal")
    func collisionSweepUsesTheBinding() throws {
        let stub = try Self.emit(template: "idempotence")
        let sweep = try #require(stub.range(of: "Pass 1b"))
        let tail = String(stub[sweep.lowerBound...])
        let offenders = Self.inlineApplications(in: tail)
        #expect(offenders.isEmpty, "the sweep still applies the literal inline: \(offenders)")
        #expect(tail.contains("collisionOnce = "))
    }

    /// The binding must carry an explicit type — an unannotated
    /// `let applyOnce = { … }` moves the same inference failure one line up
    /// rather than fixing it.
    @Test("the binding is explicitly typed with the carrier")
    func bindingIsExplicitlyTyped() throws {
        let stub = try Self.emit(template: "idempotence")
        #expect(
            stub.contains("([Suggestion]) -> [Suggestion]"),
            "the bound function must state its type; inference is the bug"
        )
    }

    /// **The control.** A bare function reference needs no wrapping, and the
    /// fix must not break it — if this ever failed, the binding would have
    /// started mangling the common case to fix the rare one.
    @Test("a bare function reference still emits and still binds cleanly")
    func bareReferenceStillWorks() throws {
        let stub = try Self.emit(
            template: "idempotence",
            carrier: "String",
            call: "SeedFocus.functionBaseName"
        )
        #expect(Self.inlineApplications(in: stub).isEmpty)
        #expect(stub.contains("(String) -> String"))
    }
}
