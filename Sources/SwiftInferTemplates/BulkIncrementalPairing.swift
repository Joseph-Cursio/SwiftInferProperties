import Foundation
import SwiftInferCore

/// Recognises the **bulk-vs-incremental** law: building a value in one call must agree
/// with building it one element at a time.
///
///     T(elements) == elements.reduce(into: T()) { $0.insert($1) }
///
/// ## The witness
///
/// Row 1 of `fixtures/swiftorg-study/loops-answer-key.json` —
/// `validation-test/stdlib/RangeSet.swift:74`, over 1,000 random inputs:
///
/// ```swift
/// let set = RangeSet(ranges)
/// var comparison = RangeSet<Int>()
/// for r in ranges { comparison.insert(contentsOf: r) }
/// expectEqual(set, comparison)
/// ```
///
/// ## Why it is refutable
///
/// A bulk entry point almost always takes a *different code path* from the incremental
/// one — pre-sizing storage, sorting once instead of inserting in order, merging
/// adjacent runs in a batch. Those paths diverge on exactly the inputs that are hard to
/// reason about: duplicates, adjacency, and empty. `IdentifiableSet` in
/// swift-package-manager is a live example of the shape's hazard — its bulk init
/// resolves duplicates with `pickLastWhenDuplicateFound`, a policy the incremental path
/// has to match and nothing forces it to.
///
/// ## The discriminator, which is the whole reason this is statable
///
/// **The insert's parameter must be the bulk init's ELEMENT type**, not merely some
/// parameter of the carrier. `RangeSet` declares both `insert(_ value: Bound)` and
/// `insert(contentsOf: Range<Bound>)`, and its bulk init takes `[Range<Bound>]` — so the
/// law pairs with `insert(contentsOf:)`, and pairing with `insert(_:)` would state
/// something flatly false. Measured: the rule picks the right one.
///
/// ## Population is thin, and the reason is a limitation rather than the shape
///
/// **Two rows across seven corpora** — `RangeSet` (the witness) and `IndexPath`. Both
/// real; no false positives to trade against.
///
/// The survey that sized this said three, and the third was mine to correct.
/// `OrderedSet.UnorderedView` matched only through its variadic
/// `init(arrayLiteral elements: Element...)`, which the scanner records as `[Element]`.
/// Its actual bulk init is `init(_ elements: some Sequence<Element>)`. Pairing against an
/// `ExpressibleByArrayLiteral` requirement is a much weaker basis than pairing against a
/// declared bulk entry point, and it is not claimed.
///
/// The count is an **undercount**, and knowing why matters for whether to widen it
/// later. The element match is textual, so it resolves `[Range<Bound>]` and
/// `Array<Element>` and gives up on `init<S: Sequence>(_ elements: S) where S.Element ==
/// Element` — which is the *idiomatic* spelling and the one `RangeReplaceableCollection`
/// mandates. Reaching those needs the where-clause, which the scanner does not record.
///
/// Deliberately not widened by keying on `RangeReplaceableCollection` conformance
/// instead: that protocol **default-implements** the bulk init as `self.init();
/// self.append(contentsOf: elements)`, so the law is true by construction for every
/// conformer that does not override it, and proposing it there would be the
/// unrefutable-by-construction shape `preconditionElidingVariant` was vetoed for.
public enum BulkIncrementalPairing {

    /// Single-element accumulators. Closed and small, on the same principle as
    /// `ModelLawPairing.SetOperation`: each is a verb whose "add one thing" meaning is
    /// definitional rather than a convention a type may reinterpret.
    public static let inserterNames: Set<String> = [
        "insert", "append", "add", "push", "enqueue", "formUnion"
    ]

    /// One statable bulk-vs-incremental law.
    public struct BulkIncrementalShape: Sendable, Equatable {

        /// The carrier, generic parameters stripped — `RangeSet`.
        public let typeName: String

        /// The single-element accumulator the fold applies.
        public let inserter: FunctionSummary

        /// The bulk initializer's parameter type as written — `[Range<Bound>]`.
        public let bulkParameterTypeText: String

        /// Its element type, which is also the inserter's parameter type.
        public let elementTypeText: String

        /// The inserter's argument label, if any — `contentsOf` for the witness.
        public let inserterLabel: String?

        public init(
            typeName: String,
            inserter: FunctionSummary,
            bulkParameterTypeText: String,
            elementTypeText: String,
            inserterLabel: String?
        ) {
            self.typeName = typeName
            self.inserter = inserter
            self.bulkParameterTypeText = bulkParameterTypeText
            self.elementTypeText = elementTypeText
            self.inserterLabel = inserterLabel
        }

        /// The law, as Swift.
        public var lawText: String {
            let call = inserterLabel.map { "\(inserter.name)(\($0): element)" }
                ?? "\(inserter.name)(element)"
            return "\(typeName)(elements) == elements.reduce(into: \(typeName)()) "
                + "{ $0.\(call) }"
        }
    }

    /// Every bulk-vs-incremental law statable from `summaries` + `typeDecls`.
    ///
    /// Needs `typeDecls` as well as summaries because initializers are recorded on the
    /// type declaration, not as function summaries.
    public static func candidates(
        in summaries: [FunctionSummary],
        typeDecls: [TypeDecl]
    ) -> [BulkIncrementalShape] {
        var insertersByCarrier: [String: [FunctionSummary]] = [:]
        for summary in summaries where inserterNames.contains(summary.name) {
            guard summary.isMutating,
                  !summary.isStatic, !summary.isThrows, !summary.isAsync,
                  summary.parameters.count == 1,
                  summary.parameters.first?.isInout == false,
                  let carrier = summary.containingTypeName else { continue }
            insertersByCarrier[stripGenerics(carrier), default: []].append(summary)
        }

        var result: [BulkIncrementalShape] = []
        var seen: Set<String> = []
        for decl in typeDecls.sorted(by: { $0.name < $1.name }) {
            let carrier = stripGenerics(decl.name)
            guard let inserters = insertersByCarrier[carrier] else { continue }
            // The fold needs a seed, and `T()` is it. Without an empty init the law
            // cannot be written at all.
            guard decl.initializers.map(\.parameters).contains(where: \.isEmpty) else { continue }

            for initializer in decl.initializers where initializer.parameters.count == 1 {
                let parameterText = initializer.parameters[0].typeName
                guard let element = bulkElementType(parameterText) else { continue }
                for inserter in inserters
                where inserter.parameters.first?.typeText == element {
                    let key = "\(carrier)|\(inserter.name)|\(element)"
                    guard seen.insert(key).inserted else { continue }
                    result.append(BulkIncrementalShape(
                        typeName: carrier,
                        inserter: inserter,
                        bulkParameterTypeText: parameterText,
                        elementTypeText: element,
                        inserterLabel: inserter.parameters.first?.label
                    ))
                }
            }
        }
        return result
    }

    /// The element type of a bulk parameter, or `nil` when it is not one.
    ///
    /// `[Range<Bound>]` → `Range<Bound>`, `Array<Foo>` → `Foo`. A dictionary literal
    /// (`[K: V]`) is excluded — its element is a pair, not the thing an inserter takes.
    static func bulkElementType(_ text: String) -> String? {
        let bare = text.trimmingCharacters(in: .whitespaces)
        if bare.hasPrefix("["), bare.hasSuffix("]"), !bare.contains(":") {
            return String(bare.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        for prefix in ["Array<", "ContiguousArray<"]
        where bare.hasPrefix(prefix) && bare.hasSuffix(">") {
            return String(bare.dropFirst(prefix.count).dropLast())
                .trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    static func stripGenerics(_ typeText: String) -> String {
        let trimmed = typeText.trimmingCharacters(in: .whitespaces)
        guard let angle = trimmed.firstIndex(of: "<") else { return trimmed }
        return String(trimmed[trimmed.startIndex..<angle])
    }
}
