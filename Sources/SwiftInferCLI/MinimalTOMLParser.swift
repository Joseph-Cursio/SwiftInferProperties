import Foundation

/// Hand-rolled TOML 1.0 subset sufficient for `.swiftinfer/config.toml`
/// in M2.2: section headers, key-value pairs whose values are booleans
/// or basic double-quoted strings, line-trailing comments. The M2 plan
/// (open decision #1) defaults to hand-parsing rather than adding a
/// TOML dep — config keys for M2 + M3 + M4 are projected to stay under
/// ten total. If the config surface grows past that, swap to a full
/// TOML library and delete this file.
///
/// **Supported.**
///
/// ```toml
/// # comments survive only outside strings
///
/// [discover]                       # section header
/// includePossible = true           # boolean
/// vocabularyPath = "vocab.json"    # string with \\ \" \n \t escapes
/// ```
///
/// **Explicitly unsupported (throws on encounter).** Numbers, dates,
/// arrays, inline tables, dotted keys, multi-line strings, literal
/// strings, sub-tables. Any of these mean the input outgrew the M2
/// plan's assumption — surfacing as a parse error keeps the tool
/// honest about what it actually understands.
public enum MinimalTOMLParser {

    /// Parse a TOML subset. Returns `[section: [key: value]]` where the
    /// root section (keys outside any `[header]`) is keyed by `""`.
    /// Sections are only created in the result when they hold at least
    /// one key, so an empty file decodes to an empty dictionary.
    public static func parse(_ text: String) throws -> [String: [String: TOMLValue]] {
        var sections: [String: [String: TOMLValue]] = [:]
        var openedHeaderSections: Set<String> = []
        var currentSection = ""

        let lines = text.components(separatedBy: "\n")
        for (idx, rawLine) in lines.enumerated() {
            let lineNumber = idx + 1
            let withoutComment = stripComment(from: rawLine)
            let trimmed = withoutComment.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                continue
            }
            if trimmed.hasPrefix("[") {
                currentSection = try parseSectionHeader(
                    trimmed,
                    lineNumber: lineNumber,
                    openedSoFar: &openedHeaderSections
                )
                continue
            }
            try parseKeyValueLine(
                trimmed,
                into: &sections,
                section: currentSection,
                lineNumber: lineNumber
            )
        }
        return sections
    }

    // MARK: - Section + key-value lines

    private static func parseSectionHeader(
        _ line: String,
        lineNumber: Int,
        openedSoFar: inout Set<String>
    ) throws -> String {
        guard line.hasSuffix("]") else {
            throw TOMLParseError(line: lineNumber, message: "expected closing ']' for section header")
        }
        let inner = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        guard !inner.isEmpty else {
            throw TOMLParseError(line: lineNumber, message: "section name cannot be empty")
        }
        guard isValidBareKey(inner) else {
            throw TOMLParseError(
                line: lineNumber,
                message: "section name '\(inner)' contains characters outside [A-Za-z0-9_-]"
            )
        }
        if openedSoFar.contains(inner) {
            throw TOMLParseError(line: lineNumber, message: "duplicate section header [\(inner)]")
        }
        openedSoFar.insert(inner)
        return inner
    }

    private static func parseKeyValueLine(
        _ line: String,
        into sections: inout [String: [String: TOMLValue]],
        section: String,
        lineNumber: Int
    ) throws {
        guard let equalsIdx = line.firstIndex(of: "=") else {
            throw TOMLParseError(
                line: lineNumber,
                message: "expected key-value or section header, got: \(line)"
            )
        }
        let key = String(line[..<equalsIdx]).trimmingCharacters(in: .whitespaces)
        let valueText = String(line[line.index(after: equalsIdx)...]).trimmingCharacters(in: .whitespaces)
        guard isValidBareKey(key) else {
            throw TOMLParseError(line: lineNumber, message: "invalid key '\(key)'")
        }
        if sections[section]?[key] != nil {
            throw TOMLParseError(
                line: lineNumber,
                message: "duplicate key '\(key)' in section [\(section.isEmpty ? "<root>" : section)]"
            )
        }
        let value = try parseValue(valueText, lineNumber: lineNumber)
        sections[section, default: [:]][key] = value
    }

    // MARK: - Value parsing

    private static func parseValue(_ text: String, lineNumber: Int) throws -> TOMLValue {
        if text == "true" {
            return .boolean(true)
        }
        if text == "false" {
            return .boolean(false)
        }
        if text.hasPrefix("\"") {
            return .string(try parseStringLiteral(text, lineNumber: lineNumber))
        }
        throw TOMLParseError(
            line: lineNumber,
            message: "unsupported value '\(text)' — M2 understands only true/false and \"quoted strings\""
        )
    }

    private static func parseStringLiteral(_ text: String, lineNumber: Int) throws -> String {
        guard text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 else {
            throw TOMLParseError(line: lineNumber, message: "malformed string literal: \(text)")
        }
        let body = text.dropFirst().dropLast()
        var result = ""
        var escape = false
        for char in body {
            if escape {
                switch char {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "n": result.append("\n")
                case "t": result.append("\t")
                default:
                    throw TOMLParseError(
                        line: lineNumber,
                        message: "unsupported escape sequence \\\(char)"
                    )
                }
                escape = false
                continue
            }
            if char == "\\" {
                escape = true
                continue
            }
            result.append(char)
        }
        if escape {
            throw TOMLParseError(line: lineNumber, message: "unterminated escape in string literal")
        }
        return result
    }

    // MARK: - Comment + key validation

    /// Strip a line-trailing `# comment`. `#` inside a double-quoted
    /// string is literal. Backslash escapes inside strings are honoured
    /// so `"path\"with\"quotes"` doesn't false-trigger end-of-string.
    private static func stripComment(from line: String) -> String {
        var inString = false
        var escape = false
        for (offset, char) in line.enumerated() {
            if escape {
                escape = false
                continue
            }
            if inString {
                if char == "\\" {
                    escape = true
                    continue
                }
                if char == "\"" {
                    inString = false
                }
                continue
            }
            if char == "\"" {
                inString = true
                continue
            }
            if char == "#" {
                return String(line.prefix(offset))
            }
        }
        return line
    }

    private static func isValidBareKey(_ key: String) -> Bool {
        guard !key.isEmpty else { return false }
        return key.allSatisfy { char in
            char.isLetter || char.isNumber || char == "_" || char == "-"
        }
    }
}

/// One value in the parsed TOML map. M2.2 only needs booleans and
/// strings; numbers / dates / arrays land in subsequent milestones if
/// the config surface ever requires them (and likely as a dep swap, see
/// `MinimalTOMLParser`'s doc comment).
public enum TOMLValue: Sendable, Equatable {
    case boolean(Bool)
    case string(String)
}

/// Thrown by `MinimalTOMLParser.parse` when the input violates the
/// supported subset. `line` is 1-based to match how editors display it
/// — `ConfigLoader` includes it in the warning rendered to stderr.
public struct TOMLParseError: Error, Equatable, CustomStringConvertible {

    public let line: Int
    public let message: String

    public init(line: Int, message: String) {
        self.line = line
        self.message = message
    }

    public var description: String {
        "TOML parse error at line \(line): \(message)"
    }
}
