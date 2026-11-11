/// How a uniquifier decorates a name it has already issued, read off its body (#692, condition 3).
///
/// The law fails only where one drawn name equals another plus this decoration, so the stub's
/// alphabet is spelled from it: a generator drawing realistic names never collides.
public enum UniquifierDecoration: Sendable, Equatable {
    /// A counter interpolated after `prefix`: `"\(name)\(index)"` is `prefix: ""`,
    /// `"\(base)_\(n)"` is `prefix: "_"`.
    case counter(prefix: String)
    /// Text a re-test loop appends until the candidate is free: `name = name + "_"` is `_`.
    case appended(String)
}

/// What `UniquifierShapeReader` read off a body that hands out names and remembers them: #669's
/// criteria 2 and 3, as the census froze them (`docs/plans/uniquifier-law-census-scope.md` §1.2).
///
/// Present only when TEST ∧ (TIED ∨ RETEST) ∧ WRITE hold. Criterion 1, state kept across calls and a
/// returned name, is read off the summary by the template, because the owner's kind is not known
/// while one function is scanned.
public struct UniquifierShape: Sendable, Equatable {
    /// The stored collections the body tests a candidate against, `self.` removed: `uniqElementNames`.
    public let testedBases: [String]
    /// How a repeated name is decorated.
    public let decoration: UniquifierDecoration
    /// What a leading `guard … else { return "…" }` returns for every input it rejects, or `nil`.
    /// Two rejected inputs share it by design, so the law excludes it.
    public let sentinel: String?
    /// The body returns a stored id early for a key it has seen (`if let id = byKey[key] { return id }`).
    /// Such a function owes the memoizing law: equal keys give equal ids, distinct keys distinct ids.
    public let isMemoizing: Bool
    /// The line each criterion was read from, for "why suggested".
    public let testLine: Int
    /// The line of the decoration the gate tied to that test, or of the re-test loop.
    public let decorationLine: Int
    /// The line of the write back to the tested state.
    public let writeLine: Int

    /// Creates a shape.
    public init(
        testedBases: [String],
        decoration: UniquifierDecoration,
        sentinel: String?,
        isMemoizing: Bool,
        testLine: Int,
        decorationLine: Int,
        writeLine: Int
    ) {
        self.testedBases = testedBases
        self.decoration = decoration
        self.sentinel = sentinel
        self.isMemoizing = isMemoizing
        self.testLine = testLine
        self.decorationLine = decorationLine
        self.writeLine = writeLine
    }
}
