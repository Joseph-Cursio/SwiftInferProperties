import SwiftInferCore

/// The **uniquifier** law (SwiftInferProperties#669, built as #692): state that hands out names and remembers
/// them owes, on one receiver, n calls with n pairwise-distinct results. A **memoizing** uniquifier, one that
/// returns the id it stored for a key it has seen, owes the other form: equal keys give equal ids, and distinct
/// keys give distinct ids.
///
/// ```swift
/// func uniqName(item: SyntaxStructure, relationship: String) -> String {
///     guard let name = item.fullName else { return "" }
///     var newName = name
///     if uniqElementNames.contains(name) {
///         newName += "\(index)"
///         index += 1
///     } else {
///         uniqElementNames.append(name)
///     }
///     return newName
/// }
/// ```
///
/// is #669's witness: the suffixed name is never re-checked, so `struct Foo0`, `struct Foo` and
/// `extension Foo` were all declared as `Foo0` (SwiftUMLStudio#54).
///
/// ## The gate
///
/// #669's three criteria, as the census applied them (`docs/measurements/uniquifier-law-census.md`: 9 rows
/// admitted, 8 owed the law):
///
/// 1. **state across calls**: a method of a class, a `mutating` method, or an `inout` collection parameter,
///    returning a value;
/// 2. **a test of a candidate against names already issued, decorated on a hit**;
/// 3. **a write back to that state**.
///
/// 2 and 3 are read off the body (`UniquifierShapeReader`). A name such as `uniq…` or `fresh…` only adds to
/// the score: #669 warns a name alone mostly finds deduplication helpers.
///
/// ## Two declines the census measured
///
/// - **A setup call.** SwiftUMLStudio's fixed `uniqName` repeats an alias in 15–20% of drawn sequences
///   unless `reserveIdentifiers(drawing:)` runs first, as its contract says. A sibling method that writes the
///   state this function tests, and is not itself a uniquifier, is read as such a call, and the subject is
///   declined rather than given a law that is false on correct code.
/// - **A recycling pool.** A sibling that removes from the tested state hands a released name out again by
///   design: swift-foundation's `AutoDictionary.insert`, the census gate's one miss.
///
/// Both are reported by `declineReason(for:siblings:)`. Async, throwing and actor methods are declined too,
/// for now: the stub's shell calls the subject synchronously.
///
/// ## Tier
///
/// Possible, behind `--include-possible` (#669 *Gating*): the role is read from the body's shape, but the law
/// is not, and the template's output over the census population has to be hand-checked before it rises.
public enum UniquifierTemplate {

    /// The template's name.
    public static let name = "uniquifier"

    /// The suggestion for `summary`, or `nil` when it is not gated or is declined.
    ///
    /// - Parameters:
    ///   - siblings: the other functions declared in `summary`'s type, for the two declines.
    ///   - owners: which type names are classes and actors.
    public static func suggest(
        for summary: FunctionSummary,
        siblings: [FunctionSummary],
        owners: UniquifierOwners
    ) -> Suggestion? {
        guard declineReason(for: summary, siblings: siblings) == nil,
              let match = match(for: summary, owners: owners) else {
            return nil
        }
        return ConstraintRunner.suggest(constraint: makeConstraint(match: match), subject: summary)
    }

    /// What the template matched in `summary`, or `nil` when criterion 1 or the body's shape is missing.
    public static func match(for summary: FunctionSummary, owners: UniquifierOwners) -> UniquifierMatch? {
        guard let shape = summary.bodySignals.uniquifierShape, !summary.isAsync, !summary.isThrows,
              let form = form(of: summary, owners: owners) else {
            return nil
        }
        let stateIndex: Int? = if case .inoutParameter(let index, _) = form { index } else { nil }
        let inputs = summary.parameters.indices.filter { $0 != stateIndex }
        let nameParameter = inputs.count == 1 && summary.parameters[inputs[0]].typeText == "String"
            ? inputs[0]
            : nil
        return UniquifierMatch(
            shape: shape,
            form: form,
            parameterTypes: summary.parameters.map(\.typeText),
            nameParameter: nameParameter
        )
    }

    /// Where `summary` keeps its state, or `nil` when it keeps none across calls.
    static func form(of summary: FunctionSummary, owners: UniquifierOwners) -> UniquifierForm? {
        if let index = summary.parameters.firstIndex(where: {
            $0.isInout && UniquifierShapeReader.isCollectionType($0.typeText)
        }) {
            return .inoutParameter(index: index, collectionType: summary.parameters[index].typeText)
        }
        guard !summary.isStatic, let owner = summary.containingTypeName else { return nil }
        if summary.isMutating { return .mutating }
        return owners.classes.contains(owner) ? .instance : nil
    }

    /// Why a gated `summary` is declined, or `nil` when it is not.
    public static func declineReason(for summary: FunctionSummary, siblings: [FunctionSummary]) -> String? {
        guard let shape = summary.bodySignals.uniquifierShape else { return nil }
        let tested = Set(shape.testedBases)
        if let own = summary.bodySignals.stateWrites, let state = own.removed.intersection(tested).min() {
            return "RECYCLING: `\(summary.name)` itself removes from `\(state)`, so a released name is issued again"
        }
        guard summary.containingTypeName != nil else { return nil }
        for sibling in siblings where sibling.location != summary.location && !sibling.isStatic {
            guard let writes = sibling.bodySignals.stateWrites else { continue }
            if let state = writes.removed.intersection(tested).min() {
                return "RECYCLING: `\(sibling.name)` removes from `\(state)`, so a released name is issued again"
            }
            if sibling.bodySignals.uniquifierShape == nil,
               let state = writes.written.intersection(tested).min() {
                return "SETUP: `\(sibling.name)` writes `\(state)`, which `\(summary.name)` tests, so the law may "
                    + "hold only after that call"
            }
        }
        return nil
    }

    static func makeConstraint(match: UniquifierMatch) -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: name,
            appliesTo: { _ in true },
            signals: { signals(for: $0, match: match) },
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(canonicalInput: "uniquifier|" + IdempotenceTemplate.canonicalSignature(of: summary))
            },
            carrier: { $0.containingTypeName },
            carrierType: { summary in
                if case .inoutParameter(_, let collectionType) = match.form { return collectionType }
                return summary.containingTypeName
            },
            caveats: { _ in UniquifierCaveats.caveats(for: match) },
            match: { _ in .uniquifier(match) }
        )
    }

    /// The body's shape in the Possible band (+25), and a corroborating name (+10) that cannot lift it out.
    static func signals(for summary: FunctionSummary, match: UniquifierMatch) -> [Signal] {
        let shape = match.shape
        let law = shape.isMemoizing
            ? "returns a stored id for a seen key (memoizing: equal keys give equal ids, distinct keys distinct ids)"
            : "so n calls on one receiver owe n distinct results"
        var signals = [
            Signal(
                kind: .uniquifierShape,
                weight: 25,
                detail: "the body tests a candidate against `\(shape.testedBases.joined(separator: "`, `"))` "
                    + "(line \(shape.testLine)), decorates it on a hit (line \(shape.decorationLine)) and writes "
                    + "back (line \(shape.writeLine)): it \(law)"
            ),
        ]
        let words = summary.name.lowercased()
        if ["uniq", "fresh", "disambig"].contains(where: words.contains) {
            signals.append(Signal(
                kind: .exactNameMatch,
                weight: 10,
                detail: "the name `\(summary.name)` says it hands out distinct names"
            ))
        }
        return signals
    }
}

extension TemplateRegistry {

    /// `UniquifierTemplate`, reached from `collectShapeSuggestions`: each function is read with the other
    /// functions of its type, for the setup and recycling declines.
    static func collectUniquifierSuggestions(
        summaries: [FunctionSummary],
        typeDecls: [TypeDecl],
        into collector: inout SuggestionCollector
    ) {
        let owners = UniquifierOwners(typeDecls: typeDecls)
        let byType = Dictionary(grouping: summaries) { $0.qualifiedContainingTypeName ?? $0.containingTypeName ?? "" }
        for summary in summaries where summary.bodySignals.uniquifierShape != nil {
            let siblings = summary.containingTypeName == nil
                ? []
                : byType[summary.qualifiedContainingTypeName ?? summary.containingTypeName ?? ""] ?? []
            if let suggestion = UniquifierTemplate.suggest(for: summary, siblings: siblings, owners: owners) {
                collector.record(suggestion, generatorType: "String")
            }
        }
    }
}
