import SwiftSyntax

/// Which member names `DeclReferenceExprSyntax.isMemberName(on:)` answers `true` for.
public enum MemberNameBase: Sendable {
    /// Every member name, whatever its base: `name` in `job.name`, `Rule().name` and
    /// `self.name`, and the leading-dot `.name`, which has no base at all.
    case anyBase
    /// Every member name except one whose base is `self`. Inside a type's own method,
    /// `self.name` is the stored property `name` spelled out, so a reader that keys on stored
    /// properties keeps it as a reference. `job.name`, `Rule().name` and `.name` still name a
    /// member of some other value.
    case otherThanSelf
}

/// Positions where a `DeclReferenceExprSyntax` is only a NAME, never a reference to a binding.
///
/// swift-syntax spells three different things with one node. `name` in `f(name)` reads a
/// binding. `name` in `job.name` and in `\.name` does not. It is the name of a member of
/// whatever the base or the key path's root turns out to be, and a test-local `let name`
/// has nothing to do with it. Both of those are `DeclReferenceExprSyntax` too. One is the
/// `declName` of a `MemberAccessExprSyntax`, the other the `declName` of a
/// `KeyPathPropertyComponentSyntax`. A visitor that overrides `visit(_: DeclReferenceExprSyntax)`
/// and asks only for `baseName` sees all three as the same thing.
///
/// What goes wrong depends on the visitor. A free-name check refuses a self-contained
/// `Sorter(by: \.name)`. A slicer pulls in an unrelated `let id = 7` because of `.map(\.id)`.
/// A rewriter that substitutes a binding's value into the name slot builds a tree whose
/// `declName` is not a `DeclReferenceExprSyntax`, and the first reader of `.declName` traps.
///
/// ⚠ **Only the NAME is name-only.** The base of a member access (`job` in `job.name`) is a
/// reference in its own right, and so is a key-path subscript component's argument (`index`
/// in `\.[index]`). Neither is answered `true` here, so a visitor that skips name-only
/// positions still visits both.
extension DeclReferenceExprSyntax {

    /// Whether this is the name of a key-path property component: `name` in `\.name`,
    /// `\Job.name`, and both `owner` and `name` in `\.owner.name`.
    ///
    /// A subscript component's argument is not one. `index` in `\.[index]` is evaluated when
    /// the key path is formed, which makes it a read.
    public var isKeyPathComponentName: Bool {
        parent?.as(KeyPathPropertyComponentSyntax.self)?.declName.id == id
    }

    /// Whether this is the member half of a member access whose base `scope` admits.
    ///
    /// `.anyBase` is every member name, `self.name` included. `.otherThanSelf` leaves
    /// `self.name` out. The base itself is never a member name: `job` in `job.name` answers
    /// `false` either way.
    public func isMemberName(on scope: MemberNameBase) -> Bool {
        guard let member = parent?.as(MemberAccessExprSyntax.self), member.declName.id == id else {
            return false
        }
        switch scope {
        case .anyBase:
            return true

        case .otherThanSelf:
            return member.base?.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind != .keyword(.self)
        }
    }

    /// Whether this is a name-only position: a key-path component's name, or a member name
    /// whose base `members` admits. A visitor collecting references to bindings skips these and
    /// keeps every other `DeclReferenceExprSyntax`.
    public func isNameOnlyPosition(members: MemberNameBase) -> Bool {
        isKeyPathComponentName || isMemberName(on: members)
    }
}
