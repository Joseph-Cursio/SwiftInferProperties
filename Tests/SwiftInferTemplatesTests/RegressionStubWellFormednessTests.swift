@testable import SwiftInferTemplates
import Testing

/// A regression stub has to be Swift (issue #249).
///
/// `verify` wrote this file on a live refutation, and it is invalid in three places at once:
///
///     @Test func SwiftFormatConfig.parse_{ $0.serialized() }_roundTrip_regression_6C179F21() {
///         let value: SwiftFormatConfig =
///         #expect({ $0.serialized() }(SwiftFormatConfig.parse(value)) == value)
///     }
///
/// The name is built from rendered CALL EXPRESSIONS rather than identifiers; the counterexample —
/// the string `"  "` — is interpolated unquoted and vanishes; and the binding is typed at the
/// declaring type while the law quantifies over `String`.
///
/// **None of it was ever caught because the file is written to `Tests/Generated/`, which is not a
/// SwiftPM target**, so it never compiled. It survived a green 159-test run on the subject repo.
/// These arms are the compile the file itself never got.
@Suite("Regression stubs are well-formed Swift")
struct RegressionStubWellFormednessTests {

    /// A Swift identifier: leading letter or `_`, then letters/digits/`_`.
    private func isIdentifier(_ name: String) -> Bool {
        guard let first = name.first, first.isLetter || first == "_" else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private func testFunctionName(in stub: String) -> String? {
        guard let line = stub.split(separator: "\n").first(where: { $0.contains("@Test func") }),
              let open = line.firstIndex(of: "("),
              let start = line.range(of: "@Test func ")?.upperBound else { return nil }
        return String(line[start..<open])
    }

    // MARK: - The exact inputs that produced the bad file

    @Test("the name survives a qualified forward and a receiver-closure inverse")
    func nameIsAnIdentifierForTheObservedShape() throws {
        let stub = LiftedTestEmitter.roundTripRegression(
            forwardName: "SwiftFormatConfig.parse",
            inverseName: "{ $0.serialized() }",
            typeName: "String",
            inputSource: "  "
        )
        let name = try #require(testFunctionName(in: stub))
        #expect(isIdentifier(name), "not an identifier: \(name)")
        // Readable, not merely legal — the method names survive.
        #expect(name.contains("parse"))
        #expect(name.contains("serialized"))
    }

    @Test("a whitespace String counterexample becomes a quoted literal")
    func whitespaceCounterexampleIsQuoted() {
        let stub = LiftedTestEmitter.roundTripRegression(
            forwardName: "parse", inverseName: "serialized", typeName: "String", inputSource: "  "
        )
        // The defect: `let value: String =` with nothing after it.
        #expect(stub.contains("let value: String = \"  \""))
    }

    // MARK: - The sanitiser

    @Test("identifierSafe reduces expressions to their method names")
    func identifierSafeReduces() {
        #expect(LiftedTestEmitter.identifierSafe("SwiftFormatConfig.parse") == "parse")
        #expect(LiftedTestEmitter.identifierSafe("{ $0.serialized() }") == "serialized")
        #expect(LiftedTestEmitter.identifierSafe("a_b") == "a_b")
    }

    @Test("a name with nothing usable falls back rather than emitting empty")
    func identifierSafeFallsBack() {
        // An empty `@Test func ()` is a syntax error too — failing to a named placeholder keeps
        // the file parseable and obviously unfinished, which is the honest failure.
        #expect(LiftedTestEmitter.identifierSafe("{ $0 }") == "regression")
        #expect(LiftedTestEmitter.identifierSafe("") == "regression")
    }

    @Test("an ordinary name is untouched — the sanitiser is not a rewriter")
    func identifierSafeIsIdentityOnCleanNames() {
        #expect(LiftedTestEmitter.identifierSafe("encode_decode_roundTrip_regression_AB12CD34")
            == "encode_decode_roundTrip_regression_AB12CD34")
    }

    @Test("a hash segment beginning with a DIGIT survives")
    func identifierSafeKeepsDigitLeadingSegments() {
        // The arm above passed while the sanitiser was deleting hashes, because `AB12CD34` starts
        // with a letter. Ten of the sixteen possible first characters are digits, and the real
        // hash from #249 is `6C179F21` — so the control was choosing the lucky case ~62% against.
        // Caught by `LiftedTestEmitterRegressionTests`' byte-stable arms, not by this suite.
        #expect(LiftedTestEmitter.identifierSafe("encode_decode_roundTrip_regression_6C179F21")
            == "encode_decode_roundTrip_regression_6C179F21")
    }

    @Test("a name that would START with a digit is prefixed, not truncated")
    func identifierSafeGuardsTheLeadingCharacter() {
        // Only the whole identifier is forbidden from starting with a digit; interior segments are
        // fine. Prefixing keeps the hash, which is what makes the file name and the test name
        // agree.
        #expect(LiftedTestEmitter.identifierSafe("6C179F21") == "regression_6C179F21")
    }

    // MARK: - Quoting

    @Test("only String is quoted; other types already arrive as expressions")
    func literalQuotesOnlyStrings() {
        #expect(LiftedTestEmitter.literal("42", ofType: "Int") == "42")
        #expect(LiftedTestEmitter.literal("(a, b)", ofType: "Pair") == "(a, b)")
        #expect(LiftedTestEmitter.literal("hi", ofType: "String") == "\"hi\"")
    }

    @Test("an already-quoted String is not double-quoted")
    func literalDoesNotDoubleQuote() {
        #expect(LiftedTestEmitter.literal("\"hi\"", ofType: "String") == "\"hi\"")
    }

    @Test("quotes, backslashes and newlines are escaped")
    func literalEscapes() {
        #expect(LiftedTestEmitter.literal("a\"b", ofType: "String") == "\"a\\\"b\"")
        #expect(LiftedTestEmitter.literal("a\nb", ofType: "String") == "\"a\\nb\"")
        #expect(LiftedTestEmitter.literal("a\\b", ofType: "String") == "\"a\\\\b\"")
    }
}
