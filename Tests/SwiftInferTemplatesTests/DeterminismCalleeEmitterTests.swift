import SwiftInferCore
import SwiftInferTemplates
import Testing

/// The determinism stub, spelled through `CalleeReference` (#465).
///
/// The emitter took one `String` and spliced it into the call, so every member came out bare —
/// `tokenizeLine(args.0, args.1)` for a member of `SwiftTokenizer` — and failed with
/// `cannot find 'tokenizeLine' in scope`. **In the corpus funnel census all 33 determinism stubs
/// that compiled were free functions; 776 member stubs failed.** The signature-template arms were
/// moved onto `CalleeReference` by #415; this arm dispatches ahead of them and was never moved.
@Suite("Determinism — qualified, labelled, receiver drawn first")
struct DeterminismCalleeEmitterTests {

    private static let seed = SamplingSeed.Value(stateA: 0x1, stateB: 0x2, stateC: 0x3, stateD: 0x4)

    private static func emit(
        _ callee: CalleeReference,
        generators: [String],
        equalityKind: LiftedTestEmitter.EqualityKind = .strict,
        isAsync: Bool = false,
        isThrows: Bool = false
    ) -> String {
        LiftedTestEmitter.deterministic(
            callee: callee,
            generators: generators,
            seed: seed,
            equalityKind: equalityKind,
            isAsync: isAsync,
            isThrows: isThrows
        )
    }

    /// The census's own witness: a static member, now qualified.
    @Test func aStaticMemberIsQualified() {
        let stub = Self.emit(
            CalleeReference(bareName: "tokenizeLine", qualifier: "SwiftTokenizer", argumentLabels: [nil, nil]),
            generators: ["Gen<String>.always(\"x\")", "Gen<Int>.int()"]
        )
        #expect(stub.contains(
            "{ args in SwiftTokenizer.tokenizeLine(args.0, args.1) == SwiftTokenizer.tokenizeLine(args.0, args.1) }"
        ))
    }

    @Test func anInstanceMethodDrawsItsReceiverFirst() {
        let stub = Self.emit(
            CalleeReference(bareName: "render", argumentLabels: [nil], isInstanceMethod: true),
            generators: ["Renderer.gen()", "Gen<String>.always(\"x\")"]
        )
        #expect(stub.contains("let arg0 = (Renderer.gen()).run(using: &rng)"))
        #expect(stub.contains("{ args in args.0.render(args.1) == args.0.render(args.1) }"))
    }

    /// A synchronous isolated member gets one hop, around the whole equality — not one per side,
    /// which would put an `await` inside `MainActor.run`.
    @Test func aSynchronousIsolatedMemberHopsOnce() {
        let stub = Self.emit(
            CalleeReference(bareName: "title", qualifier: "Sidebar", argumentLabels: ["for"], isolation: "MainActor"),
            generators: ["Gen<Int>.int()"]
        )
        #expect(stub.contains(
            "{ value in await MainActor.run { Sidebar.title(for: value) == Sidebar.title(for: value) } }"
        ))
    }

    /// An async member is awaited, never wrapped: `MainActor.run` takes a synchronous closure.
    @Test func anAsyncIsolatedMemberIsAwaitedRatherThanHopped() {
        let stub = Self.emit(
            CalleeReference(bareName: "load", qualifier: "Store", argumentLabels: [nil], isolation: "MainActor"),
            generators: ["Gen<Int>.int()"],
            isAsync: true
        )
        #expect(stub.contains("MainActor.run") == false)
        #expect(stub.contains("(await Store.load(value)) == (await Store.load(value))"))
    }

    @Test func aThrowingInstanceMethodComparesOptionals() {
        let stub = Self.emit(
            CalleeReference(bareName: "parse", argumentLabels: [nil], isInstanceMethod: true),
            generators: ["Parser.gen()", "Gen<String>.always(\"x\")"],
            isThrows: true
        )
        #expect(stub.contains("(try? args.0.parse(args.1)) == (try? args.0.parse(args.1))"))
    }

    @Test func approximateEqualityWrapsTheQualifiedCall() {
        let stub = Self.emit(
            CalleeReference(bareName: "scale", qualifier: "Geometry", argumentLabels: [nil]),
            generators: ["Gen<Int>.int()"],
            equalityKind: .approximate
        )
        #expect(stub.contains("approximatelyEqual(Geometry.scale(value), Geometry.scale(value))"))
    }

    /// The failure message names the subject the way a reader would grep for it. The old label
    /// said `name(_:)` whatever the arity — `combine(_:)` for `combine(_:with:)`.
    @Test func theFailureLabelIsTheQualifiedSignature() {
        let member = Self.emit(
            CalleeReference(bareName: "tokenizeLine", qualifier: "SwiftTokenizer", argumentLabels: [nil]),
            generators: ["Gen<Int>.int()"]
        )
        #expect(member.contains("SwiftTokenizer.tokenizeLine(_:) is not deterministic"))
        let free = LiftedTestEmitter.deterministic(
            funcName: "combine",
            parameters: [
                .init(label: nil, generator: "Gen<Int>.int()"),
                .init(label: "with", generator: "Gen<Int>.int()")
            ],
            seed: Self.seed
        )
        #expect(free.contains("combine(_:with:) is not deterministic"))
    }

    /// **The load-bearing negative.** The `funcName:` form is a free-function callee, so the two
    /// entry points cannot drift apart.
    @Test func theNameFormIsAFreeFunctionCallee() {
        let generators = ["Gen<Int>.int()", "Gen<String>.always(\"x\")"]
        let byName = LiftedTestEmitter.deterministic(
            funcName: "combine",
            parameters: [
                .init(label: nil, generator: generators[0]),
                .init(label: "with", generator: generators[1])
            ],
            seed: Self.seed
        )
        let callee = CalleeReference(bareName: "combine", argumentLabels: [nil, "with"])
        let byCallee = Self.emit(callee, generators: generators)
        #expect(byName == byCallee)
    }
}
