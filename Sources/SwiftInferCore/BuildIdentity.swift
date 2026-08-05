/// Where this binary came from, when that can be known.
///
/// ## The problem
///
/// `swift-infer --version` reported `1.148.0` whether the binary was built this
/// morning or months ago from another commit. A version string that cannot
/// distinguish two builds is not an identity, and everything downstream that
/// wants attribution has to work around it. `scripts/toolchain.sh` does exactly
/// that: it **rebuilds unconditionally**, because *"a repo SHA describes the
/// binary only if we just built the binary from it"* — the rebuild is what earns
/// the attribution, and it is a workaround for this gap.
///
/// ## Why the default is a refusal rather than a guess
///
/// `commit` is `"unattributable"` unless a build deliberately stamped it, and that
/// is the whole design. A plain `swift build` genuinely cannot know its own
/// commit — the tree may be dirty, may be a detached checkout, may not be a git
/// repository at all — so reporting anything else would be a **confident zero**:
/// a claim that looks like provenance and is not.
///
/// This mirrors the vocabulary the driver already uses for the same question:
/// `built` (the SHA is earned) · `stale` (a binary exists but we could not rebuild
/// it) · `unattributable`. The word is deliberately the same one.
///
/// ## How a build stamps it
///
/// `scripts/stamp_build_identity.sh` rewrites the constant below, builds, and
/// restores the file. That is a small, visible, reversible edit rather than a
/// SwiftPM prebuild plugin: plugins are sandboxed, running `git` from one is
/// unreliable across toolchains, and a mechanism that silently fails would
/// reintroduce the exact false-attribution risk this type exists to prevent.
///
/// **The dirty window is real and is the cost.** The script restores the file on
/// exit including on failure; if you see a stamped constant in `git status`, a
/// stamped build was interrupted and `git checkout` on this file is the fix.
public enum BuildIdentity {

    /// The commit this binary was built from, or `"unattributable"`.
    ///
    /// STAMPED BY `scripts/stamp_build_identity.sh` — the exact text of the next
    /// line is what the script rewrites, so do not reformat it.
    public static let commit = "unattributable"

    /// Whether this binary can say where it came from.
    public static var isAttributable: Bool { commit != "unattributable" }

    /// `1.148.0 (a1b2c3d)` when stamped, `1.148.0 (unattributable build)` when not.
    ///
    /// The unstamped form says *build* rather than leaving the word bare, because
    /// a reader seeing only `unattributable` cannot tell whether the tool failed to
    /// find something or is telling them this binary has no provenance.
    public static func versionString(_ version: String) -> String {
        isAttributable ? "\(version) (\(commit))" : "\(version) (unattributable build)"
    }
}
