import SwiftInferCore

/// The **partition** shape: a type that cuts a whole into indexed parts.
///
/// The existing catalogue is algebraic — `T -> T`, `(T, T) -> T`, encode/decode pairs — and it was
/// calibrated on libraries whose interesting surface *is* an algebra. Application code is not shaped
/// like that. The most valuable property in a file-sync client is not a semigroup; it is *the chunks
/// tile the payload exactly*, and no template in the set could say it.
///
/// The tell is one member, and it is unusually distinctive:
///
///     func byteRange(ofChunk index: Int) -> Range<Int>
///
/// **Give me an index, get a range.** That is a partition, and essentially nothing else has that
/// signature by accident. A type with such a member is claiming that its parts *tile* something —
/// a claim with real content, which a generator can attack and an implementation can get wrong.
///
/// A progress member — `func progress(afterCompleting index: Int) -> Double` — is optional evidence,
/// and where the interesting bugs actually live: an empty whole whose progress never reaches `1.0`
/// is a hung upload bar, and a whole that over-reports is a fraction above `1.0`.
public struct PartitionShape: Sendable, Equatable {

    /// The type doing the partitioning — `ChunkPlan`.
    public let typeName: String

    /// `(Int) -> Range<Int>`: the member that maps a part index to the slice of the whole it covers.
    /// The load-bearing evidence; without it there is no partition.
    public let tiler: FunctionSummary

    /// `(Int) -> Double`: an optional progress fraction over the same index domain.
    public let progress: FunctionSummary?

    public init(typeName: String, tiler: FunctionSummary, progress: FunctionSummary?) {
        self.typeName = typeName
        self.tiler = tiler
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
            guard let tiler = members.first(where: isTiler) else { return nil }
            return PartitionShape(
                typeName: type,
                tiler: tiler,
                progress: members.first(where: isProgress)
            )
        }
    }

    /// `(Int) -> Range<Int>` — one integer parameter in, a half-open integer range out.
    ///
    /// `Range<Int>` and `ClosedRange<Int>` both count; `Range<String.Index>` does not, because a
    /// tiling law over an opaque index type has no arithmetic a generator can drive.
    static func isTiler(_ summary: FunctionSummary) -> Bool {
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
