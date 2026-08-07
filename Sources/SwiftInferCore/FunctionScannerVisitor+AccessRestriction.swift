import Foundation
import SwiftSyntax

/// **Why** the scanner sets a declaration aside — the whole of that decision, in one place.
///
/// Split out of `FunctionScanner.swift` on 2026-08-06, when documenting the enclosing-type fix
/// pushed that file past its 400-line cap. The unit moved rather than the reasoning being trimmed,
/// following the rule `docs/design/signal-kind-rationales.md` states for `Signal+Kind`: every comment here
/// records a measurement or a corpus finding, and several are the only surviving record of why a
/// gate exists.
///
/// It is also the more cohesive seam. The two `accessRestriction` overloads must stay in step —
/// `SpeculativeWidening.candidates` filters `RestrictedFunction` on the restriction alone and never
/// asks whether the summary came from a `func` or a computed property — and they are easier to keep
/// in step adjacent than eighty lines apart around an unrelated `visit`.
///
/// The members are `internal` rather than `private` because Swift's `private` is file-scoped and
/// the call sites stayed behind in `FunctionScanner.swift`.
extension FunctionScannerVisitor {

    /// The explicit access modifier on an enclosing type or extension, at the granularity the two
    /// questions actually need — see `enclosingTypeAccess`. Token-less access is `.unmarked`,
    /// matching Lever A's *"the modifier, not the absence, is the signal"* rule: an
    /// internal-by-default type is treated as public-eligible.
    enum EnclosingTypeAccess {
        case unmarked
        case explicitInternal
        case notVisibleToTests
    }

    /// Cycle 151 (Lever D) — the explicit access modifier a type/extension carries.
    ///
    /// Replaced a `Bool` returning "explicitly non-public" on 2026-08-06 — see
    /// `enclosingTypeAccess` for what the collapsed answer cost.
    static func access(of modifiers: DeclModifierListSyntax) -> EnclosingTypeAccess {
        let names = modifiers.map(\.name.text)
        if names.contains("private") || names.contains("fileprivate") { return .notVisibleToTests }
        if names.contains("internal") { return .explicitInternal }
        return .unmarked
    }

    /// Why an external test could not call `node`, or `nil` when it could.
    ///
    /// **The order is the answer, not an implementation detail.** Several reasons can hold at once,
    /// and the one returned is the one a reader must fix *first*, so the most binding constraint is
    /// tested earliest. Reading the declaration's own `private` before looking at what it is nested
    /// inside is what produced the no-op widening patch this ordering exists to prevent — see
    /// `AccessRestriction.enclosingTypeNotVisibleToTests`, and `SpeculativeWidening` for what the
    /// patch cost.
    ///
    /// `isNestedLocalFunction` moved ahead of the modifier check in the same pass. That is
    /// behaviour-preserving on code that compiles — Swift rejects an access modifier in a local
    /// scope (*"attribute 'private' can only be used in a non-local scope"*), so no legal function
    /// can satisfy both tests — and it keeps the most specific reason winning now that a third case
    /// sits between them.
    func accessRestriction(of node: FunctionDeclSyntax) -> AccessRestriction? {
        let modifiers = node.modifiers.map(\.name.text)

        if isNestedLocalFunction(node) {
            return .nestedLocal
        }
        if enclosingTypeAccess.contains(.notVisibleToTests) {
            return .enclosingTypeNotVisibleToTests
        }
        if modifiers.contains("private") || modifiers.contains("fileprivate") {
            return .notVisibleToTests
        }
        if modifiers.contains("internal")
            || hasSPIAttribute(node)
            || typeStack.contains(where: { $0.hasPrefix("_") })
            || enclosingTypeAccess.contains(where: { $0 != .unmarked }) {
            return .internalOrSPI
        }
        return nil
    }

    /// Access restriction for a computed property, mirroring `accessRestriction`
    /// for functions (private/fileprivate → not visible; internal/SPI/`_`-type →
    /// internal). Properties are never "nested local", so that case is omitted.
    ///
    /// **The enclosing-type check is mirrored here deliberately, not just where the bug was
    /// found.** `SpeculativeWidening.candidates` filters on the restriction alone and never asks
    /// which overload produced the summary, so a `private var` inside a `private` type is the same
    /// no-op patch by a second route. Fixing only the arm that motivated the change is the mistake
    /// `EqualityBodyClassifier` already made once, where a tightening validated against its
    /// motivating row silently removed a different one.
    func accessRestriction(ofVariable node: VariableDeclSyntax) -> AccessRestriction? {
        let modifiers = node.modifiers.map(\.name.text)
        if enclosingTypeAccess.contains(.notVisibleToTests) {
            return .enclosingTypeNotVisibleToTests
        }
        if modifiers.contains("private") || modifiers.contains("fileprivate") {
            return .notVisibleToTests
        }
        let hasSPI = node.attributes.contains { element in
            if case let .attribute(attr) = element {
                return attr.attributeName.trimmedDescription == "_spi"
            }
            return false
        }
        if modifiers.contains("internal")
            || hasSPI
            || typeStack.contains(where: { $0.hasPrefix("_") })
            || enclosingTypeAccess.contains(where: { $0 != .unmarked }) {
            return .internalOrSPI
        }
        return nil
    }

    /// Cycle 151 (Lever D) — true if the function carries an `@_spi(...)`
    /// attribute (system programming interface; not importable public API).
    func hasSPIAttribute(_ node: FunctionDeclSyntax) -> Bool {
        node.attributes.contains { element in
            if case let .attribute(attr) = element {
                return attr.attributeName.trimmedDescription == "_spi"
            }
            return false
        }
    }

    /// Cycle 151 (Lever D) — true if the function is a local helper declared
    /// inside another body (function / accessor / closure), not a type member
    /// or top-level declaration. Walks ancestors: a member func reaches a
    /// `MemberBlock` (or the file root) first; a local func hits an enclosing
    /// code block / closure first.
    func isNestedLocalFunction(_ node: FunctionDeclSyntax) -> Bool {
        var ancestor = node.parent
        while let current = ancestor {
            if current.is(MemberBlockSyntax.self) || current.is(SourceFileSyntax.self) {
                return false
            }
            if current.is(CodeBlockSyntax.self) || current.is(ClosureExprSyntax.self)
                || current.is(AccessorBlockSyntax.self) {
                return true
            }
            ancestor = current.parent
        }
        return false
    }
}
