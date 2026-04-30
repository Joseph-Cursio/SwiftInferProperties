import Foundation

/// Parses `// swiftinfer: skip <hash>` rejection markers out of Swift
/// source per PRD v0.3 §7.5. The marker tells `swift-infer discover` to
/// suppress any suggestion whose `SuggestionIdentity` matches `<hash>`.
///
/// The scanner is intentionally line-oriented (not full SwiftSyntax) —
/// the marker syntax is a single comment, the cost of running the parser
/// for every file is wasteful, and we want this to compose with the
/// performance budget in PRD §13. The marker may live anywhere in any
/// `.swift` file in the scanned target; M1.5 makes no attempt to bind a
/// marker to a specific declaration. Future work (binding markers to
/// the function they sit above) lands at M6 alongside the AST-shape
/// hash extension.
public enum SkipMarkerScanner {

    private static let markerPrefix = "swiftinfer: skip "

    /// Skip hashes extracted from `source`, normalized to the form
    /// `SuggestionIdentity.normalized` produces (uppercase, no `0x`
    /// prefix). A trailing `0x` written by the user is tolerated.
    public static func skipHashes(in source: String) -> Set<String> {
        var hashes: Set<String> = []
        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("//") else { continue }
            let comment = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
            guard comment.hasPrefix(markerPrefix) else { continue }
            let raw = comment.dropFirst(markerPrefix.count).trimmingCharacters(in: .whitespaces)
            guard let hash = normalize(raw) else { continue }
            hashes.insert(hash)
        }
        return hashes
    }

    /// Recursively scan `directory` for skip markers in every `.swift`
    /// file. Files are visited in deterministic (sorted-path) order so
    /// the byte-identical-reproducibility guarantee (§16 #6) holds.
    public static func skipHashes(in directory: URL) throws -> Set<String> {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var swiftFiles: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            swiftFiles.append(url)
        }
        swiftFiles.sort { $0.path < $1.path }
        var hashes: Set<String> = []
        for fileURL in swiftFiles {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            hashes.formUnion(skipHashes(in: source))
        }
        return hashes
    }

    /// Strip an optional `0x` prefix and uppercase the rest. Returns
    /// `nil` if the residual isn't a non-empty hex run — a malformed
    /// marker should be treated as a no-op rather than as a wildcard.
    private static func normalize(_ raw: String) -> String? {
        let firstToken: String
        if let split = raw.split(whereSeparator: { $0.isWhitespace }).first {
            firstToken = String(split)
        } else {
            firstToken = ""
        }
        guard !firstToken.isEmpty else { return nil }
        let stripped: String
        if firstToken.hasPrefix("0x") || firstToken.hasPrefix("0X") {
            stripped = String(firstToken.dropFirst(2))
        } else {
            stripped = firstToken
        }
        guard !stripped.isEmpty,
              stripped.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return stripped.uppercased()
    }
}
