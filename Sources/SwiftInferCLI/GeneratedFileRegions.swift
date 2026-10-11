/// Which lines of a generated file `GeneratedFileLayout` re-lays out, and the one line each
/// becomes before it is broken again.
///
/// A **region** starts at a line that begins a statement or an argument and runs until every
/// bracket opened in it has closed — so it is self-contained, and replacing it cannot unbalance
/// what is around it. A **defect** is a line over the limit, a line that continues a chain
/// (`.map { … }` at its head — the kit's continuation style, which leaves the closing brace in
/// the middle of a line), or a bracket closed out of line with where it opened. Each defect is
/// fixed by re-laying out the innermost region holding it; a region holding another chosen one
/// replaces it.
struct GeneratedFileRegions {

    let lines: [String]
    let scan: GeneratedFileScan

    /// The regions to re-lay out, in file order, none inside another.
    var defective: [ClosedRange<Int>] {
        var chosen: [ClosedRange<Int>] = []
        for line in defectLines() {
            guard let region = innermostRegion(holding: line) else { continue }
            chosen.append(region)
        }
        let outermost = chosen.filter { region in
            !chosen.contains { $0 != region && $0.contains(region.lowerBound) && $0.contains(region.upperBound) }
        }
        return Array(Set(outermost)).sorted { $0.lowerBound < $1.lowerBound }
    }

    func defectLines() -> [Int] {
        var defects = Set<Int>()
        for (number, line) in lines.enumerated() where !scan.lines[number].frozen && !scan.lines[number].commentOnly {
            if line.count > GeneratedFileLayout.lineLimit || Self.continuesChain(line) { defects.insert(number) }
        }
        for group in scan.groups where group.closeLine > group.openLine {
            let closeIndent = GeneratedFileScan.indent(of: lines[group.closeLine])
            let aligned = group.closeLeads && closeIndent == GeneratedFileScan.indent(of: lines[group.openLine])
            if !aligned { defects.insert(group.closeLine) }
        }
        return defects.sorted()
    }

    func innermostRegion(holding line: Int) -> ClosedRange<Int>? {
        for start in stride(from: line, through: 0, by: -1) {
            guard let end = regionEnd(from: start) else { continue }
            if end >= line { return start ... end }
        }
        return nil
    }

    /// Where the region starting at `start` ends, or `nil` when `start` cannot begin one: it is
    /// not code, it continues something above it, or the run it starts closes a bracket opened
    /// above it.
    func regionEnd(from start: Int) -> Int? {
        guard Self.beginsStatement(lines[start]), isPlainCode(start) else { return nil }
        var end = start
        var grew = true
        while grew {
            grew = false
            for group in scan.groups where (start ... end).contains(group.openLine) && group.closeLine > end {
                end = group.closeLine
                grew = true
            }
        }
        let closesForeign = scan.groups.contains { $0.openLine < start && (start ... end).contains($0.closeLine) }
        guard !closesForeign, (start ... end).allSatisfy(isPlainCode) else { return nil }
        return end
    }

    private func isPlainCode(_ line: Int) -> Bool {
        let facts = scan.lines[line]
        return !facts.frozen && !facts.commentOnly && !facts.trailingComment
            && !lines[line].allSatisfy { $0 == " " }
    }

    static func continuesChain(_ line: String) -> Bool {
        let trimmed = line.drop { $0 == " " }
        guard trimmed.first == ".", let next = trimmed.dropFirst().first else { return false }
        return next.isLetter || next == "_"
    }

    static func beginsStatement(_ line: String) -> Bool {
        let trimmed = line.drop { $0 == " " }
        guard let first = trimmed.first else { return false }
        if ")]}.".contains(first) { return false }
        return !startsWithBinaryOperator(String(trimmed))
    }

    /// `== rhs`, `&& rest`, `?? fallback` — an operator followed by a space continues the line
    /// above it.
    static func startsWithBinaryOperator(_ text: String) -> Bool {
        let operatorChars = text.prefix { "=!<>&|+-*/%?:^~".contains($0) }
        guard !operatorChars.isEmpty else { return false }
        return text.dropFirst(operatorChars.count).first == " "
    }

    static func endsWithBinaryOperator(_ text: String) -> Bool {
        let operatorChars = text.reversed().prefix { "=!<>&|+-*/%?:^~".contains($0) }
        guard !operatorChars.isEmpty else { return text.hasSuffix(",") }
        return text.dropLast(operatorChars.count).last == " "
    }

    // MARK: - Flattening

    /// `region` as one line: each line break replaced by what the code needs there — nothing at
    /// a chain's `.` or next to a bracket, `; ` between two statements in a body, a space
    /// otherwise. `nil` when a line holds a string literal or comment the join cannot see past.
    static func flattened(_ region: [String]) -> String? {
        var flat = ""
        var open: [Character] = []
        for (offset, raw) in region.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if offset > 0 { flat += separator(after: flat, before: line, innermost: open.last) }
            flat += line
            guard track(line, into: &open) else { return nil }
        }
        return flat
    }

    private static func separator(after flat: String, before line: String, innermost: Character?) -> String {
        guard let last = flat.last, let first = line.first else { return "" }
        if first == "." || first == ")" || first == "]" || last == "(" || last == "[" { return "" }
        if first == "}" || last == "{" { return " " }
        guard innermost == "{" else { return " " }
        let continues = flat.hasSuffix(" in") || endsWithBinaryOperator(flat) || startsWithBinaryOperator(line)
        return continues ? " " : "; "
    }

    /// Push and pop `line`'s brackets onto `open`, skipping string literals.
    private static func track(_ line: String, into open: inout [Character]) -> Bool {
        let chars = Array(line)
        var cursor = 0
        while cursor < chars.count {
            switch chars[cursor] {
            case "\"":
                guard let end = LayoutParser.literalEnd(in: chars, from: cursor) else { return false }
                cursor = end
                continue

            case "(", "[", "{":
                open.append(chars[cursor])

            case ")", "]", "}":
                open.removeLast()

            default:
                break
            }
            cursor += 1
        }
        return true
    }
}

extension GeneratedFileScan.Group: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.openLine == rhs.openLine && lhs.openColumn == rhs.openColumn
    }
}
