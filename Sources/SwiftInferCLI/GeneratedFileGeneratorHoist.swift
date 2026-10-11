/// Moves each long generator a stub draws from — `(G).run(using: &rng)` — out of its `@Test`
/// function into a `nonisolated private static let` on the suite, so wrapping it inside 120
/// columns does not push the test past `function_body_length`.
///
/// ## Why the generator has to move
///
/// Breaking a long line makes more lines. A memberwise generator for a five-field type holding
/// arrays of five-field types fits nowhere near 120 columns, and laid out it is fifty lines on its
/// own; on SwiftLintRuleStudio's core package, wrapping in place took 24 of 59 accepted tests past
/// the rule's 50-line warning and one past its 100-line error. The generator is the only part of a
/// test that grows with the subject — the seed, the call and the failure report are a fixed twenty
/// lines — so it is the part that moves. A `guard-domain` stub draws the same generator twice, in
/// its coverage loop and in its sample, and the two now name one declaration.
///
/// ## Why the moved generator draws exactly what it drew in place
///
/// A `Generator` is a value — a description of how to draw, holding `@Sendable` closures and no
/// state — so building it once, statically, and building it on every draw are the same thing:
/// `run(using:)` reads the same `Xoshiro`, passed `inout`, in the same order. It is `Sendable`, which
/// a static stored property must be under Swift 6, and `nonisolated`, because the closure it is
/// drawn in runs isolated to nothing — which is what lets it build under a package's
/// `defaultIsolation(MainActor)`. Its type is inferred from the expression, as the inline one was:
/// `(G)` is parenthesised precisely so nothing around it takes part. Measured to build without
/// warnings under `defaultIsolation(MainActor)` and in Swift 5 language mode.
///
/// A generator that names something declared in the test — a `let`, a `var`, the `rng` it is drawn
/// with — cannot leave it, and stays where it is.
enum GeneratedFileGeneratorHoist {

    static func hoisted(_ lines: [String]) -> [String] {
        let scan = GeneratedFileScan(lines)
        guard scan.balanced,
              let suite = lines.firstIndex(where: { $0.hasPrefix("struct ") && $0.hasSuffix(" {") })
        else { return lines }
        let regions = Self.drawingRegions(lines: lines, scan: scan)
        let local = Self.declaredNames(in: lines)
        var draws: [(region: ClosedRange<Int>, flat: String)] = []
        var generators: [String] = []
        for region in regions {
            guard let flat = GeneratedFileRegions.flattened(Array(lines[region])),
                  GeneratedFileScan.indent(of: lines[region.lowerBound]) + flat.count > GeneratedFileLayout.lineLimit,
                  let nodes = LayoutParser.nodes(flat) else { continue }
            let found = Self.hoistable(in: nodes, avoiding: local)
            guard !found.isEmpty else { continue }
            for generator in found where !generators.contains(generator) { generators.append(generator) }
            draws.append((region, flat))
        }
        guard !generators.isEmpty else { return lines }
        let names = Self.names(count: generators.count, avoiding: lines)
        let nameOf = Dictionary(uniqueKeysWithValues: zip(generators, names))
        var result = lines
        for draw in draws.reversed() {
            guard let nodes = LayoutParser.nodes(draw.flat) else { continue }
            let pad = String(repeating: " ", count: GeneratedFileScan.indent(of: lines[draw.region.lowerBound]))
            result.replaceSubrange(draw.region, with: [pad + Self.drawing(nodes, from: nameOf).flat])
        }
        let breaker = LayoutBreaker(limit: GeneratedFileLayout.lineLimit, indentWidth: GeneratedFileLayout.indentWidth)
        let declarations = zip(names, generators).flatMap { name, generator -> [String] in
            let declaration = "nonisolated private static let \(name) = \(generator)"
            return breaker.lines(for: LayoutParser.nodes(declaration) ?? [.text(declaration)], indent: 4) + [""]
        }
        let insertAt = suite + 1 < result.count && result[suite + 1].isEmpty ? suite + 2 : suite + 1
        result.insert(contentsOf: declarations, at: insertAt)
        return result
    }

    /// The innermost region around every line that draws, in file order and none inside another.
    static func drawingRegions(lines: [String], scan: GeneratedFileScan) -> [ClosedRange<Int>] {
        let regions = GeneratedFileRegions(lines: lines, scan: scan)
        var found: [ClosedRange<Int>] = []
        for (number, line) in lines.enumerated() where line.contains(".run(using: &") && !scan.lines[number].frozen {
            guard let region = regions.innermostRegion(holding: number), !found.contains(region) else { continue }
            found.append(region)
        }
        let separate = found.filter { region in
            !found.contains { $0 != region && $0.overlaps(region) && $0.count < region.count }
        }
        return separate.sorted { $0.lowerBound < $1.lowerBound }
    }

    /// The text of every `(G)` drawn from with `.run(using: &…)` in `nodes`, long enough to be worth a
    /// name and naming nothing in `local`.
    static func hoistable(in nodes: [LayoutNode], avoiding local: Set<String>) -> [String] {
        var found: [String] = []
        for (index, node) in nodes.enumerated() {
            guard case let .group(_, children, _) = node else { continue }
            if isDrawn(nodes, at: index) {
                let generator = children.trimmed.flat
                let movable = referencedNames(in: children).isDisjoint(with: local)
                if generator.count >= 40, movable { found.append(generator) }
            } else {
                found += hoistable(in: children, avoiding: local)
            }
        }
        return found
    }

    /// `nodes` with each hoisted `(G)` replaced by `Self.<name>`.
    static func drawing(_ nodes: [LayoutNode], from names: [String: String]) -> [LayoutNode] {
        nodes.enumerated().map { index, node in
            guard case let .group(open, children, close) = node else { return node }
            if isDrawn(nodes, at: index), let name = names[children.trimmed.flat] { return .text("Self.\(name)") }
            return .group(open: open, children: drawing(children, from: names), close: close)
        }
    }

    /// Whether the group at `index` is a parenthesised generator drawn from: `(G).run(using: &rng)`.
    static func isDrawn(_ nodes: [LayoutNode], at index: Int) -> Bool {
        guard case .group("(", _, _) = nodes[index], index + 2 < nodes.count,
              case .text(".run") = nodes[index + 1],
              case let .group("(", arguments, _) = nodes[index + 2] else { return false }
        return arguments.flat.hasPrefix("using: &")
    }

    /// The bare names `nodes` refer to: identifiers in code, not in a literal or a comment, and not
    /// an argument label (`value:`) or a member (`.value`), which name nothing in scope.
    static func referencedNames(in nodes: [LayoutNode]) -> Set<String> {
        var names = Set<String>()
        for node in nodes {
            switch node {
            case .text(let text):
                names.formUnion(bareIdentifiers(in: text))

            case let .group(_, children, _):
                names.formUnion(referencedNames(in: children))

            case .literal, .comment:
                continue
            }
        }
        return names
    }

    private static func bareIdentifiers(in text: String) -> [String] {
        let chars = Array(text)
        var names: [String] = []
        var start = 0
        while start < chars.count {
            guard chars[start].isLetter || chars[start] == "_" else {
                start += 1
                continue
            }
            var end = start
            while end < chars.count, chars[end].isLetter || chars[end].isNumber || chars[end] == "_" { end += 1 }
            // A member's `.`, not the last of a range's `...` — `0...bound` reads `bound`.
            let isMember = start > 0 && chars[start - 1] == "." && (start < 2 || chars[start - 2] != ".")
            let isLabel = end < chars.count && chars[end] == ":"
            if !isMember, !isLabel { names.append(String(chars[start ..< end])) }
            start = end
        }
        return names
    }

    /// Every name the file declares with `let` or `var`, and the closure parameters the emitters
    /// bind — what a generator moved out of its test could no longer see.
    static func declaredNames(in lines: [String]) -> Set<String> {
        var names: Set<String> = ["rng", "value", "args", "pair", "triple", "input", "error", "drawn"]
        for line in lines {
            let words = line.split { !($0.isLetter || $0.isNumber || $0 == "_") }
            for (offset, word) in words.dropLast().enumerated() where word == "let" || word == "var" {
                names.insert(String(words[offset + 1]))
            }
        }
        return names
    }

    /// `generator`, or `generator1`, `generator2`, … — or the same under `drawnGenerator` when the
    /// file already declares a name starting with the first. Only a declaration can clash: every
    /// use is spelled `Self.<name>`.
    static func names(count: Int, avoiding lines: [String]) -> [String] {
        var declared = Set<String>()
        for line in lines {
            let words = line.split { !($0.isLetter || $0.isNumber || $0 == "_") }
            for (offset, word) in words.dropLast().enumerated() where ["let", "var", "func"].contains(word) {
                declared.insert(String(words[offset + 1]))
            }
        }
        let base = ["generator", "drawnGenerator", "hoistedGenerator"].first { candidate in
            !declared.contains { $0.hasPrefix(candidate) }
        } ?? "hoistedGenerator"
        return count == 1 ? [base] : (1 ... count).map { "\(base)\($0)" }
    }
}
