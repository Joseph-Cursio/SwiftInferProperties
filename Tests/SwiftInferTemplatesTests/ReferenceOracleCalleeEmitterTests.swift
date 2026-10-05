import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The docstring advisory's reference oracle, spelled the way `accept` spells the determinism law.
///
/// The scaffold used to splice the bare name into its call and declare the reference at file
/// scope, so a static member read `correlation(for: value)` (*cannot find 'correlation' in
/// scope*), an instance method had no receiver, and a `throws` subject had no `try`. Every shape
/// below is the spec's (A to M), pinned on the text that decides whether it compiles: where the
/// reference is declared, the property line, the test's name and the failure label.
/// `ReferenceOracleScaffoldWitness` compiles the same shapes.
@Suite("Reference oracle — the call is accept's, the reference is declared beside the subject")
struct ReferenceOracleCalleeEmitterTests {

    static let seed = SamplingSeed.Value(stateA: 0x1, stateB: 0x2, stateC: 0x3, stateD: 0x4)

    static func parameter(_ label: String?, _ name: String, _ type: String) -> Parameter {
        Parameter(label: label, internalName: name, typeText: type, isInout: false)
    }

    /// The scaffold for one subject, drawing `generators` for `argumentTypes`.
    static func emit(
        _ subject: LiftedTestEmitter.ReferenceOracleSubject,
        _ argumentTypes: [String],
        equalityKind: LiftedTestEmitter.EqualityKind = .strict,
        shims: [String] = []
    ) -> String {
        LiftedTestEmitter.referenceOracle(
            subject: subject,
            draws: .init(
                generators: argumentTypes.map { "\($0).gen()" }, argumentTypes: argumentTypes, sendableShims: shims
            ),
            equalityKind: equalityKind,
            docComment: "The documented contract.",
            seed: seed
        )
    }

    /// A. One-parameter free function: the old entry point, the subject entry point and the text
    /// f87bb241 printed are one string.
    @Test func aOneParameterFreeFunctionIsByteIdenticalToBefore() {
        let quantity = Self.parameter(nil, "quantity", "Double")
        let old = LiftedTestEmitter.referenceOracle(
            funcName: "isValidQuantity",
            arguments: [.init(parameter: quantity, generator: "Gen<Double>.double()")],
            returnTypeText: "Bool",
            docComment: "A quantity is valid when it is finite and not negative.",
            seed: Self.seed
        )
        let viaSubject = LiftedTestEmitter.referenceOracle(
            subject: .init(
                callee: CalleeReference(bareName: "isValidQuantity", argumentLabels: [nil]),
                owner: nil, parameters: [quantity], returnTypeText: "Bool", isAsync: false, isThrows: false
            ),
            draws: .init(generators: ["Gen<Double>.double()"], argumentTypes: ["Double"]),
            equalityKind: .strict,
            docComment: "A quantity is valid when it is finite and not negative.",
            seed: Self.seed
        )
        #expect(viaSubject == old)
        #expect(old == ReferenceOracleFrozenText.isValidQuantity)
    }

    /// B. Several parameters: one `let` per draw, and the annotated binding.
    @Test func aMultiParameterFreeFunctionDrawsEachArgumentAndAnnotatesTheBinding() {
        let scaffold = Self.emit(
            .init(
                callee: CalleeReference(bareName: "canReach", argumentLabels: ["from", "to"]),
                owner: nil,
                parameters: [Self.parameter("from", "origin", "Int"), Self.parameter("to", "target", "Int")],
                returnTypeText: "Bool", isAsync: false, isThrows: false
            ),
            ["Int", "Int"]
        )
        #expect(scaffold.contains("func canReach_reference(from origin: Int, to target: Int) -> Bool {\n"))
        #expect(scaffold.contains("sample: { rng in\n                    let arg0 = (Gen.frequency("))
        #expect(scaffold.contains("                    return (arg0, arg1)\n                },"))
        #expect(scaffold.contains(
            "{ (args: (Int, Int)) in canReach(from: args.0, to: args.1) == "
                + "canReach_reference(from: args.0, to: args.1) }"
        ))
        #expect(scaffold.contains("@Test func canReach_matchesReferenceDefinition()"))
        #expect(scaffold.contains("extension") == false)
    }

    /// C. A static member: qualified call, reference declared `static` in an extension, the owner
    /// in the test name and the failure label.
    @Test func aStaticMemberIsQualifiedAndItsReferenceLivesInAnExtension() {
        let scaffold = Self.emit(
            .init(
                callee: CalleeReference(bareName: "correlation", qualifier: "BeadCorrelation", argumentLabels: ["for"]),
                owner: "BeadCorrelation",
                parameters: [Self.parameter("for", "observations", "[BeadObservation]")],
                returnTypeText: "Double?", isAsync: false, isThrows: false
            ),
            ["[BeadObservation]"]
        )
        #expect(scaffold.contains("""
            extension BeadCorrelation {
                static func correlation_reference(for observations: [BeadObservation]) -> Double? {
                    fatalError("state the reference definition from the docstring, then replace this line")
                }
            }
            """))
        #expect(scaffold.contains(
            "{ value in BeadCorrelation.correlation(for: value) == BeadCorrelation.correlation_reference(for: value) }"
        ))
        #expect(scaffold.contains("@Test func BeadCorrelation_correlation_matchesReferenceDefinition()"))
        #expect(scaffold.contains("\"BeadCorrelation.correlation(for:) disagrees with its documented reference"))
    }

    /// D. An instance method draws its receiver first; the reference is an instance member too.
    @Test func anInstanceMethodDrawsItsReceiver() {
        let scaffold = Self.emit(
            .init(
                callee: CalleeReference(bareName: "relative", argumentLabels: [nil], isInstanceMethod: true),
                owner: "WorkspaceJail",
                parameters: [Self.parameter(nil, "url", "URL")],
                returnTypeText: "String", isAsync: false, isThrows: false
            ),
            ["WorkspaceJail", "URL"]
        )
        #expect(scaffold.contains("extension WorkspaceJail {\n    func relative_reference(_ url: URL) -> String {"))
        #expect(scaffold.contains("let arg0 = (WorkspaceJail.gen()).run(using: &rng)"))
        #expect(scaffold.contains("let arg1 = (URL.gen()).run(using: &rng)"))
        #expect(scaffold.contains(
            "{ (args: (WorkspaceJail, URL)) in args.0.relative(args.1) == args.0.relative_reference(args.1) }"
        ))
        #expect(scaffold.contains("\"WorkspaceJail.relative(_:) disagrees with its documented reference definition"))
    }

    /// E. A method on a standard-library type, returning a labelled tuple.
    @Test func aStdlibCarrierExtensionExtendsTheCarrier() {
        let scaffold = Self.emit(
            .init(
                callee: CalleeReference(bareName: "prefix", argumentLabels: ["utf8Bytes"], isInstanceMethod: true),
                owner: "String",
                parameters: [Self.parameter("utf8Bytes", "limit", "Int")],
                returnTypeText: "(text: String, didTruncate: Bool)", isAsync: false, isThrows: false
            ),
            ["String", "Int"]
        )
        #expect(scaffold.contains("""
            extension String {
                func prefix_reference(utf8Bytes limit: Int) -> (text: String, didTruncate: Bool) {
            """))
        #expect(scaffold.contains(
            "{ (args: (String, Int)) in args.0.prefix(utf8Bytes: args.1) == "
                + "args.0.prefix_reference(utf8Bytes: args.1) }"
        ))
        #expect(scaffold.contains("every element of the returned tuple must be Equatable"))
    }

    /// F. A throwing subject: `try?` on both sides, a throwing reference, and the note saying what
    /// that comparison means.
    @Test func aThrowingSubjectComparesTryOnBothSides() {
        let scaffold = Self.emit(
            .init(
                callee: CalleeReference(bareName: "parse", qualifier: "CoverageReport", argumentLabels: ["from"]),
                owner: "CoverageReport",
                parameters: [Self.parameter("from", "data", "Data")],
                returnTypeText: "Double", isAsync: false, isThrows: true
            ),
            ["Data"],
            equalityKind: .approximate
        )
        #expect(scaffold.contains("    static func parse_reference(from data: Data) throws -> Double {"))
        #expect(scaffold.contains(
            "{ value in (try? CoverageReport.parse(from: value)) == "
                + "(try? CoverageReport.parse_reference(from: value)) }"
        ))
        #expect(scaffold.contains(
            "// It throws, so both sides are compared through try?: throwing on the same inputs counts as "
                + "agreeing (which error is not compared).\n"
        ))
        // Two `Optional`s compare with `==`, so a throwing `Double` needs no helper.
        #expect(scaffold.contains("approximatelyEqual") == false)
    }
}
