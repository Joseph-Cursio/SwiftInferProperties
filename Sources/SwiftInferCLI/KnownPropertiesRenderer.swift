import Foundation

/// V1.145 — rendering + verify-program generation for `known-properties`.
/// Pure and testable: the actual `swift` subprocess run lives in the command.
enum KnownPropertiesRenderer {

    // MARK: - Listing

    /// Group laws by type and render, with a Caveats section. When
    /// `verifyResults` is non-nil, annotate each law with its measured
    /// PASS/FAIL (from a `--verify` run).
    static func renderList(
        _ properties: [KnownProperty],
        verifyResults: [String: Bool]? = nil
    ) -> String {
        let laws = properties.filter { $0.kind == .law }
        let caveats = properties.filter { $0.kind == .caveat }
        guard !laws.isEmpty || !caveats.isEmpty else {
            return "No known properties for the requested types.\n"
        }

        var lines: [String] = []
        let header = verifyResults == nil
            ? "Known standard-library properties (\(laws.count) laws, \(caveats.count) caveats)"
            : "Known standard-library properties — verified"
        lines.append(header)
        lines.append("")

        for type in orderedTypes(laws) {
            lines.append("\(type)")
            for law in laws where law.type == type {
                let mark = verifyResults.map { results in
                    results[law.displayName].map { $0 ? "✓ " : "✗ " } ?? "· "
                } ?? "• "
                let tag = law.witnesses.map { "  → witnesses \($0)" } ?? ""
                let roleTag = law.role == .reference ? "  [reference]" : ""
                lines.append("  \(mark)\(law.statement)   [\(law.structure)]\(tag)\(roleTag)")
                if let note = law.note { lines.append("      \(note)") }
            }
            lines.append("")
        }

        if !caveats.isEmpty {
            lines.append("Caveats — plausible but FALSE (never assert these):")
            for caveat in caveats {
                let roleTag = caveat.role == .reference ? "  [reference]" : "  [trap]"
                lines.append("  ✗ \(caveat.type): \(caveat.statement)\(roleTag)")
                if let note = caveat.note { lines.append("      \(note)") }
            }
            lines.append("")
        }

        if let verifyResults {
            let passed = verifyResults.filter(\.value).count
            lines.append("Verified \(passed)/\(verifyResults.count) laws held under executed property tests.")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func orderedTypes(_ laws: [KnownProperty]) -> [String] {
        var seen = Set<String>()
        return laws.map(\.type).filter { seen.insert($0).inserted }
    }

    // MARK: - Verify program generation

    /// A Swift program that samples inputs with a seeded RNG and prints one
    /// `PASS\t<name>` / `FAIL\t<name>` line per law. With no `imports` it is
    /// stdlib-only and runs via `swift <file>` (the fast interpreter path); with
    /// `imports` it prepends those module imports and is compiled as a temp
    /// package's `main.swift` (the package path) so external Apple-library laws
    /// build against the real releases.
    static func renderVerifyProgram(_ laws: [KnownProperty], imports: [String] = []) -> String {
        var lines: [String] = []
        for module in imports.sorted() {
            lines.append("import \(module)")
        }
        lines.append(preamble)
        for law in laws where law.checkBody != nil {
            lines.append("check(\(escaped(law.displayName))) { \(law.checkBody!) }")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Parse the `PASS\t<name>` / `FAIL\t<name>` stream into a verdict map.
    static func parseVerifyOutput(_ output: String) -> [String: Bool] {
        var results: [String: Bool] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let verdict = parts[0]
            let name = String(parts[1])
            if verdict == "PASS" {
                results[name] = true
            } else if verdict == "FAIL" {
                results[name] = false
            }
        }
        return results
    }

    private static func escaped(_ text: String) -> String {
        "\"" + text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static let preamble = """
    import Foundation

    struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &+ 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }
    var rng = SeededRNG(seed: 0xC0FFEE)
    func randInt() -> Int { Int.random(in: -1000...1000, using: &rng) }
    func randDouble() -> Double { Double.random(in: -1_000_000...1_000_000, using: &rng) }
    func randBool() -> Bool { Bool.random(using: &rng) }
    func randArr() -> [Int] { (0..<Int.random(in: 0...6, using: &rng)).map { _ in randInt() } }
    func randSet() -> Set<Int> { Set(randArr()) }
    func randOpt() -> Int? { Bool.random(using: &rng) ? randInt() : nil }
    func randDict() -> [Int: Int] {
        // Keys from a SMALL space (0...4) so merges and collisions actually occur.
        var dict = [Int: Int]()
        for _ in 0..<Int.random(in: 0...5, using: &rng) { dict[Int.random(in: 0...4, using: &rng)] = randInt() }
        return dict
    }
    func randStr() -> String {
        String((0..<Int.random(in: 0...6, using: &rng)).map { _ in "abcde".randomElement(using: &rng)! })
    }
    func check(_ name: String, _ body: () -> Bool) {
        for _ in 0..<64 where !body() { print("FAIL\\t\\(name)"); return }
        print("PASS\\t\\(name)")
    }
    """
}
