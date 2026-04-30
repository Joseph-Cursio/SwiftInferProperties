import Testing
@testable import SwiftInferCLI

@Suite("MinimalTOMLParser — section + key=value subset for .swiftinfer/config.toml")
struct MinimalTOMLParserTests {

    // MARK: - Happy path

    @Test("Empty input parses to empty dictionary")
    func emptyInput() throws {
        let parsed = try MinimalTOMLParser.parse("")
        #expect(parsed.isEmpty)
    }

    @Test("Whitespace and comments only parse to empty dictionary")
    func whitespaceAndCommentsOnly() throws {
        let parsed = try MinimalTOMLParser.parse("""
        # top-level comment

        # another


        """)
        #expect(parsed.isEmpty)
    }

    @Test("Section header with bool and string values decodes correctly")
    func basicSectionDecode() throws {
        let parsed = try MinimalTOMLParser.parse("""
        [discover]
        includePossible = true
        vocabularyPath = "vocab.json"
        """)
        #expect(parsed["discover"]?["includePossible"] == .boolean(true))
        #expect(parsed["discover"]?["vocabularyPath"] == .string("vocab.json"))
    }

    @Test("Multiple sections each carry their own keys")
    func multipleSections() throws {
        let parsed = try MinimalTOMLParser.parse("""
        [alpha]
        flag = true

        [beta]
        flag = false
        path = "x"
        """)
        #expect(parsed["alpha"]?["flag"] == .boolean(true))
        #expect(parsed["beta"]?["flag"] == .boolean(false))
        #expect(parsed["beta"]?["path"] == .string("x"))
    }

    @Test("Root-level keys (no section header) live under the empty-string key")
    func rootLevelKeys() throws {
        let parsed = try MinimalTOMLParser.parse("""
        name = "root-key"
        """)
        #expect(parsed[""]?["name"] == .string("root-key"))
    }

    @Test("Comments after a value are stripped before parsing")
    func trailingComments() throws {
        let parsed = try MinimalTOMLParser.parse("""
        [discover]
        includePossible = true   # turn this on for noisy projects
        vocabularyPath = "p.json" # path to vocab
        """)
        #expect(parsed["discover"]?["includePossible"] == .boolean(true))
        #expect(parsed["discover"]?["vocabularyPath"] == .string("p.json"))
    }

    @Test("Hash inside a string is preserved, not treated as a comment")
    func hashInString() throws {
        let parsed = try MinimalTOMLParser.parse("""
        [section]
        path = "directory/with#hash.json"
        """)
        #expect(parsed["section"]?["path"] == .string("directory/with#hash.json"))
    }

    @Test("Escape sequences in strings decode")
    func stringEscapes() throws {
        let parsed = try MinimalTOMLParser.parse("""
        [s]
        quote = "with \\"quotes\\""
        backslash = "back\\\\slash"
        newline = "line\\nbreak"
        tab = "before\\tafter"
        """)
        #expect(parsed["s"]?["quote"] == .string(#"with "quotes""#))
        #expect(parsed["s"]?["backslash"] == .string(#"back\slash"#))
        #expect(parsed["s"]?["newline"] == .string("line\nbreak"))
        #expect(parsed["s"]?["tab"] == .string("before\tafter"))
    }

    @Test("Whitespace around = is tolerated")
    func whitespaceAroundEquals() throws {
        let parsed = try MinimalTOMLParser.parse("""
        [discover]
            includePossible    =    true
        """)
        #expect(parsed["discover"]?["includePossible"] == .boolean(true))
    }

    // MARK: - Error paths

    @Test("Section header without closing bracket throws")
    func unclosedSectionHeader() {
        #expect(throws: TOMLParseError.self) {
            try MinimalTOMLParser.parse("[discover\nflag = true")
        }
    }

    @Test("Empty section name throws")
    func emptySectionName() {
        #expect(throws: TOMLParseError.self) {
            try MinimalTOMLParser.parse("[]\nflag = true")
        }
    }

    @Test("Section name with invalid characters throws")
    func invalidSectionName() {
        #expect(throws: TOMLParseError.self) {
            try MinimalTOMLParser.parse("[has space]\nflag = true")
        }
    }

    @Test("Duplicate section header throws")
    func duplicateSectionHeader() {
        #expect(throws: TOMLParseError.self) {
            try MinimalTOMLParser.parse("""
            [discover]
            flag = true
            [discover]
            other = false
            """)
        }
    }

    @Test("Duplicate key in same section throws")
    func duplicateKey() {
        #expect(throws: TOMLParseError.self) {
            try MinimalTOMLParser.parse("""
            [discover]
            flag = true
            flag = false
            """)
        }
    }

    @Test("Line that is neither section nor key=value throws")
    func malformedLine() {
        #expect(throws: TOMLParseError.self) {
            try MinimalTOMLParser.parse("just-some-words")
        }
    }

    @Test("Unsupported value type (number) throws — M2 only handles bool + string")
    func unsupportedNumberValue() {
        #expect(throws: TOMLParseError.self) {
            try MinimalTOMLParser.parse("threshold = 80")
        }
    }

    @Test("Unterminated string literal throws")
    func unterminatedString() {
        #expect(throws: TOMLParseError.self) {
            try MinimalTOMLParser.parse(#"path = "no-close"#)
        }
    }

    @Test("Unsupported escape sequence throws")
    func unsupportedEscape() {
        #expect(throws: TOMLParseError.self) {
            try MinimalTOMLParser.parse(#"path = "bad\xescape""#)
        }
    }

    @Test("Error carries the offending line number (1-based)")
    func errorReportsLineNumber() throws {
        do {
            _ = try MinimalTOMLParser.parse("""
            [discover]
            flag = true
            broken-line-here
            """)
            Issue.record("expected throw")
        } catch let error as TOMLParseError {
            #expect(error.line == 3)
        }
    }
}
