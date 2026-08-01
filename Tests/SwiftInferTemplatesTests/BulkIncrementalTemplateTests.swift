import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The **bulk-vs-incremental** law — `T(elements) == elements.reduce(into: T()) { $0.insert($1) }`.
///
/// Row 1 of `fixtures/swiftorg-study/loops-answer-key.json`, the last of the seven gap
/// families to be assessed. The witness is
/// `validation-test/stdlib/RangeSet.swift:74`, which builds a `RangeSet` both ways over
/// 1,000 random inputs and requires them equal.
@Suite("Bulk-vs-incremental — one call must agree with one element at a time")
struct BulkIncrementalTemplateTests {

    private static let loc = SourceLocation(file: "RangeSet.swift", line: 135, column: 1)

    private func inserter(
        _ name: String,
        param: String,
        label: String? = nil,
        on carrier: String = "RangeSet",
        isMutating: Bool = true,
        isStatic: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(label: label, internalName: "value", typeText: param, isInout: false)
            ],
            returnTypeText: nil,
            isThrows: false,
            isAsync: false,
            isMutating: isMutating,
            isStatic: isStatic,
            location: Self.loc,
            containingTypeName: carrier,
            bodySignals: .empty
        )
    }

    private func decl(
        _ name: String = "RangeSet",
        inits: [[String]]
    ) -> TypeDecl {
        TypeDecl(
            name: name,
            kind: .struct,
            inheritedTypes: [],
            location: Self.loc,
            initializers: inits.map { parameters in
                InitializerSignature(
                    parameters: parameters.map {
                        InitializerParameter(label: nil, typeName: $0)
                    },
                    isFailable: false,
                    isThrowing: false
                )
            }
        )
    }

    // MARK: - The witness

    /// `RangeSet` declares BOTH `insert(_ value: Bound)` and
    /// `insert(contentsOf: Range<Bound>)`, and its bulk init takes `[Range<Bound>]`.
    /// Pairing the wrong one states a flatly false law, so this is the arm that matters.
    @Test("The element type picks insert(contentsOf:) over insert(_:)")
    func elementTypeDiscriminatesBetweenTwoInserters() {
        let shapes = BulkIncrementalPairing.candidates(
            in: [
                inserter("insert", param: "Bound"),
                inserter("insert", param: "Range<Bound>", label: "contentsOf")
            ],
            typeDecls: [decl(inits: [[], ["[Range<Bound>]"]])]
        )
        #expect(shapes.count == 1)
        #expect(shapes.first?.elementTypeText == "Range<Bound>")
        #expect(shapes.first?.inserterLabel == "contentsOf")

        let suggestion = shapes.first.flatMap(BulkIncrementalTemplate.suggest(for:))
        #expect(suggestion?.templateName == "bulk-incremental-agreement")
        #expect(suggestion?.score.total == 70)
        #expect(suggestion?.score.tier == .likely)
    }

    /// The law text is what a reader will act on, so it has to name the right call.
    @Test("The rendered law carries the inserter's label")
    func lawTextIsCorrect() {
        let shapes = BulkIncrementalPairing.candidates(
            in: [inserter("insert", param: "Range<Bound>", label: "contentsOf")],
            typeDecls: [decl(inits: [[], ["[Range<Bound>]"]])]
        )
        #expect(shapes.first?.lawText.contains("insert(contentsOf: element)") == true)
        #expect(shapes.first?.lawText.contains("reduce(into: RangeSet())") == true)
    }

    // MARK: - What it declines

    /// The fold needs a seed. Without `T()` the law cannot be written at all.
    @Test("Silent without an empty initializer")
    func silentWithoutEmptyInit() {
        let shapes = BulkIncrementalPairing.candidates(
            in: [inserter("insert", param: "Range<Bound>", label: "contentsOf")],
            typeDecls: [decl(inits: [["[Range<Bound>]"]])]
        )
        #expect(shapes.isEmpty)
    }

    /// A non-mutating method is not the incremental construction — it may be a query.
    @Test("Silent for a non-mutating inserter")
    func silentForNonMutating() {
        let shapes = BulkIncrementalPairing.candidates(
            in: [inserter("insert", param: "Range<Bound>", label: "contentsOf", isMutating: false)],
            typeDecls: [decl(inits: [[], ["[Range<Bound>]"]])]
        )
        #expect(shapes.isEmpty)
    }

    /// **The documented limitation, pinned so it is a known miss rather than a surprise.**
    /// `init(_ elements: some Sequence<Element>)` is the idiomatic Swift spelling and the
    /// one `RangeReplaceableCollection` mandates, but the element match is textual and a
    /// generic constraint is not text. `OrderedSet.UnorderedView` is a real carrier lost
    /// this way.
    @Test("A generic sequence parameter is not resolvable, and is skipped")
    func genericSequenceParameterSkipped() {
        let shapes = BulkIncrementalPairing.candidates(
            in: [inserter("insert", param: "Element")],
            typeDecls: [decl(inits: [[], ["some Sequence<Element>"]])]
        )
        #expect(shapes.isEmpty)
    }

    /// A dictionary's element is a pair, not the thing an inserter takes.
    @Test("A dictionary literal parameter is not a bulk element sequence")
    func dictionaryParameterSkipped() {
        #expect(BulkIncrementalPairing.bulkElementType("[Key: Value]") == nil)
        #expect(BulkIncrementalPairing.bulkElementType("[Element]") == "Element")
        #expect(BulkIncrementalPairing.bulkElementType("Array<Foo>") == "Foo")
        #expect(BulkIncrementalPairing.bulkElementType("Element") == nil)
    }

    /// An accumulator whose parameter is not the bulk element is a different operation.
    @Test("Silent when no inserter matches the bulk element type")
    func silentOnElementMismatch() {
        let shapes = BulkIncrementalPairing.candidates(
            in: [inserter("insert", param: "Bound")],
            typeDecls: [decl(inits: [[], ["[Range<Bound>]"]])]
        )
        #expect(shapes.isEmpty)
    }

    // MARK: - Explainability (PRD §4.5)

    /// The law is close to vacuous on well-separated distinct elements, which is exactly
    /// what a naive generator produces — so the collision requirement has to be stated.
    @Test("The caveats name the collision requirement, order, and the kit boundary")
    func caveatsCarryTheHazards() {
        let shapes = BulkIncrementalPairing.candidates(
            in: [inserter("insert", param: "Range<Bound>", label: "contentsOf")],
            typeDecls: [decl(inits: [[], ["[Range<Bound>]"]])]
        )
        let caveats = shapes.first.map(BulkIncrementalTemplate.makeCaveats(for:)) ?? []
        #expect(caveats.contains { $0.contains("DUPLICATES AND ADJACENCY") })
        #expect(caveats.contains { $0.contains("ORDER IS PART OF THE CLAIM") })
        #expect(caveats.contains { $0.contains("checkRangeReplaceableCollectionPropertyLaws") })
    }

    @Test("The generator recipe demands collisions and the empty case")
    func generatorRationale() {
        let shapes = BulkIncrementalPairing.candidates(
            in: [inserter("insert", param: "Range<Bound>", label: "contentsOf")],
            typeDecls: [decl(inits: [[], ["[Range<Bound>]"]])]
        )
        let recipes = shapes.first.map(BulkIncrementalTemplate.makeGenerators(for:)) ?? []
        #expect(recipes.first?.rationale.contains("COLLISION-HEAVY") == true)
        #expect(recipes.first?.rationale.contains("empty sequence") == true)
    }

    /// Identity must be stable across runs so `accept` / `drift` can track a suggestion,
    /// and distinct per carrier so two carriers never collide.
    ///
    /// The first version of this arm compared `makeIdentity(for: shape)` with itself,
    /// which SwiftLint's `identical_operands` correctly flagged as testing nothing — a
    /// small instance of the same "check that cannot fail" the whole study is about.
    @Test("Identity is stable across equal shapes and distinct across carriers")
    func identityIsStableAndScoped() {
        func shape(carrier: String) -> BulkIncrementalPairing.BulkIncrementalShape? {
            BulkIncrementalPairing.candidates(
                in: [inserter("insert", param: "Range<Bound>", label: "contentsOf", on: carrier)],
                typeDecls: [decl(carrier, inits: [[], ["[Range<Bound>]"]])]
            ).first
        }
        guard let rangeSet = shape(carrier: "RangeSet"),
              let rebuilt = shape(carrier: "RangeSet"),
              let other = shape(carrier: "IntervalBag") else {
            Issue.record("expected three shapes")
            return
        }
        let identity = BulkIncrementalTemplate.makeIdentity(for: rangeSet)
        #expect(identity == BulkIncrementalTemplate.makeIdentity(for: rebuilt))
        #expect(identity != BulkIncrementalTemplate.makeIdentity(for: other))
    }
}
