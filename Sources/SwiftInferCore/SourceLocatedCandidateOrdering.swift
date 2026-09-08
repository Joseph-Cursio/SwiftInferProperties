/// Ordering over candidates identified by a `SourceLocation` and a type name.
///
/// `DefensiveCopyDiscoverer`, `StableIdentityDiscoverer` and
/// `ValueSemanticDiscoverer` each ended with the same three-key comparator
/// written out in full:
///
/// ```swift
/// (lhs.location.file, lhs.location.line, lhs.typeName)
///     < (rhs.location.file, rhs.location.line, rhs.typeName)
/// ```
///
/// **All three stopped at `line`.** That is the same shape as the six
/// comparators an earlier pass replaced with `SourceLocation: Comparable`,
/// which orders `(file, line, column)` — these three predate it in spirit and
/// re-derive two thirds of it by hand. Going through the conformance restores
/// `column` to the ordering, so two candidates declared on one line are
/// separated by position rather than by name.
///
/// This is deliberately *not* unified with the identically-named comparators in
/// `RuleVisitorDiscoverer`, `ConventionRoleDiscoverer` and
/// `ViewModelDiscoverer`. Those types spell `location` as a `String` built as
/// `"\(file):\(line)"`, and a protocol spanning both families would hide that
/// difference behind one name — see the note in this commit's message.
protocol SourceLocatedCandidate {
    var typeName: String { get }
    var location: SourceLocation { get }
}

extension DefensiveCopyCandidate: SourceLocatedCandidate {}
extension StableIdentityCandidate: SourceLocatedCandidate {}
extension ValueSemanticCandidate: SourceLocatedCandidate {}

enum SourceLocatedCandidateOrdering {

    /// Source position ascending, type name ascending as the tiebreak.
    ///
    /// The tiebreak is what makes this a strict weak ordering worth naming: two
    /// candidates sharing a location — a type and its extension discovered at
    /// one position — would otherwise be incomparable, and `sorted(by:)` is not
    /// promised to be stable.
    static func byLocationThenTypeName<Candidate: SourceLocatedCandidate>(
        _ lhs: Candidate, _ rhs: Candidate
    ) -> Bool {
        (lhs.location, lhs.typeName) < (rhs.location, rhs.typeName)
    }
}
