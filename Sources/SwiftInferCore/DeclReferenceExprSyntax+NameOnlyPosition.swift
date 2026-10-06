import SwiftSyntax

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

    /// Whether this is the member half of a member access, on any base: `name` in `job.name`,
    /// `Rule().name`, `self.name`, and the leading-dot `.name`. The base itself is never a member
    /// name: `job` in `job.name` answers `false`.
    ///
    /// Every caller here asks about test-local bindings, which no member access reaches — not
    /// even through `self`. A reader keyed on stored properties would want `self.name` kept, and
    /// `self?.name`, `self!.name` and `(self).name` with it; none exists yet, so that question is
    /// not answered here.
    public var isMemberName: Bool {
        guard let member = parent?.as(MemberAccessExprSyntax.self) else { return false }
        return member.declName.id == id
    }

    /// Whether this is the name of a member access with no base at all: `red` in `.red`, whose
    /// type comes from the context.
    public var isImplicitMemberName: Bool {
        guard let member = parent?.as(MemberAccessExprSyntax.self), member.declName.id == id else {
            return false
        }
        return member.base == nil
    }

    /// Whether this is a name-only position: a key-path component's name or a member name. A
    /// visitor collecting references to bindings skips these and keeps every other
    /// `DeclReferenceExprSyntax`.
    public var isNameOnlyPosition: Bool {
        isKeyPathComponentName || isMemberName
    }
}
