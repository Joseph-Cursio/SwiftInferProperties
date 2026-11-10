import Foundation
import SwiftSyntax

// Resolving each reducer's Action type to its declaration among the scanned
// sources. Split out of `ReducerDiscoverer.swift` for the `file_length` cap.

/// What a reducer's Action type resolved to among the scanned sources — the
/// declaration's kind, read from syntax, or `.unresolved`.
///
/// Recorded for every carrier because `actionCases` cannot answer the question
/// it was being asked: it holds the cases of a TCA conformer's nested
/// `enum Action` and is empty for every other carrier, so "no cases" meant
/// "not TCA", not "not a closed enum". `unknownActionIsNoOp` gated on it and
/// fired on a closed enum declared in the same file (found 2026-10-10).
public enum ActionTypeKind: String, Sendable, Equatable, Codable, CaseIterable {
    /// A closed alphabet: exhaustive, so no action outside its cases exists.
    case `enum`
    /// An open alphabet: any type may conform. Also what an `any P` / `some P`
    /// spelling names, with no lookup.
    case `protocol`
    case `struct`
    case `class`
    case `actor`
    /// Not declared in the scanned sources (imported from another module, or
    /// spelled as a tuple / optional / composition), or declared twice with
    /// different kinds. Discovery cannot say whether the alphabet is closed.
    case unresolved
}

/// Every nominal type and `typealias` one discovery walk declared, keyed by its
/// qualified path (`Outer.Inner.Action`). Resolves a spelled type name the way
/// Swift does: innermost enclosing scope first, then outward — never by leaf
/// name alone, which would hand a free reducer's imported `Action` protocol the
/// kind of some feature's nested `enum Action`.
struct DeclaredTypeIndex {

    private enum Declaration {
        case type(ActionTypeKind)
        case alias(target: String, scope: [String])
    }

    /// A typealias chain longer than this is reported `.unresolved` rather than
    /// followed — it also stops a cycle.
    private static let aliasHopLimit = 8

    private var byPath: [String: [Declaration]] = [:]

    init() { /* empty index */ }

    init(merging indexes: [Self]) {
        for index in indexes {
            byPath.merge(index.byPath) { $0 + $1 }
        }
    }

    mutating func recordType(_ name: String, kind: ActionTypeKind, scope: [String]) {
        byPath[Self.path(scope, name), default: []].append(.type(kind))
    }

    mutating func recordAlias(_ name: String, target: String, scope: [String]) {
        byPath[Self.path(scope, name), default: []].append(.alias(target: target, scope: scope))
    }

    /// The kind `spelled` names when written inside `scope` (the enclosing
    /// type stack, outermost first).
    func resolve(_ spelled: String, scope: [String]) -> ActionTypeKind {
        resolve(spelled, scope: scope, hops: 0)
    }

    private func resolve(_ spelled: String, scope: [String], hops: Int) -> ActionTypeKind {
        var name = spelled.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("any ") || name.hasPrefix("some ") { return .protocol }
        if name == "Self" { return enclosingKind(scope) }
        if name.hasPrefix("Self.") { name.removeFirst("Self.".count) }
        name = Self.droppingGenericArguments(name)
        guard hops < Self.aliasHopLimit, Self.isIdentifierPath(name) else { return .unresolved }
        for depth in stride(from: scope.count, through: 0, by: -1) {
            guard let found = byPath[Self.path(Array(scope.prefix(depth)), name)] else { continue }
            // The innermost declaration shadows every outer one, even when
            // it resolves to nothing — so the search stops here either way.
            let kinds = Set(found.map { declaration -> ActionTypeKind in
                switch declaration {
                case let .type(kind):
                    return kind

                case let .alias(target, aliasScope):
                    return resolve(target, scope: aliasScope, hops: hops + 1)
                }
            })
            guard kinds.count == 1, let kind = kinds.first else { return .unresolved }
            return kind
        }
        return .unresolved
    }

    /// What `Self` names inside `scope`: the innermost enclosing type. Inside
    /// a protocol extension `Self` is whichever type conforms — not the
    /// protocol, and not knowable here.
    private func enclosingKind(_ scope: [String]) -> ActionTypeKind {
        guard let innermost = scope.last else { return .unresolved }
        let kind = resolve(innermost, scope: Array(scope.dropLast()))
        return kind == .protocol ? .unresolved : kind
    }

    private static func path(_ scope: [String], _ name: String) -> String {
        (scope.map(droppingGenericArguments) + [name]).joined(separator: ".")
    }

    /// `Outer<T>.Action` → `Outer.Action`: a generic argument is not part of
    /// the declaration's path.
    private static func droppingGenericArguments(_ name: String) -> String {
        var depth = 0
        var kept = ""
        for character in name {
            switch character {
            case "<": depth += 1
            case ">": depth -= 1
            default: if depth == 0 { kept.append(character) }
            }
        }
        return kept
    }

    /// A dotted run of identifiers — the only spelling that names one declaration.
    private static func isIdentifierPath(_ name: String) -> Bool {
        name.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { component in
            !component.isEmpty && component.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        }
    }
}

/// One file's walk: its candidates, the type stack each was found under, and
/// the types it declared. Kept instead of the visitor so a directory scan holds
/// no syntax trees while it waits to resolve against the whole directory.
struct ReducerFileScan {
    let candidates: [ReducerCandidate]
    let scopes: [[String]]
    let declaredTypes: DeclaredTypeIndex

    func resolvingActionTypes(in universe: DeclaredTypeIndex) -> [ReducerCandidate] {
        zip(candidates, scopes).map { candidate, scope in
            var resolved = candidate
            resolved.actionTypeKind = universe.resolve(candidate.actionTypeName, scope: scope)
            return resolved
        }
    }
}

extension ReducerDiscoveryVisitor {

    /// Append `found`, remembering the type stack it was found under so its
    /// Action type can be resolved once every file has been walked.
    func record(_ found: [ReducerCandidate]) {
        candidates.append(contentsOf: found)
        candidateScopes.append(contentsOf: repeatElement(typeStack, count: found.count))
    }

    var scan: ReducerFileScan {
        ReducerFileScan(candidates: candidates, scopes: candidateScopes, declaredTypes: declaredTypes)
    }
}
