import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Self-dogfood road test (`docs/measurements/roadtest-self-dogfood.md` §12) — the fix for
/// the **confident green**, which was the finding this whole road test was built
/// around and the last one still open.
///
/// `Decisions.merge` commutativity is false: on a timestamp tie the fold keeps
/// the receiver's record. `verify` reported `measured-bothPass` at 100 trials
/// anyway, because the strategist draws `identityHash` from an eight-character
/// alphanumeric space and `capturedAt` from `Gen<Date>.date` — two records
/// essentially never share both, so the branch that carries the failure was
/// unreachable. A derived generator is tuned for coverage of the *type* and is
/// silently mistuned for coverage of the *law*.
///
/// The collision sweep runs the same oracle a second time with the RNG's entropy
/// narrowed, so independently-drawn operands share fields. After it,
/// commutativity on all four persistence logs reports `measured-defaultFails`.
///
/// **These tests exist because the mechanism was wrong twice before it was
/// right**, and both wrong versions produced a clean green:
///
///   1. The first narrowed by masking (`next() & 0x3`). That collapses every
///      derived value toward zero, so `.array(of: 0...8)` yielded a count of 0
///      on every draw and both operands came out *empty*. Commutativity on two
///      empty logs is trivially true. Found by probing the generated stub, not
///      by reading it.
///   2. A stale release binary then made the redesign look like it had also
///      failed — the survey was running yesterday's emitter.
///
/// So the assertions below pin the *properties of the emitted sweep* that make
/// it non-degenerate, not merely that a sweep is present.
@Suite("Road test — the collision sweep, and why it is not degenerate")
struct CollisionPassTests {

    private static func emit(template: String, carrier: String = "Decisions") throws -> String {
        try StrategistDispatchEmitter.emit(
            StrategistDispatchEmitter.Inputs(
                carrier: carrier,
                typeShape: IndexedTypeShape(
                    name: carrier,
                    kind: .struct,
                    inheritedTypes: ["Equatable"],
                    hasUserGen: false,
                    storedMembers: [IndexedTypeShape.StoredMember(name: "value", typeName: "Int")]
                ),
                template: template,
                functionCalls: ["merge"],
                seedHex: .init(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
                trialBudget: .small
            )
        )
    }

    // MARK: - The sweep is emitted for both binary laws

    @Test("commutativity emits a collision sweep before it declares PASS")
    func commutativityEmitsTheSweep() throws {
        let stub = try Self.emit(template: "commutativity")
        #expect(stub.contains("Pass 1b: collision sweep"))
        #expect(stub.contains("NarrowedRNG"))
        // Ordering is load-bearing: a sweep that ran *after* the PASS print
        // would never be reached on a passing default pass.
        let sweepAt = try #require(stub.range(of: "collisionPoolSizes"))
        let passAt = try #require(stub.range(of: "VERIFY_DEFAULT_RESULT: PASS"))
        #expect(sweepAt.lowerBound < passAt.lowerBound, "the sweep must precede the PASS print")
    }

    @Test("associativity emits the ternary collision sweep")
    func associativityEmitsTheSweep() throws {
        let stub = try Self.emit(template: "associativity")
        #expect(stub.contains("Pass 1b: collision sweep"))
        #expect(stub.contains("let cValue = defaultGenerator.run(using: &narrowed)"))
    }

    // MARK: - Why it is not degenerate

    /// **The regression guard for the masking bug.**
    ///
    /// The emitted RNG must draw from a pool of well-spread constants, not mask
    /// the low bits. Masking makes every length, count and index collapse to
    /// zero, which produced empty operands and a vacuous pass. A future
    /// "simplification" back to `& mask` fails here.
    @Test("the narrowed RNG draws from a spread pool, never a low-bit mask")
    func narrowedRNGIsNotABitMask() throws {
        let stub = try Self.emit(template: "commutativity")
        // Positive: `next()` must index the pool. Negative: it must not mask.
        // The first version of this test only forbade the literal `& mask`, and a
        // mutant that masked by a different variable name survived it — the
        // assertion has to be about the *operation*, not the spelling.
        #expect(
            stub.contains("Self.entropyPool[Int(inner.next()"),
            "the narrowed RNG must draw from the spread pool"
        )
        #expect(
            !stub.contains("inner.next() &"),
            """
            Masking the RNG's output collapses every derived value toward zero \
            — array counts become 0 and both operands come out empty, so the law \
            passes vacuously. Draw from a pool of spread constants instead.
            """
        )
        // The pool's constants must be large and spread, or reducing them into a
        // range clusters them again.
        #expect(stub.contains("0x9E37_79B9_7F4A_7C15"))
    }

    /// The pool size is rotated across trials. A single size is either so small
    /// that both operands are identical — commutativity then holds trivially —
    /// or so large that collisions vanish. The sweep needs both ends.
    @Test("the pool size is rotated across trials")
    func poolSizeRotates() throws {
        let stub = try Self.emit(template: "commutativity")
        #expect(stub.contains("collisionPoolSizes"))
        #expect(stub.contains("[2, 3, 4, 6, 8]"))
        #expect(stub.contains("collisionPoolSizes[trial % collisionPoolSizes.count]"))
    }

    /// The sweep threads the RNG state forward (`collisionBase = narrowed.inner`)
    /// rather than restarting from the seed each trial. Without it every trial
    /// draws the same values and the sweep is 100 copies of one test.
    @Test("the sweep advances the RNG state between trials")
    func sweepAdvancesTheRNGState() throws {
        let stub = try Self.emit(template: "commutativity")
        #expect(stub.contains("collisionBase = narrowed.inner"))
    }

    /// A failure found in the sweep reports through the ordinary
    /// `VERIFY_DEFAULT_*` markers, because it *is* the ordinary verdict — the
    /// narrowed values are legitimate values of the carrier, so the law is
    /// simply false. Nothing in the parser or the promotion path needs to know
    /// which sweep found it; `PASS_KIND` rides along only for the detail.
    @Test("a collision failure reports as an ordinary default failure")
    func collisionFailureUsesTheDefaultMarkers() throws {
        let stub = try Self.emit(template: "commutativity")
        #expect(stub.contains("VERIFY_DEFAULT_PASS_KIND: collision"))
        // Same marker vocabulary as the default pass — not a new outcome class.
        let sweep = try #require(stub.range(of: "Pass 1b"))
        let tail = String(stub[sweep.lowerBound...])
        #expect(tail.contains("VERIFY_DEFAULT_RESULT: FAIL"))
        #expect(tail.contains("VERIFY_DEFAULT_INPUT:"))
    }

    // MARK: - The unary sweep
    //
    // The binary sweep makes two *operands* collide. It says nothing about
    // elements colliding *inside a single generated value* — two records in one
    // log sharing an identity, two entries sharing a key. That is the same class
    // one level down, and it is where the original finding actually lived:
    // `merge`'s tie is reachable because a *log* can hold colliding records, not
    // merely because two logs can.

    @Test("unary laws also get a collision sweep")
    func unaryLawsGetTheSweep() throws {
        for template in ["idempotence", "codable-round-trip"] {
            let stub = try Self.emit(template: template)
            #expect(stub.contains("Pass 1b: collision sweep"), "\(template) has no sweep")
            #expect(stub.contains("let collisionValue = defaultGenerator.run(using: &narrowed)"))
            #expect(stub.contains("VERIFY_DEFAULT_PASS_KIND: collision"))
        }
    }

    /// The unary sweep draws **one** value per trial, not two. Drawing a pair
    /// here would silently turn an idempotence check into something else.
    ///
    /// Scoped to Pass 1. `Decisions` is a composed carrier, so it now also gets
    /// an advisory boundary pass, which is the *same composed body* over a
    /// boundary generator — sweep included. Counting to the end of the stub
    /// therefore counts both passes and reads as "the sweep draws two values",
    /// which is a claim about the pass count, not about the sweep.
    @Test("the unary sweep draws exactly one value per trial")
    func unarySweepDrawsOneValue() throws {
        let stub = try Self.emit(template: "codable-round-trip")
        let sweep = try #require(stub.range(of: "Pass 1b"))
        let pass1 = String(stub[sweep.lowerBound...])
            .components(separatedBy: "// --- Pass 2:")[0]
        #expect(pass1.components(separatedBy: "defaultGenerator.run(using: &narrowed)").count - 1 == 1)
    }

    /// And the boundary pass carries its own copy — one sweep per pass, so a
    /// collision-dependent law is swept over the boundary domain too. Pinned
    /// because the scoping above would otherwise hide a Pass 2 that lost it.
    @Test("the boundary pass carries its own collision sweep")
    func boundaryPassKeepsTheSweep() throws {
        let stub = try Self.emit(template: "codable-round-trip")
        let pass2 = try #require(stub.range(of: "// --- Pass 2:"))
        let tail = String(stub[pass2.lowerBound...])
        #expect(tail.contains("Pass 1b: collision sweep"))
        #expect(tail.components(separatedBy: "defaultGenerator.run(using: &narrowed)").count - 1 == 1)
        #expect(tail.contains("VERIFY_EDGE_PASS_KIND: collision"))
    }

    /// It shares the binary sweep's machinery rather than reimplementing it —
    /// same pool, same rotation, same state threading. A divergent copy would
    /// be the place a future degeneracy hides.
    @Test("the unary sweep reuses the binary sweep's narrowing")
    func unarySweepSharesTheMachinery() throws {
        let stub = try Self.emit(template: "idempotence")
        #expect(stub.contains("collisionPoolSizes[trial % collisionPoolSizes.count]"))
        #expect(stub.contains("collisionBase = narrowed.inner"))
        #expect(!stub.contains("inner.next() &"))
    }
}
