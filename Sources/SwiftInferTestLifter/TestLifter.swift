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

        public init(liftedSuggestions: [LiftedSuggestion]) {
            self.liftedSuggestions = liftedSuggestions
        }

        public static let empty = Artifacts(liftedSuggestions: [])

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
        for summary in summaries {
            let slice = Slicer.slice(summary.body)
            for detection in AssertAfterTransformDetector.detect(in: slice) {
                lifted.append(LiftedSuggestion.roundTrip(from: detection))
            }
            for detection in AssertAfterDoubleApplyDetector.detect(in: slice) {
                lifted.append(LiftedSuggestion.idempotence(from: detection))
            }
            for detection in AssertSymmetryDetector.detect(in: slice) {
                lifted.append(LiftedSuggestion.commutativity(from: detection))
            }
        }
        return Artifacts(liftedSuggestions: lifted)
    }
}
