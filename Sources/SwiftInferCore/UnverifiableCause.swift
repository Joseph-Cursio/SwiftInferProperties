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
    ///
    /// ## The carrier remedy said `Gen<T>` until 2026-08-14, and that does not compile
    ///
    /// `Gen` is `public enum Gen<Value> {}` — an uninhabitable namespace holding static
    /// factories. Nothing can return one. The real type is
    /// `Generator<T, some SendableSequenceType>`, which is exactly what the KIT has always
    /// told people to write (`SwiftPropertyLaws/PropertyLawCore/TodoReason.swift`,
    /// `PropertyLawMacro`'s documented shape). Two tools in one toolchain gave contradictory
    /// instructions for the same task, and the wrong one was downstream.
    ///
    /// **Note what is NOT wrong: `Gen<Int>.int(in:)` in EXPRESSION position is correct** and
    /// every emitted recipe uses it (`StrategistDispatchEmitter+OCRecipes`). The defect was
    /// only ever `Gen<T>` in RETURN-TYPE position, in this one string.
    ///
    /// **Scale.** This is the most-shown remedy on unfamiliar code — 138 rows on GRDB and 18
    /// on swift-format, against 5 on this repo. It is invisible from inside, because nobody
    /// working here needs to be told how to write a generator.
    ///
    /// **Found by following it literally**, which is the one thing no test in either repo
    /// does. It is issue #256's class exactly — a refusal advertising `--extra-import`, a flag
    /// that does not exist — and #256's guard (`RefusalFlagVocabularyTests`) cannot catch it,
    /// because that asserts every `--flag` parses and this is a type name.
    /// `GenAdviceCompilesTests` closes the gap by reading the signature out of the kit.
    ///
    /// The advice also hid a real adoption cost it now states: a `gen()` returning a
    /// `Generator` needs `import PropertyBased`, so following it makes swift-property-based a
    /// dependency of the *production* target under test.
    public var remedy: String {
        switch self {
        case .unsupportedTemplate:
            "no composer exists for that template, so nothing can run the law — a gap in "
                + "swift-infer, not in your code. Nothing you write unblocks these."

        case .unsupportedCarrier:
            "add `static func gen() -> Generator<T, some SendableSequenceType>` for that "
                + "carrier — an extension works even for external types "
                + "(e.g. `extension BigUInt { static func gen() … }`). It needs "
                + "`import PropertyBased`, so the target you are testing takes "
                + "swift-property-based as a dependency."

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
