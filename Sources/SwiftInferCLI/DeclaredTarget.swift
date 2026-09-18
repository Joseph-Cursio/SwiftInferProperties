import Foundation

/// One target a package manifest declares, with the directory it actually occupies.
///
/// **A named type rather than a tuple**, for the reason the linter states and one it does not:
/// three members is past the tuple cap, and `$0.isTest` reads at a call site where `$0.2` would
/// not. `EffectClaims` was extracted for the same pair of reasons.
///
/// ## Why the kind is carried
///
/// `Sources/<name>` is SwiftPM's default for a `.target`. **A `.testTarget` defaults to
/// `Tests/<name>`**, and assuming the first for both reported a directory no package has, so no
/// consumer could resolve a file under `Tests/` (SwiftInferProperties#521).
///
/// Every consumer was nonetheless *correct*, because each confirms the directory on disk and the
/// bogus path failed that check. **They were correct by accident**, and the accident is not a
/// policy — with the map fixed, each consumer has to choose its own population, and they do not
/// choose the same one:
///
/// - resolving a subject's **module** wants `isTest == false`. The name becomes
///   `@testable import <module>`, and a subject declared inside a test target needs no import at
///   all — it is already in the stub's module. Naming the test target emits an import that does
///   not compile.
/// - resolving a subject's **isolation** wants every target. The compiler applies a test target's
///   `.defaultIsolation` exactly as it applies a library target's, so a subject declared in one
///   is isolated and its stub needs the hop.
/// - resolving a target **by name**, for `--target`, wants every target: asked where `CoreTests`
///   lives, answering `Tests/CoreTests` is simply the truth.
public struct DeclaredTarget {

    /// The target's name, as the manifest spells it.
    public let name: String

    /// The directory it occupies, relative to the package root — the **effective** path, so a
    /// target with no `path:` reports the directory SwiftPM would use rather than nothing.
    public let path: String

    /// Whether SwiftPM calls this a `test` target. Drives the default above, and lets a consumer
    /// state its population instead of inheriting one.
    public let isTest: Bool
}
