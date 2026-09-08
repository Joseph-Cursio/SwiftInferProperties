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
/// `RuleVisitorCandidate`, `StatefulRole` and `ViewModelCandidate` join them
/// here. Those three used to spell `location` as a `String` built as
/// `"\(file):\(line)"` and therefore sorted *lexicographically* — line 10 before
/// line 2 — so unifying them would once have put one name over two different
/// orderings. They carry a `SourceLocation` now, which is what makes the six a
/// single comparator rather than a resemblance.
protocol SourceLocatedCandidate {
    var typeName: String { get }
    var location: SourceLocation { get }
}

extension DefensiveCopyCandidate: SourceLocatedCandidate {}
extension RuleVisitorCandidate: SourceLocatedCandidate {}
extension StatefulRole: SourceLocatedCandidate {}
extension ViewModelCandidate: SourceLocatedCandidate {}
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
