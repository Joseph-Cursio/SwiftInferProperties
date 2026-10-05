import Foundation
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// Every shape `referenceOracle(subject:draws:…)` writes is held, verbatim, by
/// `ReferenceOracleScaffoldWitness.swift`, which this test target compiles and runs.
///
/// Each case is emitted here, its one `fatalError(…)` line is replaced by a correct body — the one
/// edit the scaffold asks of its reader — and the witness file must contain the result byte for
/// byte. So the target building proves the emitted text compiles once that line is replaced, and
/// the witness's `@Test`s passing proves the law it states holds for a right reference. If the
/// emitter changes, this fails until the witness is regenerated, and the regenerated witness only
/// builds if the new text compiles.
@Suite("Reference oracle — every emitted shape compiles, and the witness holds it verbatim")
struct ReferenceOracleScaffoldWitnessTests {

    /// One witnessed shape: the emitter's inputs, and the body that replaces `fatalError`.
    struct WitnessCase: Sendable, CustomTestStringConvertible {
        let name: String
        let subject: LiftedTestEmitter.ReferenceOracleSubject
        let draws: LiftedTestEmitter.ReferenceOracleDraws
        var equalityKind: LiftedTestEmitter.EqualityKind = .strict
        let docComment: String
        let body: String

        var testDescription: String { name }
    }

    /// The two witness files: W1 to W5b, and W6 to W11 (split for SwiftLint's file-length cap).
    static let witnessFiles = ["ReferenceOracleScaffoldWitness.swift", "ReferenceOracleScaffoldWitness+Shapes.swift"]
    static let seed = SamplingSeed.Value(stateA: 0x5EED, stateB: 0x0C0FFEE, stateC: 0xBEEF, stateD: 0xF00D)
    static let fatalLine = #"fatalError("state the reference definition from the docstring, then replace this line")"#

    static func witnessText(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(file)
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func witnessText() throws -> String {
        try witnessFiles.map(witnessText).joined(separator: "\n")
    }

    /// The scaffold for `witness`, with its `fatalError` line replaced by the case's body.
    static func witnessed(_ witness: WitnessCase) -> String {
        let scaffold = LiftedTestEmitter.referenceOracle(
            subject: witness.subject,
            draws: witness.draws,
            equalityKind: witness.equalityKind,
            docComment: witness.docComment,
            seed: seed
        )
        return scaffold.replacingOccurrences(of: fatalLine, with: witness.body)
    }

    @Test("the witness holds the scaffold the emitter writes", arguments: ReferenceOracleWitnessCases.all)
    func theWitnessHoldsTheEmittedScaffold(_ witness: WitnessCase) throws {
        let text = try Self.witnessText()
        let scaffold = Self.witnessed(witness)
        #expect(scaffold.contains(Self.fatalLine) == false, "the body replaced the one line the reader edits")
        #expect(text.contains(scaffold), "regenerate the witness; the emitter now writes:\n\(scaffold)")
    }

    /// What each witnessed shape exercises, read off the emitted text — so a case cannot drift
    /// into a shape that no longer tests what its name says.
    @Test("each witnessed case is the shape its name claims", arguments: [
        ("W1", "extension OracleWitnessInbox {\n    static func largest_reference(in messages: [Message])"),
        ("W2", "(try? args.0.celsius(offset: args.1)) == (try? args.0.celsius_reference(offset: args.1))"),
        ("W3a", "in await args.0.advanced(by: args.1) == args.0.advanced_reference(by: args.1) }"),
        ("W3b", "    nonisolated func doubled_reference(_ step: Int) -> Int {"),
        ("W4", "{ value in await MainActor.run { OracleWitnessSidebar.title(for: value) =="),
        ("W5a", "(await OracleWitnessLoader.load(value)) == (await OracleWitnessLoader.load_reference(value))"),
        ("W5b", "(try? await OracleWitnessLoader.decode(value)) == (try? await"),
        ("W6", "(args.0 + args.1) == OracleWitnessMoney.plus_reference(args.0, args.1)"),
        ("W7", "static func resolve_reference(lineCount: Int, startLine: Int?, maxLines: Int?, cap: Int) -> Self?"),
        ("W8", "{ (args: (String, String)) in oracleWitnessHasPrefix(args.0, matching: args.1) =="),
        ("W9", "extension String {\n    func oracleWitnessClipped_reference(toLength limit: Int)"),
        ("W10", "approximatelyEqual(OracleWitnessGeometry.scaled(args.0, by: args.1), "),
        ("W11", "extension OracleWitnessTally: @unchecked Sendable {}\nextension OracleWitnessTally {")
    ])
    func eachWitnessedCaseIsTheShapeItsNameClaims(name: String, shape: String) throws {
        let witness = try #require(ReferenceOracleWitnessCases.all.first { $0.name == name })
        #expect(Self.witnessed(witness).contains(shape))
    }

    /// The floating-point case is the only one carrying the helper, and each file declares it at
    /// most once — two `private` helpers in one file would be a redeclaration.
    @Test func theApproximateHelperIsWrittenOnceAndOnlyWhereItIsUsed() throws {
        let carrying = ReferenceOracleWitnessCases.all.filter { Self.witnessed($0).contains("func approximatelyEqual") }
        #expect(carrying.map(\.name) == ["W10"])
        let perFile = try Self.witnessFiles.map { file in
            try Self.witnessText(file).components(separatedBy: "func approximatelyEqual").count - 1
        }
        #expect(perFile == [0, 1])
    }
}

/// The witnessed cases, W1 to W11 of the design, apart from the suite for SwiftLint's
/// type-body-length cap.
enum ReferenceOracleWitnessCases {
    typealias WitnessCase = ReferenceOracleScaffoldWitnessTests.WitnessCase

    private static func parameter(_ label: String?, _ name: String, _ type: String) -> Parameter {
        Parameter(label: label, internalName: name, typeText: type, isInout: false)
    }

    static let all: [WitnessCase] = members + effects + shapes

    /// W1, W2, W3a, W3b: a static member over a nested type, a throwing instance method with a
    /// drawn receiver, an actor instance method, and a `nonisolated` actor member.
    static let members: [WitnessCase] = [
        WitnessCase(
            name: "W1",
            subject: .init(
                callee: CalleeReference(bareName: "largest", qualifier: "OracleWitnessInbox", argumentLabels: ["in"]),
                owner: "OracleWitnessInbox",
                parameters: [parameter("in", "messages", "[Message]")],
                returnTypeText: "Int?", isAsync: false, isThrows: false
            ),
            draws: .init(
                generators: ["Gen<Int>.int(in: 0...99).map { OracleWitnessInbox.Message(size: $0) }.array(of: 0...8)"],
                argumentTypes: ["[OracleWitnessInbox.Message]"]
            ),
            docComment: "Returns the size of the largest message, or nil when there are none.",
            body: "messages.map(\\.size).max()"
        ),
        WitnessCase(
            name: "W2",
            subject: .init(
                callee: CalleeReference(bareName: "celsius", argumentLabels: ["offset"], isInstanceMethod: true),
                owner: "OracleWitnessTemperature",
                parameters: [parameter("offset", "offset", "Int")],
                returnTypeText: "Int", isAsync: false, isThrows: true
            ),
            draws: .init(
                generators: [
                    "Gen<Int>.int(in: -300...300).map { OracleWitnessTemperature(kelvin: $0) }", "Gen<Int>.int()"
                ],
                argumentTypes: ["OracleWitnessTemperature", "Int"]
            ),
            docComment: "Returns the temperature in Celsius plus the offset; throws for a negative Kelvin reading.",
            body: "if kelvin < 0 { throw OracleWitnessError.negativeKelvin }; return offset + kelvin - 273"
        ),
        WitnessCase(
            name: "W3a",
            subject: .init(
                callee: CalleeReference(
                    bareName: "advanced", argumentLabels: ["by"],
                    isolation: CalleeReference.actorReceiverIsolation, isInstanceMethod: true
                ),
                owner: "OracleWitnessCounter",
                parameters: [parameter("by", "step", "Int")],
                returnTypeText: "Int", isAsync: false, isThrows: false
            ),
            draws: .init(
                generators: ["Gen<Int>.int(in: -99...99).map { OracleWitnessCounter(base: $0) }", "Gen<Int>.int()"],
                argumentTypes: ["OracleWitnessCounter", "Int"]
            ),
            docComment: "Returns the base advanced by the step.",
            body: "step &+ base"
        ),
        WitnessCase(
            name: "W3b",
            subject: .init(
                callee: CalleeReference(bareName: "doubled", argumentLabels: [nil], isInstanceMethod: true),
                owner: "OracleWitnessCounter",
                parameters: [parameter(nil, "step", "Int")],
                returnTypeText: "Int", isAsync: false, isThrows: false, declaresNonisolated: true
            ),
            draws: .init(
                generators: ["Gen<Int>.int(in: -99...99).map { OracleWitnessCounter(base: $0) }", "Gen<Int>.int()"],
                argumentTypes: ["OracleWitnessCounter", "Int"]
            ),
            docComment: "Returns the step doubled, and never reads the counter.",
            body: "step &+ step"
        )
    ]

    /// W4, W5a, W5b: a `@MainActor` static (one hop), an async static and an async throwing one.
    static let effects: [WitnessCase] = [
        WitnessCase(
            name: "W4",
            subject: .init(
                callee: CalleeReference(
                    bareName: "title", qualifier: "OracleWitnessSidebar",
                    argumentLabels: ["for"], isolation: "MainActor"
                ),
                owner: "OracleWitnessSidebar",
                parameters: [parameter("for", "count", "Int")],
                returnTypeText: "String", isAsync: false, isThrows: false
            ),
            draws: .init(generators: ["Gen<Int>.int()"], argumentTypes: ["Int"]),
            docComment: "Returns the inbox title, with the count in parentheses.",
            body: "\"Inbox (\" + String(count) + \")\""
        ),
        WitnessCase(
            name: "W5a",
            subject: .init(
                callee: CalleeReference(bareName: "load", qualifier: "OracleWitnessLoader", argumentLabels: [nil]),
                owner: "OracleWitnessLoader",
                parameters: [parameter(nil, "text", "String")],
                returnTypeText: "Int", isAsync: true, isThrows: false
            ),
            draws: .init(generators: ["Gen<Character>.letterOrNumber.string(of: 0...8)"], argumentTypes: ["String"]),
            docComment: "Returns the number of characters in the text.",
            body: "text.count"
        ),
        WitnessCase(
            name: "W5b",
            subject: .init(
                callee: CalleeReference(bareName: "decode", qualifier: "OracleWitnessLoader", argumentLabels: [nil]),
                owner: "OracleWitnessLoader",
                parameters: [parameter(nil, "text", "String")],
                returnTypeText: "Int", isAsync: true, isThrows: true
            ),
            draws: .init(generators: ["Gen<Character>.letterOrNumber.string(of: 0...8)"], argumentTypes: ["String"]),
            docComment: "Returns the decimal number the text spells, and throws when it spells none.",
            body: "guard let value = Int(text) else { throw OracleWitnessError.notANumber }; return value"
        )
    ]

    /// W6 to W11: an operator, a `-> Self?` factory with optional parameters, a free function over
    /// two real `String` generators, a stdlib-carrier extension returning a tuple, a `Double`
    /// result, and a non-`Sendable` class receiver with its shim.
    static let shapes: [WitnessCase] = [
        WitnessCase(
            name: "W6",
            subject: .init(
                callee: CalleeReference(bareName: "+", argumentLabels: ["lhs", "rhs"]),
                owner: "OracleWitnessMoney",
                parameters: [parameter("lhs", "lhs", "Self"), parameter("rhs", "rhs", "Self")],
                returnTypeText: "Self", isAsync: false, isThrows: false
            ),
            draws: .init(
                generators: Array(repeating: "Gen<Int>.int().map { OracleWitnessMoney(cents: $0) }", count: 2),
                argumentTypes: ["OracleWitnessMoney", "OracleWitnessMoney"]
            ),
            docComment: "Returns the sum of both amounts, in cents.",
            body: "Self(cents: rhs.cents &+ lhs.cents)"
        ),
        WitnessCase(
            name: "W7",
            subject: .init(
                callee: CalleeReference(
                    bareName: "resolve", qualifier: "OracleWitnessWindow",
                    argumentLabels: ["lineCount", "startLine", "maxLines", "cap"]
                ),
                owner: "OracleWitnessWindow",
                parameters: [
                    parameter("lineCount", "lineCount", "Int"), parameter("startLine", "startLine", "Int?"),
                    parameter("maxLines", "maxLines", "Int?"), parameter("cap", "cap", "Int")
                ],
                returnTypeText: "Self?", isAsync: false, isThrows: false
            ),
            draws: .init(
                generators: [
                    "Gen<Int>.int()", LiftedTestEmitter.defaultGenerator(for: "Int?"),
                    LiftedTestEmitter.defaultGenerator(for: "Int?"), "Gen<Int>.int()"
                ],
                argumentTypes: ["Int", "Int?", "Int?", "Int"]
            ),
            docComment: "Returns the window starting at the start line, at most the cap long, or nil when it is empty.",
            body: "let first = Swift.max(startLine ?? 1, 1); guard first <= lineCount else { return nil }; "
                + "let size = Swift.min(maxLines ?? cap, cap, lineCount - first + 1); "
                + "return size > 0 ? Self(start: first, count: size) : nil"
        ),
        WitnessCase(
            name: "W8",
            subject: .init(
                callee: CalleeReference(bareName: "oracleWitnessHasPrefix", argumentLabels: [nil, "matching"]),
                owner: nil,
                parameters: [parameter(nil, "name", "String"), parameter("matching", "pattern", "String")],
                returnTypeText: "Bool", isAsync: false, isThrows: false
            ),
            draws: .init(
                generators: Array(repeating: LiftedTestEmitter.defaultGenerator(for: "String"), count: 2),
                argumentTypes: ["String", "String"]
            ),
            docComment: "Returns whether the name starts with the pattern.",
            body: "name.starts(with: pattern)"
        ),
        WitnessCase(
            name: "W9",
            subject: .init(
                callee: CalleeReference(
                    bareName: "oracleWitnessClipped", argumentLabels: ["toLength"], isInstanceMethod: true
                ),
                owner: "String",
                parameters: [parameter("toLength", "limit", "Int")],
                returnTypeText: "(text: String, didTruncate: Bool)", isAsync: false, isThrows: false
            ),
            draws: .init(
                generators: ["Gen<Character>.letterOrNumber.string(of: 0...8)", "Gen<Int>.int()"],
                argumentTypes: ["String", "Int"]
            ),
            docComment: "Returns the prefix that fits in the length budget, and whether anything was cut.",
            body: "let kept = String(prefix(Swift.max(limit, 0))); return (kept, kept.count < count)"
        ),
        WitnessCase(
            name: "W10",
            subject: .init(
                callee: CalleeReference(
                    bareName: "scaled", qualifier: "OracleWitnessGeometry", argumentLabels: [nil, "by"]
                ),
                owner: "OracleWitnessGeometry",
                parameters: [parameter(nil, "length", "Double"), parameter("by", "factor", "Double")],
                returnTypeText: "Double", isAsync: false, isThrows: false
            ),
            draws: .init(
                generators: Array(repeating: "Gen<Double>.double(in: -1_000_000...1_000_000)", count: 2),
                argumentTypes: ["Double", "Double"]
            ),
            equalityKind: .approximate,
            docComment: "Returns the length scaled by the factor, never negative.",
            body: "abs(factor * length)"
        ),
        WitnessCase(
            name: "W11",
            subject: .init(
                callee: CalleeReference(bareName: "adding", argumentLabels: [nil], isInstanceMethod: true),
                owner: "OracleWitnessTally",
                parameters: [parameter(nil, "amount", "Int")],
                returnTypeText: "Int", isAsync: false, isThrows: false
            ),
            draws: .init(
                generators: ["Gen<Int>.int(in: -99...99).map { OracleWitnessTally(total: $0) }", "Gen<Int>.int()"],
                argumentTypes: ["OracleWitnessTally", "Int"],
                sendableShims: ["OracleWitnessTally"]
            ),
            docComment: "Returns the total plus the amount, and leaves the tally unchanged.",
            body: "amount &+ total"
        )
    ]
}
