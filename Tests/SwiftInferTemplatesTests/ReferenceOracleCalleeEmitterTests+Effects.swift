import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// Shapes G to M of the reference oracle, and the pin that it and the determinism law cannot
/// drift apart.
extension ReferenceOracleCalleeEmitterTests {

    /// G. An async subject is awaited on each side; async-throwing is `try? await`.
    @Test func anAsyncSubjectIsAwaitedOnEachSide() {
        let callee = CalleeReference(bareName: "load", qualifier: "Loader", argumentLabels: [nil])
        let parameters = [Self.parameter(nil, "path", "String")]
        let awaited = Self.emit(
            .init(
                callee: callee, owner: "Loader", parameters: parameters,
                returnTypeText: "Int", isAsync: true, isThrows: false
            ),
            ["String"]
        )
        #expect(awaited.contains("{ value in (await Loader.load(value)) == (await Loader.load_reference(value)) }"))
        #expect(awaited.contains("    static func load_reference(_ path: String) async -> Int {"))

        let throwing = Self.emit(
            .init(
                callee: callee, owner: "Loader", parameters: parameters,
                returnTypeText: "Int", isAsync: true, isThrows: true
            ),
            ["String"]
        )
        #expect(throwing.contains(
            "{ value in (try? await Loader.load(value)) == (try? await Loader.load_reference(value)) }"
        ))
        #expect(throwing.contains("    static func load_reference(_ path: String) async throws -> Int {"))
    }

    /// H. A global-actor member: one hop around the comparison, covering the reference too, which
    /// the extension isolates the same way.
    @Test func aGlobalActorMemberHopsOnce() {
        let scaffold = Self.emit(
            .init(
                callee: CalleeReference(
                    bareName: "title", qualifier: "Sidebar", argumentLabels: ["for"], isolation: "MainActor"
                ),
                owner: "Sidebar",
                parameters: [Self.parameter("for", "count", "Int")],
                returnTypeText: "String", isAsync: false, isThrows: false
            ),
            ["Int"]
        )
        #expect(scaffold.contains(
            "{ value in await MainActor.run { Sidebar.title(for: value) == Sidebar.title_reference(for: value) } }"
        ))
    }

    /// I. An actor-instance member is reached with one `await`; a `nonisolated` one with none, and
    /// its reference must be `nonisolated` too or the un-awaited call does not compile.
    @Test func anActorMemberAwaitsAndANonisolatedOneCopiesTheModifier() {
        let isolated = Self.emit(
            .init(
                callee: CalleeReference(
                    bareName: "count", argumentLabels: ["of"],
                    isolation: CalleeReference.actorReceiverIsolation, isInstanceMethod: true
                ),
                owner: "Ledger",
                parameters: [Self.parameter("of", "entry", "String")],
                returnTypeText: "Int", isAsync: false, isThrows: false
            ),
            ["Ledger", "String"]
        )
        #expect(isolated.contains(
            "{ (args: (Ledger, String)) in await args.0.count(of: args.1) == args.0.count_reference(of: args.1) }"
        ))
        #expect(isolated.contains("extension Ledger {\n    func count_reference(of entry: String) -> Int {"))

        let nonisolated = Self.emit(
            .init(
                callee: CalleeReference(bareName: "count", argumentLabels: ["of"], isInstanceMethod: true),
                owner: "Ledger",
                parameters: [Self.parameter("of", "entry", "String")],
                returnTypeText: "Int", isAsync: false, isThrows: false, declaresNonisolated: true
            ),
            ["Ledger", "String"]
        )
        #expect(nonisolated.contains("in args.0.count(of: args.1) == args.0.count_reference(of: args.1) }"))
        #expect(nonisolated.contains("    nonisolated func count_reference(of entry: String) -> Int {"))
    }

    /// J. An operator is called infix and compared with a NAMED static reference — an operator
    /// character cannot spell `+_reference`.
    @Test func anOperatorIsComparedWithANamedStaticReference() {
        let scaffold = Self.emit(
            .init(
                callee: CalleeReference(bareName: "+", argumentLabels: ["lhs", "rhs"]),
                owner: "Money",
                parameters: [Self.parameter("lhs", "lhs", "Money"), Self.parameter("rhs", "rhs", "Money")],
                returnTypeText: "Money", isAsync: false, isThrows: false
            ),
            ["Money", "Money"]
        )
        #expect(scaffold.contains("    static func plus_reference(_ lhs: Money, _ rhs: Money) -> Money {"))
        #expect(scaffold.contains(
            "{ (args: (Money, Money)) in (args.0 + args.1) == Money.plus_reference(args.0, args.1) }"
        ))
        #expect(scaffold.contains("@Test func Money_plus_matchesReferenceDefinition()"))
    }

    /// K. `-> Self?` is legal in the extension, where a file-scope reference was *global function
    /// cannot return 'Self'*.
    @Test func aSelfReturningFactoryIsDeclaredInsideItsType() {
        let scaffold = Self.emit(
            .init(
                callee: CalleeReference(
                    bareName: "resolve", qualifier: "ReadWindow",
                    argumentLabels: ["lineCount", "startLine", "maxLines", "cap"]
                ),
                owner: "ReadWindow",
                parameters: [
                    Self.parameter("lineCount", "lineCount", "Int"), Self.parameter("startLine", "startLine", "Int?"),
                    Self.parameter("maxLines", "maxLines", "Int?"), Self.parameter("cap", "cap", "Int")
                ],
                returnTypeText: "Self?", isAsync: false, isThrows: false
            ),
            ["Int", "Int?", "Int?", "Int"]
        )
        #expect(scaffold.contains("""
            extension ReadWindow {
                static func resolve_reference(lineCount: Int, startLine: Int?, maxLines: Int?, cap: Int) -> Self? {
            """))
        #expect(scaffold.contains("let arg1 = (Int?.gen()).run(using: &rng)"))
        #expect(scaffold.contains("let arg3 = (Gen.frequency((3.0, Gen<Int>.boundedForArithmetic())"))
    }

    /// L. A floating-point result compares approximately, and the helper is appended exactly once.
    @Test func aFloatingPointResultComparesApproximatelyWithOneHelper() {
        let scaffold = Self.emit(
            .init(
                callee: CalleeReference(bareName: "scale", qualifier: "Geometry", argumentLabels: [nil]),
                owner: "Geometry",
                parameters: [Self.parameter(nil, "length", "Double")],
                returnTypeText: "Double", isAsync: false, isThrows: false
            ),
            ["Double"],
            equalityKind: .approximate
        )
        #expect(scaffold.contains(
            "{ value in approximatelyEqual(Geometry.scale(value), Geometry.scale_reference(value)) }"
        ))
        #expect(scaffold.components(separatedBy: "private func approximatelyEqual<Value: FloatingPoint>").count == 2)
        #expect(scaffold.hasSuffix(LiftedTestEmitter.approximateEqualityHelper))
    }

    /// M. A drawn type that is not `Sendable` gets its shim, live, after the note and before the
    /// reference's extension.
    @Test func aNonSendableInputGetsItsShimBeforeTheExtension() {
        let scaffold = Self.emit(
            .init(
                callee: CalleeReference(bareName: "adding", argumentLabels: [nil], isInstanceMethod: true),
                owner: "Counter",
                parameters: [Self.parameter(nil, "amount", "Int")],
                returnTypeText: "Int", isAsync: false, isThrows: false
            ),
            ["Counter", "Int"],
            shims: ["Counter", "Tally"]
        )
        #expect(scaffold.contains("""
            // (the return type Int must be Equatable for this to compile)
            // Inputs must be Sendable. Declare each of these once per test target, and delete it if \
            SwiftInferSendableShims.swift or another scaffold already does:
            extension Counter: @unchecked Sendable {}
            extension Tally: @unchecked Sendable {}
            extension Counter {
                func adding_reference(_ amount: Int) -> Int {
            """))
    }
}
