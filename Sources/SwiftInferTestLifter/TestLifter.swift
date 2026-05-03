import Foundation
import SwiftInferCore

extension TestLifter {

    /// Result of a `TestLifter.discover(in:)` run. Carries lifted
    /// suggestions for every TestLifter pattern surfaced from the
    /// detector pipeline — round-trip (M1), idempotence + commutativity
    /// (M2). M5+ patterns (ordering / count-change / reduce-equivalence)
    /// extend the same `liftedSuggestions` array without changing the
    /// `Artifacts` shape.
    public struct Artifacts: Sendable, Equatable {

        public let liftedSuggestions: [LiftedSuggestion]

        /// M4.2 — per-origin setup-region annotation maps for the
        /// `LiftedSuggestionRecovery` annotation tier. One entry per
        /// `LiftedOrigin` with at least one detection; entries are
        /// computed once per slice and reused across all detectors that
        /// fired on that slice. Empty for projects with no annotated /
        /// bare-constructor bindings — the recovery pass treats it as
        /// purely additive (FunctionSummary tier still runs first).
        public let setupAnnotationsByOrigin: [LiftedOrigin: [String: String]]

        /// M4.3 — corpus-wide construction record built once per
        /// `discover(in:)` run by `SetupRegionConstructionScanner.
        /// record(over: testMethods)`. The CLI pipeline's mock-inferred
        /// fallback queries this for `MockGeneratorSynthesizer.synthesize(
        /// typeName:record:)` lookups when a lifted-promoted Suggestion
        /// exits `GeneratorSelection.apply` with `.notYetComputed` source.
        /// Empty when the test corpus has no `T(...)` constructor sites.
        public let constructionRecord: ConstructionRecord

        public init(
            liftedSuggestions: [LiftedSuggestion],
            setupAnnotationsByOrigin: [LiftedOrigin: [String: String]] = [:],
            constructionRecord: ConstructionRecord = ConstructionRecord(entries: [])
        ) {
            self.liftedSuggestions = liftedSuggestions
            self.setupAnnotationsByOrigin = setupAnnotationsByOrigin
            self.constructionRecord = constructionRecord
        }

        public static let empty = Artifacts(
            liftedSuggestions: [],
            setupAnnotationsByOrigin: [:],
            constructionRecord: ConstructionRecord(entries: [])
        )

        /// The cross-validation keys to feed into
        /// `TemplateRegistry.discover(crossValidationFromTestLifter:)`.
        /// Sorted-array → set conversion is collision-free because
        /// `LiftedSuggestion.crossValidationKey` is `Hashable`.
        public var crossValidationKeys: Set<CrossValidationKey> {
            Set(liftedSuggestions.map(\.crossValidationKey))
        }
    }

    /// Walk `directory` recursively, parse every `.swift` file as a
    /// potential test source, slice each test method body, run all
    /// TestLifter detectors against the slice, and collect the
    /// surviving `LiftedSuggestion` records.
    ///
    /// **No directory filtering at this layer** — TestSuiteParser only
    /// emits summaries for files containing recognized test methods
    /// (XCTestCase subclasses or `@Test func`), so production source
    /// files naturally produce no summaries and contribute nothing to
    /// the artifacts. M1.5 calls this with the same `discover` target
    /// directory the TemplateEngine uses; the M1 plan's open
    /// decision #1 default `(a)` resolves the layering.
    public static func discover(in directory: URL) throws -> Artifacts {
        let summaries = try TestSuiteParser.scanTests(directory: directory)
        var lifted: [LiftedSuggestion] = []
        var annotationsByOrigin: [LiftedOrigin: [String: String]] = [:]
        for summary in summaries {
            let slice = Slicer.slice(summary.body)
            let origin = LiftedOrigin(
                testMethodName: summary.methodName,
                sourceLocation: summary.location
            )
            // M4.2 — per-test-method annotation map for the
            // `LiftedSuggestionRecovery` annotation tier. Populated
            // unconditionally (cheap walk, linear in slice size); the
            // recovery pass only consults it when the FunctionSummary
            // tier misses, so empty maps are fine.
            let annotations = SetupRegionTypeAnnotationScanner.annotations(in: slice)
            if !annotations.isEmpty {
                annotationsByOrigin[origin] = annotations
            }
            for detection in AssertAfterTransformDetector.detect(in: slice) {
                lifted.append(LiftedSuggestion.roundTrip(from: detection, origin: origin))
            }
            for detection in AssertAfterDoubleApplyDetector.detect(in: slice) {
                lifted.append(LiftedSuggestion.idempotence(from: detection, origin: origin))
            }
            for detection in AssertSymmetryDetector.detect(in: slice) {
                lifted.append(LiftedSuggestion.commutativity(from: detection, origin: origin))
            }
        }
        // M4.3 — build the corpus-wide construction record once per
        // discover run; the CLI pipeline's mock-inferred fallback
        // queries it after `GeneratorSelection.apply` to fire mock
        // synthesis on lifted-promoted Suggestions whose type isn't
        // memberwise-derivable from `corpus.typeDecls`.
        let constructionRecord = SetupRegionConstructionScanner.record(over: summaries)
        return Artifacts(
            liftedSuggestions: lifted,
            setupAnnotationsByOrigin: annotationsByOrigin,
            constructionRecord: constructionRecord
        )
    }
}
