import Foundation

/// What happens when the corpus under survey **is** one of the verifier's own
/// dependencies.
///
/// The synthesized manifest declares swift-numerics, swift-collections,
/// swift-property-based, SwiftPropertyLaws (and swift-syntax / TCA / Mobius on
/// the arms that need them) by URL, then appends the corpus by path. SwiftPM
/// derives package *identity* from the last path component either side — URL
/// basename minus `.git`, directory basename — so if the corpus is any of those
/// packages, one identity arrives from two sources and SwiftPM rejects the whole
/// graph:
///
///     error: Conflicting identity for swift-collections:
///            dependency 'github.com/apple/swift-collections' and
///            dependency '/…/swift-collections' both point to the same
///            package identity 'swift-collections'.
///
/// Measured (#169): **0 of 98** entries executed on swift-collections and
/// **0 of 39** on SwiftPropertyLaws — every row that needed a build recorded
/// `measured-error: build-failed`, which reads as a carrier-reach problem and is
/// nothing of the kind. `swift-collections` and `swift-numerics` are the two
/// canonical algebraic corpora, so this closed off most of the population the
/// tool exists to check.
///
/// **The corpus wins.** It vends the same products under the same identity — the
/// `ignoring duplicate product` warning SwiftPM emits alongside the error is
/// saying exactly that — so dropping the URL line loses nothing and the
/// `.product(name:package:)` edges keep resolving unchanged, because the
/// surviving dependency answers to the identity they already name. That is not a
/// coincidence: the collision *is* the identities being equal.
///
/// The consequence is deliberate and worth stating: a survey of swift-collections
/// now tests the checkout in front of you rather than the pinned release. For a
/// survey that is the right answer — but it means a corpus older than the pin can
/// fail to compile the emitted stub, and *that* build failure is honest (the law
/// could not be checked against that version) where this one never involved the
/// property at all.
extension VerifierWorkdir {

    /// The SwiftPM identity of a `.package(url:)` line, or `nil` if the line is
    /// not a URL dependency (a comment, or the `.package(path:)` entry).
    ///
    /// Parses a string this type just rendered, which is normally a smell. It is
    /// contained here because the alternative — threading an identity alongside
    /// every entry through five mode arms — restates the URL in two places, and
    /// two spellings of a package's name is the class of bug this whole file is
    /// about. The parse is made safe by its **failure direction plus a guard**:
    /// an unreadable line is kept, so a shape this misses re-opens the collision
    /// rather than dropping a needed dependency, and
    /// `VerifierWorkdirCorpusIdentityTests.everyURLDependencyIsReadable` asserts
    /// every line of every arm parses, so "this misses a shape" fails the suite.
    static func urlDependencyIdentity(in line: String) -> String? {
        guard let marker = line.range(of: "url: \"") else { return nil }
        let afterMarker = line[marker.upperBound...]
        guard let closing = afterMarker.firstIndex(of: "\"") else { return nil }
        var identity = afterMarker[..<closing]
            .split(separator: "/")
            .last
            .map(String.init) ?? ""
        if identity.hasSuffix(".git") { identity.removeLast(4) }
        return identity.isEmpty ? nil : identity
    }

    /// Drop every URL dependency whose identity collides with the corpus's.
    ///
    /// Case-insensitive, as SwiftPM's own comparison is — the measured error
    /// lowercases both sides, and a corpus checked out as `SwiftPropertyLaws`
    /// collides with a URL ending `SwiftPropertyLaws.git` regardless of casing.
    static func collapsingCorpusIdentity(
        _ entries: [String],
        corpus: UserPackageReference?
    ) -> [String] {
        guard let corpus else { return entries }
        let corpusIdentity = corpus.packageIdentity.lowercased()
        return entries.filter { line in
            guard let identity = urlDependencyIdentity(in: line) else { return true }
            return identity.lowercased() != corpusIdentity
        }
    }

    /// Identities this mode would declare by URL but will take from the corpus
    /// instead. Empty in the normal case.
    ///
    /// Exposed so a caller can *say* the substitution happened. A survey whose
    /// kit or stdlib dependency silently became "whatever is checked out next
    /// door" is exactly the kind of unstated resolution this project reports
    /// rather than assumes.
    static func supersededDependencyIdentities(
        userPackage: UserPackageReference?,
        mode: WorkdirMode
    ) -> [String] {
        guard let userPackage else { return [] }
        let all = renderDependenciesBlock(userPackage: nil, mode: mode)
            .components(separatedBy: "\n")
            .compactMap { urlDependencyIdentity(in: $0) }
        let corpusIdentity = userPackage.packageIdentity.lowercased()
        return all.filter { $0.lowercased() == corpusIdentity }
    }
}
