/// **Roles whose postcondition the CATALOGUE supplies, rather than discovering.**
///
/// A normaliser's defining law is a postcondition — the output satisfies the predicate
/// the function exists to establish. `fixtures/branch-reaching-generator/` §4 measured
/// that on a legalise-shaped subject the postcondition kills **4 of 4** real bugs while
/// **idempotence — the law the tool emitted — kills 1 of 4**.
///
/// ## Why the predicate is supplied and not found
///
/// `docs/measurements/postcondition-law-declined.md` measured two routes that try to
/// **discover** the predicate in the subject's code, and declined both: pairing it to a
/// same-type `(T) -> Bool` by name found ~5 genuine of 349, and reading it out of a body
/// guard found ~13 of 25 with **9 of the 13 in a single stdlib file**.
///
/// The route that works was already shipping. **`MeasureTemplate` does not discover
/// `>= 0`** — it recognises the role `count` / `size` / `magnitude` and the catalogue
/// supplies the law, at **401 rows across the 17 corpora**. This is that pattern widened:
/// Measured at the **17** corpora resolving then; `CorpusManifest`
/// resolves **20** since 2026-08-23 and this has NOT been re-taken —
/// see `docs/measurements/census-universe-17-to-20.md`.
///
/// > role recognised by name → predicate supplied here → asserted of the output
///
/// It sidesteps every failure of the discovery routes. No pairing, no guard reading, and
/// **no control-versus-postcondition ambiguity** — `shouldFormatterIgnore(node)` is
/// structurally identical to a validity guard and means something else entirely, which is
/// what capped route B's precision at ~52%. Here the template writes the check.
///
/// ## The two exclusions are measured, not cautious
///
/// **`normalized` is deliberately absent.** Its law would be *"the result is in normal
/// form"*, which is **not a checkable predicate** — there is no universal test for
/// "normal". Both sites found on the corpora confirm it: `SubjectFingerprint.normalized`
/// establishes a fingerprint convention, and `ParallelEnumShapeVisitor.normalized` returns
/// a `(Set<String>, [String: String])` tuple. A role that reads like a law and supplies
/// none is worse than an absent role, because it looks like coverage.
///
/// **A parameterised match is not the role** — see ``matches(name:parameterLabels:)``.
/// `SyntaxProtocol.trimmed(matching filter:)` is an exact name match that trims *trivia
/// selected by a filter*, not whitespace. Supplying *"no leading or trailing whitespace"*
/// there would be a **false law refuting correct code**, which is the worst failure this
/// tool has. It was the only false positive in a hand-check of all 38 declarations.
public enum RolePostcondition: String, Sendable, Equatable, Hashable, CaseIterable {

    case sorted
    case clamped
    case rounded
    case lowercased
    case uppercased
    case deduplicated
    case escaped
    case unescaped
    /// Weak but true: reversal preserves count. Kept because it is refutable — a
    /// `reversed` that drops an element fails it — and marked in ``isStrong``.
    case reversed
    /// Weak but true: a shuffle is a permutation of its input.
    case shuffled

    /// The law, in the words a reader of the suggestion sees.
    public var law: String {
        switch self {
        case .sorted: "the result is in non-decreasing order"
        case .clamped: "the result lies within the given bounds"
        case .rounded: "the result is integral"
        case .lowercased: "the result contains no uppercase character"
        case .uppercased: "the result contains no lowercase character"
        case .deduplicated: "the result contains no duplicate element"
        case .escaped: "the result contains no unescaped occurrence"
        case .unescaped: "the result contains no escape sequence"
        case .reversed: "the result has the same element count as the input"
        case .shuffled: "the result is a permutation of the input"
        }
    }

    /// Whether the law constrains the output beyond its size.
    ///
    /// ``reversed`` and ``shuffled`` are true and weak: they pin cardinality and
    /// membership without pinning *content*, so a wrong-but-same-size result satisfies
    /// them. Recorded rather than dropped — the distinction belongs to the reader, and
    /// a suggestion that hides it is over-claiming.
    public var isStrong: Bool { self != .reversed && self != .shuffled }

    /// The parameter labels this role permits.
    ///
    /// **`nil` means "no parameters".** A role names an operation, and a parameter can
    /// change which operation it is: `trimmed()` trims whitespace, `trimmed(matching:)`
    /// trims trivia a caller selects. Only labels that leave the role's meaning intact
    /// are admitted — a comparator for `sorted`, bounds for `clamped`, a rule for
    /// `rounded`.
    public var permittedLabels: Set<String?> {
        switch self {
        case .sorted: [nil, "by", "using"]
        case .clamped: ["to", "lowerBound", "upperBound"]
        case .rounded: [nil]
        case .escaped: [nil, "asASCII"]
        case .shuffled: [nil, "using"]
        default: [nil]
        }
    }

    /// **The law as a Swift expression that is TRUE when the law is VIOLATED**, given a
    /// binding named `result`.
    ///
    /// `nil` means the role is **suggested but not executable** — which is the honest
    /// state for most of them, and the reason this is an `Optional` rather than a
    /// `fatalError` branch:
    ///
    /// - **`sorted` was attempted and declined, and the reason is not the one expected.**
    ///   `SemanticIndexEntry` carries no return type, so the element type — and whether it
    ///   is `Comparable` — is unknowable at emit time. But adding that field would not
    ///   help: walking the 8 exact sites across the 17 corpora, **not one would take a
    ///   natural-order check that is both compilable and true.** Two are
    ///   `sorted(using comparator:)` and one is `sorted(by:)`, where the ordering is the
    ///   **caller's** and natural order is a *false law*; `Leaderboard.sorted()` sorts by
    ///   score, whose natural order is a different key; `Sequence.sorted()` is generic;
    ///   and `BitSet.sorted()` returns `self`. **The blocker is the missing comparator,
    ///   not the missing schema field.**
    ///
    ///   This also exposes a seam in ``permittedLabels``: `by` and `using` are admitted
    ///   because they *preserve the role* — `sorted(by:)` is still sorting — which is
    ///   right for SUGGESTING the law and wrong for EXECUTING it. A future executable
    ///   `sorted` needs `isNullary` on top of the role gate.
    ///
    /// - **`deduplicated`** needs `Element: Hashable`, unknowable for the same reason.
    ///   Emitting a check that does not compile is the failure
    ///   `criterion-a-unmet-subject.md` measured at **89% of output on an unmet subject**.
    /// - **`clamped`** needs the bounds the caller passed, which the stub does not hold.
    /// - **`escaped` / `unescaped`** are escaping-scheme specific; there is no universal
    ///   check, only the subject's own.
    /// - **`rounded`** needs the `FloatingPointRoundingRule`, and `rounded(.up)` of an
    ///   already-integral value is integral for a different reason than `.towardZero`.
    /// - **`reversed` / `shuffled`** need the input alongside the result, which this
    ///   single-value shape does not carry.
    ///
    /// What is left executes unconditionally: `lowercased()` and `uppercased()` return
    /// `String` in every Swift spelling, so the check needs no conformance the tool must
    /// prove and no argument it does not have.
    public var violationExpression: String? {
        switch self {
        case .lowercased: "result.contains(where: { $0.isUppercase })"
        case .uppercased: "result.contains(where: { $0.isLowercase })"
        default: nil
        }
    }

    /// Whether the law can be executed as well as suggested.
    public var isExecutable: Bool { violationExpression != nil }

    /// **Does this declaration carry the role, unmodified?**
    ///
    /// Requires an exact name — a prefix match is a different operation whose suffix
    /// narrows the law. Measured: `trimmingLeadingWhitespace` leads with `trimming` and
    /// does **not** guarantee the trailing half, and `trimmingSuperfluousNewlines` does
    /// not touch whitespace at all. **14 of the 16 trim-family sites across the 17 corpora
    /// were prefix matches**, so this single rule moved the usable population from 62 to
    /// 36 — and every row it removed would have carried a false or over-strong law.
    public static func matches(name: String, parameterLabels: [String?]) -> Self? {
        guard let role = Self(rawValue: name) else { return nil }
        let permitted = role.permittedLabels
        // Zero parameters is spelled `[nil]` in `permittedLabels`; an empty list matches
        // it, which is the common `sorted()` / `lowercased()` shape.
        guard parameterLabels.isEmpty || parameterLabels.allSatisfy({ permitted.contains($0) })
        else { return nil }
        return role
    }
}
