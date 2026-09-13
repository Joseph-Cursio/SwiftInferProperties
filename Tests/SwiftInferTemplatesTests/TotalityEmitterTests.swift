import SwiftInferCore
import SwiftInferTemplates
import Testing

/// The emitter arm for the catalog's **role-entailed** laws.
///
/// ## Why this arm exists, measured
///
/// On SwiftMarkdownWiki, before it did: of 48 suggestions, the 23 carried by role-entailed
/// templates — laws a *correct* implementation cannot fail — produced **0** stub files, while 21
/// of 25 conjectural ones produced a file.
///
/// **The tool emitted the laws that can cry wolf and declined the ones that cannot.** That is the
/// exact inverse of `Refutability.isWorthSurfacingBelowCut`, which exists to privilege entailed
/// laws, and it had been true since the accept path was written.
///
/// `predicate` (15) and `input-totality` (4) are 19 of those 23, and both state the same law: the
/// subject returns or throws for every input its parameter type admits, and never traps.
@Suite("Totality — the emitted form of the one free law")
struct TotalityEmitterTests {

    private static let seed = SamplingSeed.Value(
        stateA: 0x1234_5678_9ABC_DEF0,
        stateB: 0x0FED_CBA9_8765_4321,
        stateC: 0xAAAA_BBBB_CCCC_DDDD,
        stateD: 0x1111_2222_3333_4444
    )

    private static func emit(
        _ callee: CalleeReference,
        isThrowing: Bool = false,
        isAsync: Bool = false
    ) -> String {
        LiftedTestEmitter.total(
            callee: callee,
            seed: seed,
            generator: "Gen<String>.always(\"x\")",
            isThrowing: isThrowing,
            isAsync: isAsync
        )
    }

    // MARK: - The law

    /// **The property returns `true` unconditionally, and that is the law rather than a stub.**
    /// A trap kills the process, so there is nothing to catch and nothing to compare — reaching
    /// the `return true` *is* the evidence.
    @Test func theCallIsMadeAndItsResultDiscarded() {
        let stub = Self.emit(CalleeReference(bareName: "parse", qualifier: "WikilinkParser"))
        #expect(stub.contains("_ = WikilinkParser.parse(value); return true"))
    }

    /// Totality compares nothing, so the return type needs no `Equatable` — the constraint that
    /// sends so many subjects to a `.todo`. Pinned as an absence because that reach is the
    /// reason this arm gets subjects the comparison-shaped arms cannot.
    @Test func nothingIsCompared() {
        let stub = Self.emit(CalleeReference(bareName: "parse", qualifier: "WikilinkParser"))
        #expect(stub.contains("==") == false)
        #expect(stub.contains("isApproximatelyEqual") == false)
    }

    /// **`try?` is the law, not a shortcut.** The claim is *return **or throw***: a parser handed
    /// malformed bytes is entitled to throw. Swallowing the error would be wrong for every other
    /// law in the catalog and is exactly right for this one.
    @Test func aThrowingSubjectIsAllowedToThrow() {
        let stub = Self.emit(
            CalleeReference(bareName: "decode", qualifier: "Codec", argumentLabels: ["from"]),
            isThrowing: true
        )
        #expect(stub.contains("_ = try? Codec.decode(from: value); return true"))
    }

    @Test func aNonThrowingSubjectIsCalledPlainly() {
        let stub = Self.emit(CalleeReference(bareName: "parse", qualifier: "Codec"))
        #expect(stub.contains("try?") == false)
    }

    // MARK: - Isolation

    @Test func anIsolatedSubjectGetsItsHop() {
        let stub = Self.emit(
            CalleeReference(bareName: "render", qualifier: "View", isolation: "MainActor")
        )
        #expect(stub.contains("await MainActor.run { _ = View.render(value); return true }"))
    }

    /// **An async subject must NOT be wrapped in an actor hop.** `MainActor.run` takes a
    /// *synchronous* `@MainActor` closure, so an `await` cannot appear inside one — the emitted
    /// file would not compile. Awaiting an isolated async function performs the hop by itself.
    ///
    /// This is #432's defect in the opposite direction, and it was a real bug in the first draft
    /// of this arm rather than a hypothetical.
    @Test func anAsyncIsolatedSubjectIsAwaitedRatherThanHopped() {
        let stub = Self.emit(
            CalleeReference(bareName: "load", qualifier: "Store", isolation: "MainActor"),
            isAsync: true
        )
        #expect(stub.contains("MainActor.run") == false)
        #expect(stub.contains("_ = await Store.load(value); return true"))
    }

    @Test func anAsyncThrowingSubjectCarriesBothKeywordsInOrder() {
        let stub = Self.emit(
            CalleeReference(bareName: "fetch", qualifier: "Client"),
            isThrowing: true,
            isAsync: true
        )
        #expect(stub.contains("_ = try? await Client.fetch(value); return true"))
    }

    // MARK: - Scaffold

    @Test func theStubIsAnAsyncTestNamedForItsSubject() {
        let stub = Self.emit(CalleeReference(bareName: "parse", qualifier: "WikilinkParser"))
        #expect(stub.contains("@Test func parse_isTotal() async"))
        #expect(stub.contains("trials: 100"))
    }

    /// The failure label names the subject the way a reader would grep for it — qualified, with
    /// its labels — rather than by the bare name the old splice used.
    @Test func theFailureLabelNamesTheQualifiedSubject() {
        let stub = Self.emit(
            CalleeReference(bareName: "decode", qualifier: "Codec", argumentLabels: ["from"]),
            isThrowing: true
        )
        #expect(stub.contains("Codec.decode(from:) failed totality"))
    }

    @Test func theSeedIsCarriedForReplay() {
        let stub = Self.emit(CalleeReference(bareName: "parse", qualifier: "P"))
        #expect(stub.contains("stateA: 0x123456789ABCDEF0"))
    }
}
