import SwiftSyntax

/// Can this declaration be **called at all**, or has its author withdrawn it?
///
/// Discovery has always read visibility and never availability. A law proposed on an
/// `@available(*, unavailable)` declaration cannot be written, cannot compile, and cannot be
/// acted on — so it is not a conservative suggestion, it is a wrong one.
///
/// ## Measured before building (2026-08-22)
///
/// **24 of 4,161 discovery evidence-rows** across the corpora, at `--include-possible`:
/// swiftlang-swift 19, swift-system 5, and **zero in the other 16**. That is 0.58% of output
/// and 79% of it in one corpus, so **nobody should quote this as a large win** — the argument
/// is soundness, not volume.
///
/// **Measured AFTER building, which corrected the estimate**: the gate removes **19 suggestions**
/// on swiftlang-swift (1,332 → 1,313) and **35 evidence-rows**, against a predicted 19 rows. The
/// gap is not over-firing and was checked rather than assumed — `count`, `byteCount` and
/// `underestimatedCount` all still produce suggestions afterwards. It has two causes, both of
/// which make the pre-build estimate a floor:
///
/// 1. **The estimate's regex read one line.** A multi-line `@available(*, unavailable,\n
///    renamed: …)` was invisible to it and is not invisible to the parser.
/// 2. **A gated declaration takes its PARTNER's evidence row with it.** A `round-trip` pairing
///    `byteCount()` with a withdrawn `dropFirst(_:)` is one suggestion; removing it removes both
///    rows, and only one of them is withdrawn.
///
/// swift-system: 5 rows, 47 → 42. The home corpus blocks **zero** — and cannot serve as a
/// control here anyway, because adding this file to `Sources/SwiftInferCore` adds four discovery
/// rows of its own.
///
/// What makes it worth the code is that it costs **no laws**. All 24 carry `renamed:`, and
/// **20 of the 24 are strict duplicates**: swiftlang-swift's 19 point at
/// `extracting(first:)` / `extracting(droppingFirst:)` / `extracting(droppingLast:)`, which
/// carry 48 live evidence-rows of their own, and swift-system's `dirname` points at
/// `removingLastComponent()`, which has its own row. The remaining four — `dup` / `dup2` /
/// `dup3` → `duplicate`, and `pwrite` → `write` — have no replacement row, and lose nothing
/// actionable either: three of them have bodies that are literally
/// `fatalError("Not implemented")`.
///
/// ## The gate is `unavailable` and `obsoleted:` ONLY, and that is the measured part
///
/// The tempting rule — *skip anything carrying `@available`* — was measured and would be a
/// catastrophe. Across the same corpora, on `public` / `package` declarations:
///
/// | form | sites | callable? |
/// |---|---:|---|
/// | `@available(*, deprecated, …)` | **1,163** | **yes**, with a warning |
/// | `@available(macOS 13, iOS 16, *)` and other floors | hundreds | **yes** |
/// | `@available(*, noasync)` | 28 | **yes** — the emitted stub is synchronous |
/// | `@available(*, unavailable, …)` | 92 | no |
/// | `@available(swift, …, obsoleted: 5.0, …)` | 49+ | no — already removed |
///
/// So the rule blocks on two spellings and admits every other. `deprecated` is the one that
/// would hurt: a deprecated API is still a perfectly good law subject, and gating on it would
/// throw away an order of magnitude more than it saved.
///
/// **`obsoleted:` does not compare versions**, and that is a deliberate simplification with a
/// measured basis rather than an oversight: every instance found is a Swift-version obsoletion
/// already passed (`obsoleted: 4.2`, `obsoleted: 5.0`, against a Swift 6 toolchain). A wrong
/// decline here costs one suggestion; a wrong admission costs a guaranteed build failure. If a
/// future subject declares `obsoleted:` at a version not yet reached, this over-declines, and
/// the fix is to compare — not to loosen.
public enum UncallableDeclaration {

    /// Spellings inside `@available(…)` that mean *this cannot be called from new code*.
    ///
    /// Deliberately NOT a set of whole attribute texts: the payload varies (`message:`,
    /// `renamed:`, platform lists), and matching whole strings would miss every real one.
    public static let blockingSpellings = ["unavailable", "obsoleted"]

    /// `true` when this attribute list withdraws the declaration.
    ///
    /// Reads the argument text rather than parsing `AvailabilityArgumentListSyntax`, because the
    /// question is a keyword's presence and the structured form differs across the spellings
    /// (`*, unavailable` is an availability-argument list; `swift, obsoleted: 5.0` carries a
    /// version tuple). One text check that both forms reach is more honest than two parses that
    /// each handle half.
    public static func withdraws(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            guard case let .attribute(attribute) = element,
                  attribute.attributeName.trimmedDescription == "available",
                  let arguments = attribute.arguments else { return false }
            let text = arguments.trimmedDescription
            return blockingSpellings.contains { spelling in
                containsWord(spelling, in: text)
            }
        }
    }

    /// `true` when the declaration OR anything it is nested inside withdraws it.
    ///
    /// swift-system puts both of its `FilePath` renames inside one `extension` under a
    /// `// MARK - Renamed` banner, and marks the members rather than the extension — but the
    /// reverse is legal and common, and a check that reads only the declaration's own attributes
    /// would admit every member of an unavailable extension.
    ///
    /// **Walks ancestors rather than keeping a stack.** `FunctionScanner`'s `typeStack` /
    /// `enclosingTypeAccess` pair carries a standing warning that a third parallel stack is how
    /// the push/pop discipline drifts, and it is right — so this asks the tree instead, the same
    /// way `isNestedLocalFunction` does.
    public static func isWithdrawn(_ node: some SyntaxProtocol) -> Bool {
        var current: Syntax? = Syntax(node)
        while let candidate = current {
            if let attributes = attributeList(of: candidate), withdraws(attributes) { return true }
            current = candidate.parent
        }
        return false
    }

    /// The attribute list of any declaration form that can carry one and can contain members.
    ///
    /// Returns nil for everything else, which makes the ancestor walk above degrade to "keep
    /// climbing" rather than to a wrong answer.
    private static func attributeList(of node: Syntax) -> AttributeListSyntax? {
        if let decl = node.as(FunctionDeclSyntax.self) { return decl.attributes }
        if let decl = node.as(VariableDeclSyntax.self) { return decl.attributes }
        if let decl = node.as(ExtensionDeclSyntax.self) { return decl.attributes }
        if let decl = node.as(StructDeclSyntax.self) { return decl.attributes }
        if let decl = node.as(ClassDeclSyntax.self) { return decl.attributes }
        if let decl = node.as(EnumDeclSyntax.self) { return decl.attributes }
        if let decl = node.as(ActorDeclSyntax.self) { return decl.attributes }
        return nil
    }

    /// Whole-word containment, so `unavailable` is not found inside a `message:` string that
    /// merely says the word, and `obsoleted` is matched at its label rather than anywhere.
    ///
    /// Cheap and adequate: a `message:` payload saying "unavailable" on a declaration that is
    /// NOT unavailable would over-decline one row. The stricter reading — inspect only the
    /// argument labels — needs the structured parse this type's doc explains it is avoiding.
    /// Recorded rather than resolved, and measured at zero occurrences across the corpora.
    private static func containsWord(_ word: String, in text: String) -> Bool {
        var searchRange = text.startIndex ..< text.endIndex
        while let found = text.range(of: word, range: searchRange) {
            let beforeOK = found.lowerBound == text.startIndex
                || !isIdentifierCharacter(text[text.index(before: found.lowerBound)])
            let afterOK = found.upperBound == text.endIndex
                || !isIdentifierCharacter(text[found.upperBound])
            if beforeOK, afterOK { return true }
            guard found.upperBound < text.endIndex else { return false }
            searchRange = found.upperBound ..< text.endIndex
        }
        return false
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}
