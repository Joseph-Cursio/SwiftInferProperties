import SwiftInferCore

/// The **member form** of the additive-measure homomorphism —
/// `(a + b).count == a.count + b.count`.
///
/// ## Why this exists: the free-function form reaches nothing
///
/// `HomomorphismTemplate`'s original gate is
/// `parameters.count == 1 && isArrayShaped(param.typeText)` — a free function
/// `[T] -> Int`. **Nobody writes `func count(_ xs: [T]) -> Int` in Swift**; they write
/// `var count: Int` on the type. Measured across eight corpora and ~55,000 functions,
/// the template fired **zero times** (findings §10).
///
/// It was built for a shape the language does not use, and nothing caught that because a
/// dead template and a correctly-silent one produce identical output.
///
/// ## The law is the same; only the spelling moves
///
/// A measure is a monoid homomorphism from the container to `Int`. The free-function
/// form writes it `h(a + b) == h(a) + h(b)`; the member form writes
/// `(a + b).count == a.count + b.count`. Same claim, same failure mode — a `count` that
/// double-counts a seam, an `append` that forgets to grow the count.
///
/// The suggestion carries `templateName: "homomorphism"` for that reason: it is the same
/// law family, and the census should show one template going from 0 to N rather than a
/// new sibling appearing beside a dead one.
///
/// ## The exclusions carry over verbatim, and both matter
///
/// **Grapheme-counting carriers are excluded.** The original doc states it: `String.count`
/// is grapheme count, which is **not** additive across a combining-character boundary —
/// `"e" + "◌́"` is one grapheme, not two. `BigString` is a rope of `Character`s and
/// inherits exactly that.
///
/// The test is textual (`name contains "String"`), which over-excludes
/// `BigString.UnicodeScalarView` — a carrier whose count *is* additive, because scalars
/// do not combine. That is a missed law rather than a false one, and it is the
/// conservative direction PRD §3.5 asks for. Recorded so it is a known cost rather than
/// an accident.
///
/// **Set-like carriers are excluded.** `|A ∪ B| <= |A| + |B|`, with equality only when
/// the operands are disjoint — the measure is *sub*-additive. Handled twice over: the
/// combining operation must be a concatenation verb (`union` is not one), and a
/// `SetAlgebra` conformance vetoes outright.
public enum HomomorphismMemberPairing {

    /// Value-returning concatenations — the operation must produce a new container from
    /// two, freely, with no de-duplication or clamping.
    public static let concatenationNames: Set<String> = ["+", "appending", "concatenated"]

    /// In-place concatenations. `append(contentsOf:)` grows the receiver by the whole of
    /// its argument, which is the same law read as a mutation.
    public static let mutatingConcatenationNames: Set<String> = ["append", "formUnion"]

    /// A carrier name containing this is treated as grapheme-counting. See the type doc
    /// for what it over-excludes and why that is the right direction.
    public static let graphemeCarrierMarker = "String"

    /// One statable member-form homomorphism.
    public struct MemberMeasureShape: Sendable, Equatable {

        /// The carrier, generic parameters stripped — `Deque`.
        public let typeName: String

        /// The measure — `count`.
        public let measure: FunctionSummary

        /// The concatenation it must distribute over — `+` or `append`.
        public let concatenation: FunctionSummary

        /// `true` when the concatenation mutates rather than returns.
        public let concatenationIsMutating: Bool

        public init(
            typeName: String,
            measure: FunctionSummary,
            concatenation: FunctionSummary,
            concatenationIsMutating: Bool
        ) {
            self.typeName = typeName
            self.measure = measure
            self.concatenation = concatenation
            self.concatenationIsMutating = concatenationIsMutating
        }

        /// The law, as Swift.
        public var lawText: String {
            if concatenationIsMutating {
                return "var c = a; c.\(concatenation.name)(b); "
                    + "c.\(measure.name) == a.\(measure.name) + b.\(measure.name)"
            }
            return "(a \(concatenation.name) b).\(measure.name) "
                + "== a.\(measure.name) + b.\(measure.name)"
        }
    }

    /// Every member-form homomorphism statable from `summaries`.
    public static func candidates(
        in summaries: [FunctionSummary],
        inheritedTypesByName: [String: Set<String>]
    ) -> [MemberMeasureShape] {
        var measures: [String: FunctionSummary] = [:]
        var concatenations: [String: FunctionSummary] = [:]

        for summary in summaries {
            guard let carrier = summary.containingTypeName else { continue }
            let key = stripGenerics(carrier)
            if isMemberMeasure(summary), measures[key] == nil {
                measures[key] = summary
            }
            if isFreeConcatenation(summary, carrier: key), concatenations[key] == nil {
                concatenations[key] = summary
            }
        }

        var result: [MemberMeasureShape] = []
        for (carrier, measure) in measures.sorted(by: { $0.key < $1.key }) {
            guard let concatenation = concatenations[carrier] else { continue }
            guard !carrier.contains(graphemeCarrierMarker) else { continue }
            let conformances = inheritedTypesByName[carrier] ?? []
            guard !conformances.contains("SetAlgebra") else { continue }
            result.append(MemberMeasureShape(
                typeName: carrier,
                measure: measure,
                concatenation: concatenation,
                concatenationIsMutating: concatenation.isMutating
            ))
        }
        return result
    }

    /// A nullary, non-mutating, integer-valued member named like a measure.
    static func isMemberMeasure(_ summary: FunctionSummary) -> Bool {
        guard HomomorphismTemplate.curatedVerbs.contains(summary.name),
              summary.parameters.isEmpty,
              !summary.isMutating, !summary.isStatic,
              !summary.isThrows, !summary.isAsync,
              let returnType = summary.returnTypeText else {
            return false
        }
        return HomomorphismTemplate.integerCodomains.contains(returnType)
    }

    /// A concatenation of the carrier with itself — free, so the measure is additive
    /// rather than merely sub-additive.
    static func isFreeConcatenation(_ summary: FunctionSummary, carrier: String) -> Bool {
        let isValueForm = concatenationNames.contains(summary.name) && !summary.isMutating
        let isMutatingForm = mutatingConcatenationNames.contains(summary.name)
            && summary.isMutating
        guard isValueForm || isMutatingForm, !summary.isThrows, !summary.isAsync else {
            return false
        }
        // `formUnion` is in the mutating list only so the veto below can reject it
        // loudly; a set union is sub-additive and never carries this law.
        guard summary.name != "formUnion" else { return false }
        guard summary.parameters.contains(where: { matches($0.typeText, carrier) }) else {
            return false
        }
        if summary.isMutating { return true }
        return summary.returnTypeText.map { matches($0, carrier) } ?? false
    }

    static func matches(_ typeText: String, _ carrier: String) -> Bool {
        typeText == "Self" || stripGenerics(typeText) == carrier
    }

    static func stripGenerics(_ typeText: String) -> String {
        let trimmed = typeText.trimmingCharacters(in: .whitespaces)
        guard let angle = trimmed.firstIndex(of: "<") else { return trimmed }
        return String(trimmed[trimmed.startIndex..<angle])
    }
}

extension HomomorphismTemplate {

    /// The member form, emitted under the same `homomorphism` template name.
    public static func suggestMemberForm(
        for shape: HomomorphismMemberPairing.MemberMeasureShape
    ) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeMemberConstraint(), subject: shape)
    }

    static func makeMemberConstraint()
        -> Constraint<HomomorphismMemberPairing.MemberMeasureShape> {
        Constraint<HomomorphismMemberPairing.MemberMeasureShape>(
            templateName: "homomorphism",
            appliesTo: { _ in true },
            signals: Self.memberSignals(for:),
            evidence: { [$0.measure.inferenceEvidence, $0.concatenation.inferenceEvidence] },
            identity: Self.makeMemberIdentity(for:),
            carrier: { $0.typeName },
            carrierType: { $0.typeName },
            caveats: Self.makeMemberCaveats(for:)
        )
    }

    /// 70 (Likely) — a curated measure name plus a curated concatenation, both required.
    static func memberSignals(
        for shape: HomomorphismMemberPairing.MemberMeasureShape
    ) -> [Signal] {
        [
            Signal(
                kind: .exactNameMatch,
                weight: 40,
                detail: "Curated measure '\(shape.measure.name)' and concatenation "
                    + "'\(shape.concatenation.name)' on \(shape.typeName). A measure is a "
                    + "monoid homomorphism from the container to Int — measuring a join "
                    + "equals summing the measures"
            ),
            Signal(
                kind: .typeSymmetrySignature,
                weight: 30,
                detail: "Member form: `\(shape.typeName).\(shape.measure.name)` is nullary "
                    + "and integer-valued, and `\(shape.concatenation.name)` combines two "
                    + "\(shape.typeName)s freely"
            )
        ]
    }

    static func makeMemberCaveats(
        for shape: HomomorphismMemberPairing.MemberMeasureShape
    ) -> [String] {
        [
            "THE LAW IS `\(shape.lawText)` — the measure distributes over the join. This is "
                + "where the bugs a per-element test never finds actually live: a count that "
                + "double-counts a boundary element, a capacity update that runs before the "
                + "append rather than after, a chunk seam counted twice.",
            "THE JOIN MUST BE FREE. If `\(shape.concatenation.name)` de-duplicates, clamps, "
                + "merges adjacent runs or drops anything, the measure is SUB-additive — "
                + "`<=` rather than `==` — and this law is false by design. Set union is the "
                + "canonical case and is vetoed; confirm this carrier is not a quieter "
                + "version of it.",
            "GRAPHEME-COUNTING CARRIERS ARE EXCLUDED and it is worth knowing why, because it "
                + "is the same trap in your own types: `String.count` counts graphemes, and "
                + "`\"e\" + \"◌́\"` is ONE grapheme, not two. Any carrier whose element is a "
                + "`Character` has a count that is not additive across a join. The exclusion "
                + "here is textual, so a scalar view with `String` in its name is "
                + "over-excluded — a missed law rather than a false one.",
            "GENERATE THE JOIN, NOT THE OPERANDS. Two independently drawn containers exercise "
                + "the seam once each; the failures live at an EMPTY operand, a "
                + "single-element operand, and a join that crosses whatever internal boundary "
                + "the carrier has — a word, a chunk, a capacity. Draw those deliberately."
        ]
    }

    static func makeMemberIdentity(
        for shape: HomomorphismMemberPairing.MemberMeasureShape
    ) -> SuggestionIdentity {
        SuggestionIdentity(
            canonicalInput: "homomorphism|member|\(shape.typeName)|"
                + "\(shape.measure.name)|\(shape.concatenation.name)"
        )
    }
}
