import Foundation

/// Why an `architecturalCoveragePending` record did not run — read back off the `detail`
/// string the verify path wrote.
///
/// ## The defect this closes
///
/// `report` printed one tip under the Unverifiable count:
///
/// > *an Unverifiable pick means the strategist has no generator for its carrier. Add
/// > `static func gen() -> Gen<T>` for that type in your target …*
///
/// Measured on `SwiftFormatRuleStudioCore` (`docs/measurements/exploratory-swiftformatrulestudio.md`
/// §5.1), the 18 Unverifiable records split **9 `unsupported-template`, 6 subject-not-visible,
/// 2 instance-method-shape, 1 `unsupported-carrier`**. The advice addressed the cause behind
/// **one row of eighteen**, and the fix it prescribed would move nothing else — a reader who
/// followed it would write a `gen()` and watch the number not change.
///
/// This is the glossary's own standing warning, shipped as user-facing guidance:
/// *"`unsupported-carrier` is nearly always the wrong suspect. It reads like the obvious
/// bottleneck and measures at ~4%. Reading that constant and believing it produced a wrong
/// plan once already."* The same mistake, one layer out — and this time told to the user.
///
/// ## Reading a string, and the cost of that
///
/// `VerifyEvidenceRecord.detail` is documented as *"short human-readable detail"*, and this
/// parses it. That is a real coupling: the producers
/// (`VerifyCommand+AllFromIndexRecords`, `VerifyCommand+ArchitecturalPendingDetail`) can
/// change a prefix and silently reclassify everything to `.unrecognised`.
///
/// **It is chosen over threading a structured cause through the evidence format** because the
/// format is persisted: adding a field means every record written before today has it absent,
/// so the reader needs a string fallback regardless. Better one parser than a parser plus a
/// migration. `UnverifiableCauseTests` pins each prefix against the constant that writes it,
/// so a producer that renames one fails there rather than degrading a user-facing count.
///
/// ## Unrecognised is a case, not a default
///
/// A detail this enum does not recognise becomes `.unrecognised` and is **reported as such**,
/// never folded into the largest bucket or dropped from the total. Silently bucketing an
/// unknown cause under a known one is how the original defect read as true: a confident
/// attribution is worse than an admitted gap, because only the second prompts a look.
public enum UnverifiableCause: String, Sendable, Equatable, CaseIterable {

    /// No composer exists for the template. The law was proposed, scored and shown; nothing
    /// can run it. **Not the reader's to fix** — this is a gap in swift-infer.
    case unsupportedTemplate

    /// The carrier type resolves to no generator. The `gen()` hook is the remedy, and this is
    /// the *only* cause it addresses.
    case unsupportedCarrier

    /// A two-function template's pairing did not resolve.
    case unsupportedPair

    /// The subject is `private`/`fileprivate`, so no test can name it — not even under
    /// `@testable`. One keyword, and it is the reader's to change.
    case subjectNotVisible

    /// The instance-method shape is not one the emitter can call.
    case instanceMethodShape

    /// `a ≤ b ⟹ f(a) ≤ f(b)` needs an ordered domain and this one is not.
    case monotonicityDomainNotComparable

    /// The detail did not match any known prefix — or there was none. Reported, never merged.
    case unrecognised

    /// Classify one record's `detail`.
    ///
    /// Prefix-matched rather than equality-matched: most details carry a payload after the
    /// category (`"unsupported-carrier: ConfigModel"`), and the payload is the part that
    /// varies per row.
    public static func classify(detail: String?) -> Self {
        guard let detail else { return .unrecognised }
        // Order matters only in that `unsupported-pair` must not be reached by a prefix of
        // `unsupported-template`; they share no prefix, so this is a plain first-match.
        for (prefix, cause) in prefixes where detail.hasPrefix(prefix) {
            return cause
        }
        return .unrecognised
    }

    /// The `detail` prefixes each cause is written with, paired with the cause.
    ///
    /// An array rather than a dictionary so the match order is stated rather than incidental.
    static let prefixes: [(String, Self)] = [
        ("unsupported-template", .unsupportedTemplate),
        ("unsupported-carrier", .unsupportedCarrier),
        ("unsupported-pair", .unsupportedPair),
        ("not-a-candidate", .subjectNotVisible),
        ("instance-method-shape-not-supported", .instanceMethodShape),
        ("monotonicity-domain-not-comparable", .monotonicityDomainNotComparable)
    ]

    /// Short label for a count breakdown.
    public var label: String {
        switch self {
        case .unsupportedTemplate: "no composer for the template"
        case .unsupportedCarrier: "no generator for the carrier"
        case .unsupportedPair: "pairing unresolved"
        case .subjectNotVisible: "subject not visible to tests"
        case .instanceMethodShape: "instance-method shape"
        case .monotonicityDomainNotComparable: "domain not ordered"
        case .unrecognised: "unrecognised"
        }
    }

    /// What the reader can actually do — or an honest statement that they cannot.
    ///
    /// **Two of these say the reader cannot fix it, and that is the point.** The tip this
    /// replaces implied every Unverifiable row was one `gen()` away. Naming a tool gap as a
    /// tool gap is more useful than prescribing work that will not move the number.
    public var remedy: String {
        switch self {
        case .unsupportedTemplate:
            "no composer exists for that template, so nothing can run the law — a gap in "
                + "swift-infer, not in your code. Nothing you write unblocks these."

        case .unsupportedCarrier:
            "add `static func gen() -> Gen<T>` for that carrier in your target — a same-file "
                + "extension works even for external types "
                + "(e.g. `extension BigUInt { static func gen() … }`)."

        case .unsupportedPair:
            "the template needs a second function and could not resolve it; check both halves "
                + "are declared on the same type."

        case .subjectNotVisible:
            "the subject is `private`/`fileprivate`, so no test can call it — not even with "
                + "`@testable import`. Widen it to `internal`, or lift the logic into a type "
                + "of its own."

        case .instanceMethodShape:
            "the emitter cannot call that instance-method shape — a gap in swift-infer, not "
                + "in your code."

        case .monotonicityDomainNotComparable:
            "`a ≤ b ⟹ f(a) ≤ f(b)` needs an ordered domain, and this carrier has none."

        case .unrecognised:
            "no category was recorded — run `swift-infer query` for the row's own detail."
        }
    }
}
