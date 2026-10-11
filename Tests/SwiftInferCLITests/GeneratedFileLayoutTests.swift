import Foundation
@testable import SwiftInferCLI
import Testing

/// `GeneratedFileLayout` breaks the long lines of a written stub without changing what it means.
///
/// Each case checks the shape SwiftLint wants and, where the layout only moves whitespace, that
/// it moved nothing else: `ink` — the text with every space, line break and `;` removed — is the
/// same before and after.
@Suite("Generated file layout — long lines broken, meaning kept")
struct GeneratedFileLayoutTests {

    static let breaker = LayoutBreaker(limit: 120, indentWidth: 4)

    static func lines(_ source: String, indent: Int = 8) throws -> [String] {
        breaker.lines(for: try #require(LayoutParser.nodes(source)), indent: indent)
    }

    /// What a layout may not change.
    static func ink(_ text: String) -> String {
        text.filter { !$0.isWhitespace && $0 != ";" }
    }

    static func parses(_ text: String) -> Bool {
        GeneratedFileLayout.parses(text.components(separatedBy: "\n"))
    }

    // MARK: - Breaking one line

    @Test func aLineThatFitsIsLeftAlone() throws {
        #expect(try Self.lines("foo(alpha, beta)") == ["        foo(alpha, beta)"])
    }

    /// A call taking closures reads one argument at a time, its closer back under its opener.
    @Test func aCallTakingClosuresBreaksOneArgumentPerLine() throws {
        let source = "let result = await backend.check(trials: 100, seed: seed, "
            + "sample: { rng in (Gen<Int>.int()).run(using: &rng) }, "
            + "property: { value in negate(negate(value)) == value })"
        #expect(try Self.lines(source) == [
            "        let result = await backend.check(",
            "            trials: 100,",
            "            seed: seed,",
            "            sample: { rng in (Gen<Int>.int()).run(using: &rng) },",
            "            property: { value in negate(negate(value)) == value }",
            "        )"
        ])
    }

    /// Plain arguments are packed, which is what keeps a memberwise generator short.
    @Test func plainArgumentsArePackedAsManyToALineAsFit() throws {
        let source = "let report = Report(name: drawn.0, count: drawn.1, isComplete: drawn.2, message: drawn.3, "
            + "filesProcessed: drawn.4, totalFiles: drawn.5, violationsFound: drawn.6)"
        let laid = try Self.lines(source)
        #expect(laid.first == "        let report = Report(")
        #expect(laid.last == "        )")
        #expect(laid.count == 4)
        #expect(laid.allSatisfy { $0.count <= 120 })
        #expect(Self.ink(laid.joined(separator: "\n")) == Self.ink(source))
    }

    /// Two calls in a chain break before each `.` — `multiline_function_chains` refuses anything
    /// in between.
    @Test func aChainOfTwoCallsBreaksBeforeEachDot() throws {
        let source = "let values = zip(Gen<Int>.int(), Gen<Int>.int(), Gen<Int>.int(), Gen<Int>.int())"
            + ".map { Pair(first: $0.0, second: $0.1) }.array(of: 0...8)"
        #expect(try Self.lines(source) == [
            "        let values = zip(Gen<Int>.int(), Gen<Int>.int(), Gen<Int>.int(), Gen<Int>.int())",
            "            .map { Pair(first: $0.0, second: $0.1) }",
            "            .array(of: 0...8)"
        ])
    }

    /// A closure broken over lines names its `$n` (`shorthand_argument`), and a nested closure
    /// keeps its own.
    @Test func aClosureThatSpansLinesNamesItsShorthandArguments() throws {
        let source = "let reports = values.map { Report(name: $0.0, tags: $0.1.filter { $0.isEmpty == false }, "
            + "count: $0.2, isComplete: $0.3, message: $0.4) }"
        let laid = try Self.lines(source)
        let text = laid.joined(separator: "\n")
        #expect(laid.first == "        let reports = values.map { drawn in")
        #expect(text.contains("name: drawn.0"))
        #expect(text.contains("{ $0.isEmpty == false }"))
        #expect(laid.last == "        }")
        #expect(Self.parses(text))
    }

    /// A block inside the closure uses the closure's `$n`, so it is renamed there too.
    @Test func aBlockInsideTheClosureIsRenamedWithIt() throws {
        let source = "let kept = values.filter { if $0.count > 10 { return true }; "
            + "return $0.name.isEmpty == false && $0.name.count < 100 && $0.name.hasPrefix(\"draft\") == false }"
        let text = try Self.lines(source).joined(separator: "\n")
        #expect(!text.contains("$0"))
        #expect(text.contains("if drawn.count > 10 { return true }"))
        #expect(Self.parses(text))
    }

    /// The two spellings cannot be mixed, so a `$n` in an interpolation leaves the closure as it was.
    @Test func aShorthandInsideAnInterpolationLeavesTheClosureUnnamed() throws {
        let source = "let labels = values.map { describe(\"\\($0.name) has \\($0.count) items\", "
            + "alignment: .leading, width: 80, truncation: .tail, separator: \", \") }"
        let text = try Self.lines(source).joined(separator: "\n")
        #expect(text.contains("$0.name"))
        #expect(!text.contains("drawn"))
    }

    /// A string literal too long for its line is continued with `\`, and reads back the same.
    @Test func aLongStringLiteralContinuesWithItsValueUnchanged() throws {
        let content = "SwiftLintDeprecations.rulesAdded(from:to:) selected something from an empty range "
            + "at input \\(input). \\(error?.message ?? \"\")"
        let laid = try Self.lines("Issue.record(\"\(content)\")", indent: 16)
        #expect(laid.first == "                Issue.record(")
        #expect(laid[1] == "                    \"\"\"")
        #expect(laid[laid.count - 2] == "                    \"\"\"")
        #expect(laid.last == "                )")
        #expect(laid.allSatisfy { $0.count <= 120 })
        let body = laid[2 ..< laid.count - 2].map { String($0.dropFirst(20)) }
        let value = body.map { $0.hasSuffix("\\") ? String($0.dropLast()) : $0 }.joined()
        #expect(value == content)
        #expect(Self.parses(laid.joined(separator: "\n")))
    }

    /// A `/* … */` marker too long for its line is continued over lines — whitespace to Swift.
    @Test func aLongBlockCommentContinuesOverLines() throws {
        let source = "let arg0 = (Rule.gen() /* no generator derived — Cannot derive a generator for `Rule`: no user "
            + "`init(...)` derives, so supply `static func gen()` and this will compile */).run(using: &rng)"
        let laid = try Self.lines(source)
        #expect(laid.allSatisfy { $0.count <= 120 })
        #expect(Self.ink(laid.joined(separator: "\n")) == Self.ink(source))
        #expect(Self.parses(laid.joined(separator: "\n")))
    }

    @Test func theForceUnwrapOfAListElementBecomesACompactMap() {
        let line = "Gen<String?>.element(of: [\"a\", \"b\"] as [String]).map { $0! }"
        #expect(GeneratedFileLayout.rewritingForceUnwraps(line)
            == "Gen<String?>.element(of: [\"a\", \"b\"] as [String]).compactMap(\\.self)")
    }

    /// The layout moves only whitespace and `;` wherever it does not rewrite.
    static let reflowed: [String] = [
        "let result = await backend.check(trials: 100, seed: seed, sample: { rng in "
            + "let lhs = (Gen<Int>.int()).run(using: &rng); let rhs = (Gen<Int>.int()).run(using: &rng); "
            + "return (lhs, rhs) }, property: { pair in f(pair.0) <= f(pair.1) })",
        "let frequency = Gen.frequency((3.0, Gen<Character>.letterOrNumber.string(of: 0...8)), "
            + "(1.0, Gen<Character>.ascii.string(of: "
            + "0...120)), (1.0, Gen<Character>.latin1.string(of: 0...24)))",
        "if case let .failed(_, _, input, error) = result { Issue.record(\"failed at \\(input)\"); "
            + "recordFailure(input: input, "
            + "error: error, file: #filePath, line: #line) }"
    ]

    @Test("only whitespace moves", arguments: reflowed)
    func onlyWhitespaceMoves(source: String) throws {
        let laid = try Self.lines(source).joined(separator: "\n")
        #expect(Self.ink(laid) == Self.ink(source))
        #expect(laid.split(separator: "\n").allSatisfy { $0.count <= 120 })
        #expect(Self.parses(laid))
    }

    // MARK: - A whole file

    static func file(_ body: [String]) -> String {
        (["struct Suite {", "    func run() {"] + body + ["    }", "}", ""]).joined(separator: "\n")
    }

    /// The kit's continuation style — `.map { … }` at the head of a line — left the sample closure's
    /// brace mid-line (`closure_end_indentation`). The run is joined and broken again. (The generator
    /// reads a local, `bound`, so it stays in place rather than moving to the suite.)
    @Test func theKitsContinuationLinesAreJoinedBeforeBreaking() {
        let input = Self.file([
            "        let bound = 8",
            "        let result = check(",
            "            sample: { rng in (zip(Gen<Character>.letterOrNumber.string(of: 0...bound), Gen<Int>.int())",
            "                .map { Pair(first: $0.0, second: $0.1) }).run(using: &rng) },",
            "            property: { value in value.first.count <= value.second || value.first.isEmpty }",
            "        )"
        ])
        let output = GeneratedFileLayout.laidOut(input)
        let lines = output.components(separatedBy: "\n")
        #expect(!lines.contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix(".map") })
        #expect(lines.contains("            sample: { rng in"))
        #expect(lines.contains("            },"))
        #expect(lines.allSatisfy { $0.count <= 120 })
        #expect(Self.parses(output))
    }

    /// A region holding a `//` comment cannot be flattened onto one line, so it is left alone.
    @Test func aRegionHoldingALineCommentIsLeftAlone() {
        let long = "        let value = compute(alpha: firstArgumentValue, beta: secondArgumentValue, "
            + "gamma: thirdArgumentValue) // keep"
        let input = Self.file([long])
        #expect(GeneratedFileLayout.laidOut(input) == input)
    }

    /// A file that does not parse is not one whose meaning a layout can vouch for.
    @Test func aFileThatDoesNotParseKeepsItsLines() {
        let long = "        let value = (?.gen() /* no generator */).run(using: &rng) "
            + "+ compute(alpha: firstArgumentValue, beta: secondArgumentValue)"
        let input = Self.file([long])
        #expect(GeneratedFileLayout.laidOut(input) == input)
    }

    /// A multi-line literal's content line is continued at the closing delimiter's indentation,
    /// which Swift strips — so the value does not change.
    @Test func multiLineLiteralContentIsContinuedAtTheDelimitersIndentation() throws {
        let content = "NOT APPLIED — no draw entered the sub-domain in 100 trials, so the pass below means nothing. "
            + "Narrow the generator until it reaches it."
        let input = Self.file([
            "        Issue.record(",
            "            \"\"\"",
            "            \(content)",
            "            \"\"\"",
            "        )"
        ])
        let lines = GeneratedFileLayout.laidOut(input).components(separatedBy: "\n")
        let start = try #require(lines.firstIndex(of: "            \"\"\""))
        let end = try #require(lines.lastIndex(of: "            \"\"\""))
        let body = lines[start + 1 ..< end]
        #expect(body.count == 2)
        #expect(body.allSatisfy { $0.hasPrefix("            ") && $0.count <= 120 })
        let value = body.map { String($0.dropFirst(12)) }
            .map { $0.hasSuffix("\\") ? String($0.dropLast()) : $0 }
            .joined()
        #expect(value == content)
    }

    @Test func blankLinesCollapseAndTheFileEndsWithOneNewline() {
        let input = "\n\nlet alpha = 1   \n\n\n\nlet beta = 2\n\n"
        #expect(GeneratedFileLayout.laidOut(input) == "let alpha = 1\n\nlet beta = 2\n")
    }

    /// A long comment wraps at its spaces; the `// Source:` line, which tools read back whole, does not.
    @Test func aLongCommentWrapsButTheSourceLineDoesNot() {
        let comment = "// Access: no test can name the subject: its enclosing type or extension is `private` or "
            + "`fileprivate`, so no test can name it."
        let source = "// Source: Sources/" + String(repeating: "Deep/", count: 24) + "File.swift:12"
        let output = GeneratedFileLayout.laidOut(comment + "\n" + source + "\n")
        let lines = output.components(separatedBy: "\n")
        #expect(lines[0].hasPrefix("// Access: ") && lines[1].hasPrefix("// "))
        #expect(lines[0].count <= 120 && lines[1].count <= 120)
        #expect(lines.contains(source))
    }

    // MARK: - The generator moved beside its test

    static func test(named name: String, sample: String, before: [String] = []) -> [String] {
        ["    @Test func \(name)() async {"] + before + [
            "        let result = await backend.check(",
            "            trials: 100,",
            "            seed: seed,",
            "            sample: \(sample),",
            "            property: { value in value.isEmpty || !value.isEmpty }",
            "        )",
            "    }"
        ]
    }

    static func suite(_ body: [String]) -> String {
        (["struct ReportTests {"] + body + ["}", ""]).joined(separator: "\n")
    }

    static let longGenerator = "zip(Gen<Character>.letterOrNumber.string(of: 0...8), Gen<Int>.int(), Gen<Bool>.bool())"
        + ".map { Report(name: $0.0, count: $0.1, isComplete: $0.2) }"

    static let longSample = "{ rng in (\(longGenerator)).run(using: &rng) }"

    /// A generator too long for its line becomes a static on the suite, drawn from where it was —
    /// so the test keeps its fixed twenty lines (`function_body_length`).
    @Test func aLongGeneratorMovesBesideItsTest() throws {
        let output = GeneratedFileLayout.laidOut(Self.suite(Self.test(named: "report", sample: Self.longSample)))
        #expect(output.contains("    nonisolated private static let generator = zip("))
        #expect(output.contains("            sample: { rng in Self.generator.run(using: &rng) },\n"))
        let stored = try #require(output.range(of: "static let generator"))
        let test = try #require(output.range(of: "@Test func report"))
        #expect(stored.lowerBound < test.lowerBound)
        #expect(Self.parses(output))
    }

    @Test func aShortGeneratorStaysWhereItIs() {
        let input = Self.suite(Self.test(named: "report", sample: "{ rng in (Gen<Int>.int()).run(using: &rng) }"))
        #expect(GeneratedFileLayout.laidOut(input) == input)
    }

    /// A `guard-domain` stub draws its generator twice — counting coverage, then checking — and both
    /// draws name one declaration.
    @Test func twoDrawsOfOneGeneratorShareItsName() {
        let coverage = "        let drawn = (\(Self.longGenerator)).run(using: &coverageRNG)"
        let output = GeneratedFileLayout.laidOut(Self.suite(
            Self.test(named: "report", sample: Self.longSample, before: [coverage])
        ))
        #expect(output.components(separatedBy: "static let ").count == 2)
        #expect(output.contains("let drawn = Self.generator.run(using: &coverageRNG)"))
        #expect(output.contains("sample: { rng in Self.generator.run(using: &rng) },"))
        #expect(Self.parses(output))
    }

    @Test func distinctGeneratorsAreNumbered() {
        let other = "{ rng in (zip(Gen<Int>.int(), Gen<Int>.int(), Gen<Int>.int())"
            + ".map { Pair(first: $0.0, second: $0.1) }).run(using: &rng) }"
        let output = GeneratedFileLayout.laidOut(Self.suite(
            Self.test(named: "first", sample: Self.longSample) + Self.test(named: "second", sample: other)
        ))
        #expect(output.contains("static let generator1 = ") && output.contains("static let generator2 = "))
        #expect(output.contains("Self.generator1.run(using: &rng)"))
        #expect(output.contains("Self.generator2.run(using: &rng)"))
        #expect(Self.parses(output))
    }

    /// A generator naming something the test declares cannot leave the test.
    @Test func aGeneratorNamingALocalStaysInItsTest() {
        let sample = "{ rng in (zip(Gen<Character>.letterOrNumber.string(of: 0...bound), Gen<Int>.int(), "
            + "Gen<Bool>.bool()).map { Report(name: $0.0, count: $0.1, isComplete: $0.2) }).run(using: &rng) }"
        let output = GeneratedFileLayout.laidOut(Self.suite(
            Self.test(named: "report", sample: sample, before: ["        let bound = 8"])
        ))
        #expect(!output.contains("static let"))
        #expect(Self.parses(output))
    }
}
