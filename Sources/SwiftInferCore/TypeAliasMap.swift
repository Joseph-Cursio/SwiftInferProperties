import SwiftSyntax

/// Collecting `typealias` declarations for the generator resolver.
public enum TypeAliasMap {

    /// One declared alias under both the names a signature may spell it by.
    struct Entry {
        let qualified: String
        let bare: String
        let underlying: String
    }

    /// The alias `node` declares, or `nil` for a generic alias — `typealias Pair<T> = (T, T)` names no
    /// single type the resolver could derive.
    static func entry(for node: TypeAliasDeclSyntax, in typeStack: [String]) -> Entry? {
        guard node.genericParameterClause == nil else { return nil }
        let bare = node.name.text
        return Entry(
            qualified: (typeStack + [bare]).joined(separator: "."),
            bare: bare,
            underlying: node.initializer.value.trimmedDescription
        )
    }

    /// Several files' maps as one. A name two declarations spell differently is dropped rather
    /// than guessed: two nested `Word`s meaning `UInt` and `UInt32` must not resolve either way.
    public static func merged(_ maps: [[String: String]]) -> [String: String] {
        var merged: [String: String] = [:]
        var conflicting: Set<String> = []
        for map in maps {
            for (name, underlying) in map {
                if let existing = merged[name], existing != underlying { conflicting.insert(name) }
                merged[name] = merged[name] ?? underlying
            }
        }
        conflicting.formUnion(merged.filter { $0.value == FunctionScannerVisitor.conflictMarker }.keys)
        conflicting.forEach { merged[$0] = nil }
        return merged
    }
}

extension FunctionScannerVisitor {

    func recordAlias(_ node: TypeAliasDeclSyntax) {
        guard let entry = TypeAliasMap.entry(for: node, in: typeStack) else { return }
        record(alias: entry.qualified, underlying: entry.underlying)
        if entry.bare != entry.qualified { record(alias: entry.bare, underlying: entry.underlying) }
    }

    /// Within one file, too, a bare name spelled two ways is dropped.
    private func record(alias name: String, underlying: String) {
        if let existing = typeAliases[name], existing != underlying {
            typeAliases[name] = Self.conflictMarker
        } else if typeAliases[name] != Self.conflictMarker {
            typeAliases[name] = underlying
        }
    }

    static let conflictMarker = "\u{0}conflict"
}
