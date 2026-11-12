import SwiftSyntax

/// A body testing something against a collection: the census's TEST cue
/// (`uniquifier-law-census-scope.md` §1.2).
struct MembershipTest {
    /// The test's form.
    enum Kind: Equatable {
        /// `names.contains(x)`.
        case contains
        /// `table[k] == nil` or `!= nil`.
        case nilCompare
        /// `table[k, default: …]`.
        case defaultSubscript
        /// `table[k] ?? …`.
        case coalesce
        /// `if let v = table[k]`, in any clause of an `if`, `guard` or `while`.
        case binding
        /// `table.index(forKey: k)`.
        case indexForKey
        /// `set.insert(x).inserted`.
        case inserted
    }

    /// The test's form.
    let kind: Kind
    /// The tested collection's chain, `self.`, `?` and `!` removed: `existing.values`.
    let chain: String
    /// The node carrying the test: the call or subscript.
    let node: Syntax
    /// What is tested: the call's or subscript's arguments.
    let argument: Syntax

    /// The chain's first component: `existing.values.contains` tests `existing`.
    var base: String { UniquifierBody.base(of: chain) }
}
