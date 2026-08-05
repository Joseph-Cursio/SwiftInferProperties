import Testing

@testable import SwiftInferCore

/// Build identity, and the one property that matters: **it must never invent
/// provenance.**
///
/// A version string that cannot distinguish two builds is not an identity — but a
/// version string that *claims* a commit it cannot know is worse, because it looks
/// like provenance and is not. Every assertion here is about the refusal.
@Suite("BuildIdentity")
struct BuildIdentityTests {

    /// The committed default. A plain `swift build` cannot know its own commit —
    /// the tree may be dirty, detached, or not a git repository — so the checked-in
    /// constant must say so.
    ///
    /// **This test failing usually means a stamped build was interrupted** and left
    /// the constant rewritten in the working tree. `git checkout` the file.
    @Test("the checked-in constant refuses to claim a commit")
    func defaultIsUnattributable() {
        #expect(BuildIdentity.commit == "unattributable")
        #expect(BuildIdentity.isAttributable == false)
    }

    /// The unstamped rendering says *build*, not a bare word. A reader seeing only
    /// "unattributable" cannot tell whether the tool failed to find something or is
    /// telling them this binary has no provenance.
    @Test("an unstamped version string says what is unattributable")
    func unstampedVersionNamesTheSubject() {
        let rendered = BuildIdentity.versionString("9.9.9")
        #expect(rendered == "9.9.9 (unattributable build)")
        #expect(rendered.contains("9.9.9"))
    }

    /// The version number survives either way — the identity is additive, not a
    /// replacement, so existing consumers that match on `1.148.0` keep working.
    @Test("the version number is present in both forms")
    func versionSurvivesBothForms() {
        #expect(BuildIdentity.versionString("1.2.3").hasPrefix("1.2.3 ("))
    }
}
