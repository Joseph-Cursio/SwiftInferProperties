import SwiftInferCore

/// The **partition** shape: a type that cuts a whole into indexed parts.
///
/// The existing catalogue is algebraic — `T -> T`, `(T, T) -> T`, encode/decode pairs — and it was
/// calibrated on libraries whose interesting surface *is* an algebra. Application code is not shaped
/// like that. The most valuable property in a file-sync client is not a semigroup; it is *the chunks
/// tile the payload exactly*, and no template in the set could say it.
///
/// The tell is one member, and there are **two ways to write it** — which took five cold walks to
/// learn, because this template originally recognised only one of them.
///
///     func byteRange(ofChunk index: Int) -> Range<Int>       // give me an index, get a RANGE
///     func chunk(of data: Data, at index: Int) -> Data       // give me the whole + an index, get a PART
///
/// Both say *the parts tile the whole*. The first names the part; the second hands it to you.
///
/// **This template used to accept only the first, and the cost was the entire point of it.** Three
/// independent readers, following the loop cold, each performed the extraction the linter demanded —
/// and all three wrote the **second** form. None of them was offered a partition law, so none of them
/// reached the unclamped-resume-counter bug the law's own caveat names. The template was keyed on the
/// signature *the reference implementation happened to use*, and the reference is the outlier.
///
/// The doc comment that shipped with it was right about the principle and wrong about the shape:
/// *"deliberately not keyed on names — the signature is the evidence."* Quite so. It was keyed on one
/// author's signature instead, which is the same mistake in a better disguise.
///
/// A progress member — `func progress(afterCompleting index: Int) -> Double` — is optional evidence,
/// and where the interesting bugs actually live: an empty whole whose progress never reaches `1.0`
/// is a hung upload bar, and a whole that over-reports is a fraction above `1.0`.
public struct PartitionShape: Sendable, Equatable {

    /// How the tiler names the part it produces. The tiling law reads differently for each, and
    /// stating the wrong one at the reader is worse than stating none.
    public enum TilerForm: Sendable, Equatable {
        /// `(Int) -> Range<Int>` — the part is a range *into* the whole. Consecutive parts must abut.
        case range

        /// `(C, Int) -> C` — the part *is* a slice of the whole. The parts must concatenate to it.
        case slice
    }

    /// The type doing the partitioning — `ChunkPlan`.
    public let typeName: String

    /// The member that maps a part index to the part. The load-bearing evidence; without it there is
    /// no partition.
    public let tiler: FunctionSummary

    /// Which of the two tiler shapes `tiler` is.
    public let tilerForm: TilerForm

    /// `(Int) -> Double`: an optional progress fraction over the same index domain.
    public let progress: FunctionSummary?

    public init(
        typeName: String,
        tiler: FunctionSummary,
        tilerForm: TilerForm = .range,
        progress: FunctionSummary?
    ) {
        self.typeName = typeName
        self.tiler = tiler
        self.tilerForm = tilerForm
        self.progress = progress
    }
}

/// Finds partition shapes among the scanned functions.
public enum PartitionPairing {

    /// Group by containing type, then look for the index → range member.
    ///
    /// Deliberately **not** keyed on names. The road-test's `ChunkPlan` calls its members
    /// `byteRange(ofChunk:)` and `progress(afterCompleting:)`, but a different author writes
    /// `slice(at:)` and `fractionDone(after:)`, and a template that keys on vocabulary would find one
    /// and miss the other. The *signature* is the evidence — a name is at best a tiebreak — which is
    /// the same lesson the effect lattice learned when it graded `createRequest` by its prefix.
    public static func candidates(in summaries: [FunctionSummary]) -> [PartitionShape] {
        var byType: [String: [FunctionSummary]] = [:]
        for summary in summaries {
            guard let type = summary.containingTypeName else { continue }
            byType[type, default: []].append(summary)
        }

        return byType.sorted { $0.key < $1.key }.compactMap { type, members in
            // A range tiler is the stronger evidence, so it wins when a type somehow has both.
            let found = members.compactMap { member -> (FunctionSummary, PartitionShape.TilerForm)? in
                guard let form = tilerForm(of: member) else { return nil }
                return (member, form)
            }
            guard let (tiler, form) = found.first(where: { $0.1 == .range }) ?? found.first else {
                return nil
            }
            return PartitionShape(
                typeName: type,
                tiler: tiler,
                tilerForm: form,
                progress: members.first(where: isProgress)
            )
        }
    }

    /// Which tiler shape this member is, if any.
    static func tilerForm(of summary: FunctionSummary) -> PartitionShape.TilerForm? {
        if isRangeTiler(summary) { return .range }
        if isSliceTiler(summary) { return .slice }
        return nil
    }

    /// Kept for callers that only need the boolean.
    static func isTiler(_ summary: FunctionSummary) -> Bool {
        tilerForm(of: summary) != nil
    }

    /// `(Int) -> Range<Int>` — one integer parameter in, a half-open integer range out.
    ///
    /// `Range<Int>` and `ClosedRange<Int>` both count; `Range<String.Index>` does not, because a
    /// tiling law over an opaque index type has no arithmetic a generator can drive.
    static func isRangeTiler(_ summary: FunctionSummary) -> Bool {
        guard let returnType = summary.returnTypeText,
              isIntegerRange(returnType),
              summary.parameters.count == 1,
              let parameter = summary.parameters.first,
              isInteger(parameter.typeText),
              !parameter.isInout else {
            return false
        }
        return true
    }

    /// `(C, Int) -> C` — hand over the whole and an index, get back a part **of the same type**.
    ///
    ///     func chunk(of data: Data, at index: Int) -> Data
    ///
    /// **The whole must be a parameter, and that is not fussiness — it is the only thing keeping this
    /// sound.** A one-parameter slice form, `func chunk(at index: Int) -> Data`, is *not* distinctive:
    /// every `item(at:) -> [Tag]` lookup in existence has that signature, and matching it would flood
    /// the reader with false partitions. Requiring the whole to appear, with the type the function
    /// returns, is what makes the claim "these are parts *of that*" legible from the signature alone —
    /// and it costs nothing, because a type that stores the whole can still be tiled by the range form.
    ///
    /// Order is not fixed: `chunk(of:at:)` and `chunk(at:in:)` are the same shape.
    ///
    /// **The integer must read as an INDEX, and this is the one place a name earns a vote.** The two
    /// tiler forms are not equally self-evident, and pretending they are ships a false law:
    ///
    ///     func byteRange(ofChunk index: Int) -> Range<Int>       // `Range<Int>` says "partition" alone
    ///     func above(_ items: [Int], threshold: Int) -> [Int]    // ← same SHAPE as a slice tiler
    ///
    /// `(C, Int) -> C` is a *filter with a scalar*, a *prefix*, a *page*, and a partition — the
    /// signature does not choose. Left uncorroborated it proposed a tiling law over `above(_:threshold:)`,
    /// which is not a partition and never tiles anything; a reader would have watched it fail for a
    /// reason that is not a bug. **A tool that proposes a false law is worse than one that proposes
    /// nothing**, and the range form needs no such tiebreak precisely because its return type already
    /// made the claim.
    static func isSliceTiler(_ summary: FunctionSummary) -> Bool {
        guard let returnType = summary.returnTypeText,
              isSliceable(returnType),
              summary.parameters.count == 2,
              summary.parameters.allSatisfy({ !$0.isInout })
        else { return false }

        let whole = summary.parameters.first { sameType($0.typeText, returnType) }
        let index = summary.parameters.first { isInteger($0.typeText) && isIndexLike($0) }

        // Distinct parameters: one must not answer for both roles.
        guard let whole, let index, whole.internalName != index.internalName else { return false }
        return true
    }

    /// Whether this integer parameter is offered as a **position**, by either its label or its name.
    ///
    /// Deliberately narrow. `threshold`, `count`, `limit` and `size` are all integers that are *not*
    /// ordinals, and admitting them is how the tiling law ends up pointed at a filter.
    private static func isIndexLike(_ parameter: Parameter) -> Bool {
        let candidates = [parameter.label, parameter.internalName]
            .compactMap { $0?.lowercased() }
        return candidates.contains { name in
            Self.indexNames.contains(name) || name.hasSuffix("index") || name.hasPrefix("index")
        }
    }

    /// The vocabulary of "which one" — an ordinal, not a quantity.
    private static let indexNames: Set<String> = [
        "index", "idx", "at", "ofchunk", "chunk", "part", "position", "ordinal", "nth", "i", "n"
    ]

    /// A type whose values are sequences that can be cut and rejoined, so *"the parts concatenate to
    /// the whole"* is a statement a generator can attack.
    ///
    /// An `Array` and an `ArraySlice` of anything qualify; so do `Data`, `String` and `Substring`. A
    /// `Set` does not — concatenation is not defined on it, and neither is a part's *position*.
    private static func isSliceable(_ text: String) -> Bool {
        let bare = text.trimmingCharacters(in: .whitespaces)
        if ["Data", "String", "Substring"].contains(bare) { return true }
        if bare.hasPrefix("["), bare.hasSuffix("]"), !bare.contains(":") { return true }
        return bare.hasPrefix("ArraySlice<") || bare.hasPrefix("ContiguousArray<")
    }

    private static func sameType(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespaces) == rhs.trimmingCharacters(in: .whitespaces)
    }

    /// `(Int) -> Double` — the progress fraction over the same index domain.
    static func isProgress(_ summary: FunctionSummary) -> Bool {
        guard let returnType = summary.returnTypeText,
              isFraction(returnType),
              summary.parameters.count == 1,
              let parameter = summary.parameters.first,
              isInteger(parameter.typeText) else {
            return false
        }
        return true
    }

    private static func isIntegerRange(_ text: String) -> Bool {
        let bare = text.trimmingCharacters(in: .whitespaces)
        return bare == "Range<Int>" || bare == "ClosedRange<Int>"
    }

    private static func isInteger(_ text: String) -> Bool {
        ["Int", "Int64", "Int32", "UInt", "UInt64"].contains(text.trimmingCharacters(in: .whitespaces))
    }

    private static func isFraction(_ text: String) -> Bool {
        ["Double", "Float"].contains(text.trimmingCharacters(in: .whitespaces))
    }
}
