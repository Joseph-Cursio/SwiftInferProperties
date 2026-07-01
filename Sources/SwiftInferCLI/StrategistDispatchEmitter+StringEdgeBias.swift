import Foundation

// V1.150 — edge-biased String carrier generator.
//
// The kit's raw `String` generator (`Gen<Character>.letterOrNumber.string(of:
// 0...8)`) only ever produces alphanumerics, so a property check over a
// string-processing function never sees whitespace, newlines, or punctuation —
// the exact inputs that falsify structural logic (YAML `- ` markers,
// indentation, trimming, splitting). A determinism/idempotence check on such a
// function then *false-passes*. Mixing curated structural edge strings into the
// generated distribution makes those counterexamples reachable while keeping the
// alphanumeric baseline for ordinary coverage.
extension StrategistDispatchEmitter {

    /// Curated whole-string edge values injected alongside random strings.
    /// Empty / whitespace / newline boundaries plus the YAML/markup tokens
    /// (`-`, `- `, leading-space `-`, multi-line) that dominate real
    /// string-structural bugs.
    static let stringEdgeCases: [String] = [
        "", " ", "  ", "\n", "\t", "-", "- ", "  -", "- x", "a\n- b", ":", "#", "/"
    ]

    /// The generator expression for a top-level `String` carrier, or `nil` for
    /// any other carrier (callers fall back to `RawType.generatorExpression`).
    /// 3:2 weighting keeps random alphanumeric strings the majority while
    /// surfacing a structural edge on ~40% of draws.
    static func edgeBiasedStringExpression(for carrier: String) -> String? {
        guard carrier == "String" else { return nil }
        let edges = stringEdgeCases.map(swiftStringLiteral).joined(separator: ", ")
        return "Gen.frequency("
            + "(3.0, Gen<Character>.letterOrNumber.string(of: 0...8)), "
            + "(2.0, Gen<String?>.element(of: [\(edges)] as [String]).map { $0! })"
            + ")"
    }

    /// Render `value` as a Swift double-quoted string literal, escaping the
    /// characters that would otherwise break the emitted source.
    static func swiftStringLiteral(_ value: String) -> String {
        var out = "\""
        for character in value {
            switch character {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            default: out.append(character)
            }
        }
        out += "\""
        return out
    }
}
