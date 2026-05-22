import Foundation
import SwiftInferCore

extension TestLifter {

    /// Result of a `TestLifter.discover(in:)` run. Carries lifted
    /// suggestions for every TestLifter pattern surfaced from the
    /// detector pipeline — round-trip (M1), idempotence + commutativity
    /// (M2). M5+ patterns (ordering / count-change / reduce-equivalence)
    /// extend the same `liftedSuggestions` array without changing the
    /// `Artifacts` shape. M7 adds `counterSignals` for the negative-form
    /// asymmetric-assertion mirror pass.
    public struct Artifacts: Sendable, Equatable {

        public let liftedSuggestions: [LiftedSuggestion]

        /// M7 — counter-signals collected by the
        /// `AsymmetricAssertionDetector` pass. Each detection is a
        /// negative-form mirror of one of the six positive `LiftedSuggestion`
        /// patterns; the discover pipeline applies the matching
        /// `-25 .asymmetricAssertion` Signal to TE-side suggestions
        /// and filters the lifted-side suggestions whose key matches.
        public let counterSignals: [LiftedCounterSignal]

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

        /// M10.3 — corpus-wide call-site map built once per
        /// `discover(in:)` run by `DomainCorpusScanner.artifacts(in:)`
        /// over each slice + `mergeCallSites(...)` to flatten. Keyed by
        /// the consumer function's trailing-identifier name; each
        /// site's `argument` classification has already been resolved
        /// against its originating slice's setup bindings (so corpus
        /// merge is safe — identifiers that don't resolve in their own
        /// slice degrade to `.other` and become outliers). The CLI
        /// pipeline's `applyDomainInference(...)` queries this map per
        /// round-trip suggestion to populate `MockGenerator.domainHint`.
        /// Empty when the test corpus has no relevant call sites.
        public let domainCallSitesByConsumer: [String: [DomainCallSite]]

        /// M11.2 — corpus-wide partition candidates built once per
        /// `discover(in:)` run by `EquivalenceClassMarkerExtractor.extract(
        /// methods:slices:markerTable:)` over the parsed test target.
        /// Each candidate is one `(predicateName, markerPair)` partition;
        /// the CLI pipeline's `applyEquivalenceClassEmission(...)` runs
        /// the M11.1 `PredicateEquivalenceClassDetector` against each
        /// (with `summariesByName` for the predicate-shape veto) and
        /// emits one `LiftedSuggestion` per surviving partition into the
        /// promotion stream. Empty when the test corpus has no methods
        /// carrying a curated marker.
        public let equivalenceClassCandidates: [PartitionCandidate]

        public init(
            liftedSuggestions: [LiftedSuggestion],
            setupAnnotationsByOrigin: [LiftedOrigin: [String: String]] = [:],
            constructionRecord: ConstructionRecord = ConstructionRecord(entries: []),
            counterSignals: [LiftedCounterSignal] = [],
            domainCallSitesByConsumer: [String: [DomainCallSite]] = [:],
            equivalenceClassCandidates: [PartitionCandidate] = []
        ) {
            self.liftedSuggestions = liftedSuggestions
            self.setupAnnotationsByOrigin = setupAnnotationsByOrigin
            self.constructionRecord = constructionRecord
            self.counterSignals = counterSignals
            self.domainCallSitesByConsumer = domainCallSitesByConsumer
            self.equivalenceClassCandidates = equivalenceClassCandidates
        }

        public static let empty = Self(
            liftedSuggestions: [],
            setupAnnotationsByOrigin: [:],
            constructionRecord: ConstructionRecord(entries: []),
            counterSignals: [],
            domainCallSitesByConsumer: [:],
            equivalenceClassCandidates: []
        )

        /// The cross-validation keys to feed into
        /// `TemplateRegistry.discover(crossValidationFromTestLifter:)`.
        /// Sorted-array → set conversion is collision-free because
        /// `LiftedSuggestion.crossValidationKey` is `Hashable`.
        public var crossValidationKeys: Set<CrossValidationKey> {
            Set(liftedSuggestions.map(\.crossValidationKey))
        }

        /// M7 — counter-signal keys to feed into
        /// `TemplateRegistry.discover(counterSignalsFromTestLifter:)`.
        /// Same shape as `crossValidationKeys`; the discover pipeline
        /// uses these to (a) apply `-25 .asymmetricAssertion` to
        /// matching TE-side suggestions and (b) filter matching
        /// lifted-side suggestions out of the visible stream.
        public var counterSignalKeys: Set<CrossValidationKey> {
            Set(counterSignals.map(\.crossValidationKey))
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
    public static func discover(
        in directory: URL,
        markerTable: MarkerTable = MarkerTable(
            pairs: MarkerTable.curatedPairs,
            sets: MarkerTable.curatedSets
        )
    ) throws -> Artifacts {
        let summaries = try TestSuiteParser.scanTests(directory: directory)
        var lifted: [LiftedSuggestion] = []
        var counterSignals: [LiftedCounterSignal] = []
        var annotationsByOrigin: [LiftedOrigin: [String: String]] = [:]
        var sliceArtifactsList: [DomainCorpusScanner.SliceArtifacts] = []
        // M11.2 — streaming aggregator avoids retaining all `[SlicedTestBody]`
        // for the discover run (each slice carries SwiftSyntax tree refs).
        // Per §13 row 4 memory ceiling: M11.0's eager (methods, slices)
        // extractor regressed by ~65MB on the 500-file corpus.
        // M13.3 — `markerTable` carries both M11/M13.1 two-class pairs
        // and M13.2 N-class sets. Default is `MarkerTable.curatedPairs`
        // + empty sets; the CLI's `Discover+Pipeline` constructs an
        // effective table by appending vocabulary-supplied entries.
        var equivalenceClassAggregator = PartitionAggregator()
        for summary in summaries {
            let slice = Slicer.slice(summary.body)
            equivalenceClassAggregator.observe(
                method: summary, slice: slice, markerTable: markerTable.pairs
            )
            equivalenceClassAggregator.observeNClass(
                method: summary, slice: slice, markerSets: markerTable.sets
            )
            sliceArtifactsList.append(DomainCorpusScanner.artifacts(in: slice))
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
            collectDetections(
                in: slice,
                origin: origin,
                lifted: &lifted,
                counterSignals: &counterSignals
            )
        }
        // M4.3 — build the corpus-wide construction record once per
        // discover run; the CLI pipeline's mock-inferred fallback
        // queries it after `GeneratorSelection.apply` to fire mock
        // synthesis on lifted-promoted Suggestions whose type isn't
        // memberwise-derivable from `corpus.typeDecls`.
        let constructionRecord = SetupRegionConstructionScanner.record(over: summaries)
        let domainCallSitesByConsumer = DomainCorpusScanner.mergeCallSites(sliceArtifactsList)
        // M11.2 — finalize the partition candidates collected
        // streaming-style by `equivalenceClassAggregator.observe` above.
        let equivalenceClassCandidates = equivalenceClassAggregator.finalize()
        return Artifacts(
            liftedSuggestions: lifted,
            setupAnnotationsByOrigin: annotationsByOrigin,
            constructionRecord: constructionRecord,
            counterSignals: counterSignals,
            domainCallSitesByConsumer: domainCallSitesByConsumer,
            equivalenceClassCandidates: equivalenceClassCandidates
        )
    }

    /// Per-slice detector fan-out. Extracted from `discover(in:)` to
    /// keep that function under SwiftLint's 50-line body cap; the M11.2
    /// streaming-aggregator addition crossed the threshold.
    private static func collectDetections(
        in slice: SlicedTestBody,
        origin: LiftedOrigin,
        lifted: inout [LiftedSuggestion],
        counterSignals: inout [LiftedCounterSignal]
    ) {
        for detection in AssertAfterTransformDetector.detect(in: slice) {
            lifted.append(LiftedSuggestion.roundTrip(from: detection, origin: origin))
        }
        for detection in AssertAfterDoubleApplyDetector.detect(in: slice) {
            lifted.append(LiftedSuggestion.idempotence(from: detection, origin: origin))
        }
        for detection in AssertSymmetryDetector.detect(in: slice) {
            lifted.append(LiftedSuggestion.commutativity(from: detection, origin: origin))
        }
        // M5.5 — second-wave detectors. Same per-summary slice surface
        // as the M2 trio; each detection fans out to a LiftedSuggestion
        // via the matching M5.0 factory.
        for detection in AssertOrderingPreservedDetector.detect(in: slice) {
            lifted.append(LiftedSuggestion.monotonicity(from: detection, origin: origin))
        }
        for detection in AssertCountChangeDetector.detect(in: slice) {
            lifted.append(LiftedSuggestion.countInvariance(from: detection, origin: origin))
        }
        for detection in AssertReduceEquivalenceDetector.detect(in: slice) {
            lifted.append(LiftedSuggestion.reduceEquivalence(from: detection, origin: origin))
        }
        // M7 — seventh-detector pass. Asymmetric-assertion detector
        // surfaces negative-form mirrors of the six positive patterns;
        // each detection becomes a LiftedCounterSignal keyed on the
        // same CrossValidationKey shape the positive detectors use.
        for detection in AsymmetricAssertionDetector.detect(in: slice) {
            counterSignals.append(
                counterSignal(from: detection, slice: slice, origin: origin)
            )
        }
    }

    /// Lift a `DetectedAsymmetricAssertion` into a
    /// `LiftedCounterSignal` carrying the source location of the
    /// triggering assertion + the originating test method's origin.
    /// One arm per positive pattern; sourceLocation is taken from the
    /// slice's terminal assertion (`slice.assertion?.location`) which
    /// is the negative-form assertion the detector matched on.
    private static func counterSignal(
        from detection: DetectedAsymmetricAssertion,
        slice: SlicedTestBody,
        origin: LiftedOrigin
    ) -> LiftedCounterSignal {
        let location = slice.assertion?.location
            ?? SourceLocation(file: origin.sourceLocation.file, line: 0, column: 0)
        switch detection {
        case .roundTrip(let forwardCallee, let backwardCallee):
            return .roundTrip(
                forwardCallee: forwardCallee,
                backwardCallee: backwardCallee,
                sourceLocation: location,
                origin: origin
            )

        case .idempotence(let calleeName):
            return .idempotence(
                calleeName: calleeName,
                sourceLocation: location,
                origin: origin
            )

        case .commutativity(let calleeName):
            return .commutativity(
                calleeName: calleeName,
                sourceLocation: location,
                origin: origin
            )

        case .monotonicity(let calleeName):
            return .monotonicity(
                calleeName: calleeName,
                sourceLocation: location,
                origin: origin
            )

        case .countInvariance(let calleeName):
            return .countInvariance(
                calleeName: calleeName,
                sourceLocation: location,
                origin: origin
            )

        case .reduceEquivalence(let opCalleeName):
            return .reduceEquivalence(
                opCalleeName: opCalleeName,
                sourceLocation: location,
                origin: origin
            )
        }
    }
}
