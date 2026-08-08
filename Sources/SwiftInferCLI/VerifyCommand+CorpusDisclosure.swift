import Foundation

/// Say when the corpus has replaced one of the verifier's own dependencies.
///
/// #172 made a corpus that shares an identity with a pinned dependency win the
/// resolution, which is right — a survey should check the code in front of you.
/// #174 is that it happened silently: `verify --all-from-index` on swift-collections
/// resolves every law against a local checkout at whatever commit, while the
/// manifest's `from: "1.0.0"` has been dropped, and the verdict records
/// `swiftInferVersion` and nothing about the corpus.
///
/// **The precedent is a guardrail, not a nicety.** CLAUDE.md requires a partial
/// exploration to disclose its excluded set — *"verified over M of N action types
/// (excluded: …)"* — in `detail` and in the render. Same shape: a verdict
/// established over a different subject than the reader assumes, and the remedy is
/// to name the difference.
///
/// **Run-level, not per-entry.** The substitution is a property of the resolved
/// dependency graph, so repeating it across 98 rows would be noise, and per-entry
/// text is the wrong place for something a reader needs *before* the verdicts. It
/// is emitted on stderr ahead of the stream, the same posture
/// `KitEvidenceScoring`'s demotion warning takes for a diagnosis that would
/// otherwise be hidden below the cut.
extension SwiftInferCommand.Verify {

    /// Emit one warning per distinct `(corpus, mode)` that supersedes a pinned
    /// dependency. No output in the normal case, where nothing collides.
    ///
    /// `write` is injected so a test can assert the text rather than scrape
    /// stderr; the default is the same `warning:` channel the rest of the survey
    /// uses. Not gated on `quiet` — that suppresses the JSON record *stream* for
    /// callers rendering their own summary, and a resolution the reader cannot see
    /// is precisely what should survive a quieter mode.
    static func discloseSupersededDependencies(
        for members: [SharedVerifierPackage.Member],
        write: (String) -> Void = { message in
            FileHandle.standardError.write(Data("warning: \(message)\n".utf8))
        }
    ) {
        var announced: Set<String> = []
        for member in members {
            guard let corpus = member.userPackage else { continue }
            let superseded = VerifierWorkdir.supersededDependencyIdentities(
                userPackage: corpus, mode: member.mode
            )
            guard !superseded.isEmpty else { continue }
            // One line per (corpus, mode): the superseded set is mode-dependent,
            // and a survey can hold more than one mode.
            guard announced.insert("\(corpus.packagePath.path)|\(member.mode.rawValue)").inserted
            else { continue }
            write(disclosure(superseded: superseded, corpus: corpus))
        }
    }

    static func disclosure(
        superseded: [String],
        corpus: VerifierWorkdir.UserPackageReference
    ) -> String {
        let names = superseded.sorted().joined(separator: ", ")
        let subject = superseded.count == 1 ? "is a dependency" : "are dependencies"
        return "\(names) \(subject) of the generated verifier AND the corpus under "
            + "survey, so the pinned release was dropped and the corpus won. Every law "
            + "here is checked against \(CorpusProvenance.describe(corpus.packagePath)). "
            + "A measured verdict is a statement about that checkout, not about the "
            + "pinned version — and two runs taken at different checkouts are not "
            + "comparable."
    }
}
