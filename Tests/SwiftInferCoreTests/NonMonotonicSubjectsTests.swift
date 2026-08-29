import Foundation
import Testing

@testable import SwiftInferCore

/// **The gate's classifier, and the controls that make its zeros mean something.**
///
/// `monotonicity` fires on a `Comparable -> Comparable` signature with nothing asking
/// whether the operation HAS the property (`open-threads.md` row 69). This covers the half
/// decidable from the name — and the arms below are, in order of what they are guarding:
/// the measured population, the true laws that must survive, and the two probes that were
/// measurably wrong before this one.
@Suite("NonMonotonicSubjects — the definitionally-false half of monotonicity")
struct NonMonotonicSubjectsTests {

    /// The population the census measured, in the spellings it found them in.
    @Test("the measured population is caught", arguments: [
        "_cos(_:)", "_sin(_:)",
        "_rawHashValue(seed:)", "_rawHashValue(_seed:)", "_hashValue(for:)",
        "_hashValue(at:)", "hashValue(at:)", "hashValue(for:)",
        "Hashable_hashValue_indirect(_:)"
    ])
    func measuredPopulationIsCaught(name: String) {
        #expect(NonMonotonicSubjects.isDefinitionallyNonMonotonic(name), "\(name) is not order-preserving")
    }

    /// **The load-bearing control: functions that ARE monotonic must survive.**
    ///
    /// `MathForwardFunctions.curated` contains every one of these, which is exactly why it
    /// could not be reused as the gate's set — it would remove true laws to remove false
    /// ones. `sinh`/`tanh`/`asin`/`atan`/`asinh`/`atanh`/`acosh` are strictly increasing;
    /// `exp` and `log` and the roots likewise. The stdlib shims among them (`_exp`, `_log`,
    /// `_log2`, `_log10`, `_nearbyint`) are 8 measured rows the gate leaves alone.
    @Test("genuinely monotonic functions survive", arguments: [
        "_exp(_:)", "_exp2(_:)", "_log(_:)", "_log2(_:)", "_log10(_:)", "_nearbyint(_:)",
        "sinh(_:)", "tanh(_:)", "asin(_:)", "atan(_:)", "asinh(_:)", "atanh(_:)", "acosh(_:)",
        "sqrt(_:)", "cbrt(_:)"
    ])
    func monotonicFunctionsSurvive(name: String) {
        #expect(
            !NonMonotonicSubjects.isDefinitionallyNonMonotonic(name),
            "\(name) is strictly increasing — removing it would cost a TRUE law"
        )
    }

    /// **The substring probe's coincidences, every one measured on the real corpora.**
    /// `distance` contains `tan`; `secondsInDay` contains `sin`. A `contains` check scores
    /// all six as trigonometric.
    @Test("substring coincidences are not caught", arguments: [
        "distance(to:)", "editDistance(to:)", "indentationDistance(of:)",
        "secondsInDay(from:)", "numWeeksInYearForWeekOfYear(_:)",
        "clampedMinimumDaysInFirstWeek(_:)", "_class_getInstancePositiveExtentSize(_:)"
    ])
    func substringCoincidencesAreNotCaught(name: String) {
        #expect(
            !NonMonotonicSubjects.isDefinitionallyNonMonotonic(name),
            "\(name) matched on a substring — `distance` contains `tan`, `secondsInDay` contains `sin`"
        )
    }

    /// The tokenizer, stated directly. An argument label is the CALLER's word and is
    /// dropped, so `wordCount(forScale:)` must not tokenise to include `scale`.
    @Test("tokens split on underscore and camelCase, and drop argument labels")
    func tokensSplitCorrectly() {
        #expect(NonMonotonicSubjects.tokens(of: "_rawHashValue(seed:)") == ["raw", "hash", "value"])
        #expect(NonMonotonicSubjects.tokens(of: "wordCount(forScale:)") == ["word", "count"])
        #expect(NonMonotonicSubjects.tokens(of: "distance(to:)") == ["distance"])
        #expect(NonMonotonicSubjects.tokens(of: "_cos(_:)") == ["cos"])
    }

    /// `acos` is *decreasing*, and the emitted law checks non-decreasing (`if resultA >
    /// resultB { FAIL }`), so it belongs in the set for a different reason than `sin` —
    /// worth pinning, because a future reader reasoning "inverse trig is monotonic" would
    /// otherwise remove it correctly-looking and wrongly.
    @Test("acos is excluded as decreasing, its inverse-trig siblings are not")
    func acosIsDecreasing() {
        #expect(NonMonotonicSubjects.isDefinitionallyNonMonotonic("acos(_:)"))
        #expect(NonMonotonicSubjects.isDefinitionallyNonMonotonic("cosh(_:)"))
        #expect(!NonMonotonicSubjects.isDefinitionallyNonMonotonic("acosh(_:)"))
        #expect(!NonMonotonicSubjects.isDefinitionallyNonMonotonic("asin(_:)"))
    }
}
