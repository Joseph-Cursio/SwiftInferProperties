import Foundation
import SwiftInferCore

/// Recognises a **family of scaled unit constructors** on one carrier, and the
/// consistency law between adjacent members of it.
///
///     T.seconds(n) == T.milliseconds(n * 1_000)
///
/// ## The witnesses
///
/// Rows 8–11 of `fixtures/swiftorg-study/loops-answer-key.json` — `test/stdlib/Duration.swift`
/// checks `Duration.milliseconds(v).components` against `(v / 1000, v % 1000 * 1e15)` and
/// three siblings at other scales.
///
/// ## Why the law is stated between CONSTRUCTORS, not against `components`
///
/// The witness's own form needs two pieces of carrier-specific knowledge: the scale
/// factor *and* the internal decomposition (`Duration` splits into seconds and
/// attoseconds; nothing else does). The second is not inferable and would make this a
/// one-carrier template.
///
/// Relating two constructors needs only the **ratio**, which is definitional for time
/// units, and says nothing about how the carrier stores the value. It reaches the same
/// bug — a wrong conversion constant — without needing to know the representation.
///
/// ## Time units only, and the reason is a measured ambiguity
///
/// SI time prefixes are definitional: `milli` is 1/1000 of a second and no type may
/// reinterpret it, the same standard `ModelLawPairing.SetOperation` applies to `union`.
///
/// **Byte prefixes are not.** `kilobytes` means 1000 in some types and 1024 in others,
/// and both are defensible. swift-nio's `ByteCount` — found by the population sweep with
/// a full `bytes`/`kilobytes`/`megabytes`/`gigabytes` family — uses `1000 * count`. A
/// template asserting either ratio would be flatly wrong for half the ecosystem, so the
/// byte family is excluded and the 1000-vs-1024 split is the reason.
///
/// That exclusion costs one of the three carriers the sweep found.
public enum ScaledUnitPairing {

    /// Time units and their size in nanoseconds. Integers, so the ratio between any two
    /// members is exact and no floating-point rounding enters the law.
    ///
    /// Deliberately stops at `hours`. `days` and `weeks` are calendar units, and a type
    /// that models calendars rather than durations may make a day something other than
    /// 86,400 seconds — which is exactly the reinterpretation this table must not permit.
    public static let nanosecondsPerUnit: [String: Int64] = [
        "nanoseconds": 1,
        "microseconds": 1_000,
        "milliseconds": 1_000_000,
        "seconds": 1_000_000_000,
        "minutes": 60_000_000_000,
        "hours": 3_600_000_000_000
    ]

    /// One statable consistency law between two units of the same family.
    public struct ScaledUnitShape: Sendable, Equatable {

        /// The carrier, generic parameters stripped — `Duration`.
        public let typeName: String

        /// The coarser constructor — `seconds`.
        public let larger: FunctionSummary

        /// The finer one — `milliseconds`.
        public let smaller: FunctionSummary

        /// How many of the finer unit make one of the coarser — `1_000`.
        public let ratio: Int64

        /// How many curated units the carrier exposes in total. A type with four is
        /// unmistakably a unit family; two might be a coincidence of naming.
        public let familySize: Int

        public init(
            typeName: String,
            larger: FunctionSummary,
            smaller: FunctionSummary,
            ratio: Int64,
            familySize: Int
        ) {
            self.typeName = typeName
            self.larger = larger
            self.smaller = smaller
            self.ratio = ratio
            self.familySize = familySize
        }

        /// The law, as Swift.
        public var lawText: String {
            "\(typeName).\(larger.name)(n) == \(typeName).\(smaller.name)(n * \(ratio))"
        }
    }

    /// Every adjacent-pair consistency law statable from `summaries`.
    ///
    /// **Adjacent pairs only**, not every pair. Two reasons, and the second is the one
    /// that matters: a family of six would otherwise produce fifteen rows saying much the
    /// same thing, and the non-adjacent ratios are the large ones — `hours` to
    /// `nanoseconds` is 3.6e12, so the multiplication overflows for almost any input a
    /// generator would draw, and the law would be reporting a domain limit rather than a
    /// defect.
    public static func candidates(in summaries: [FunctionSummary]) -> [ScaledUnitShape] {
        var byCarrier: [String: [String: FunctionSummary]] = [:]
        for summary in summaries where nanosecondsPerUnit[summary.name] != nil {
            guard summary.isStatic,
                  !summary.isMutating, !summary.isThrows, !summary.isAsync,
                  summary.parameters.count == 1,
                  summary.parameters.first?.isInout == false,
                  let carrier = summary.containingTypeName,
                  let returnType = summary.returnTypeText else { continue }
            // A scaled CONSTRUCTOR returns the carrier. An accessor of the same name
            // returning `Int64` is the decomposition, not the construction.
            guard returnType == "Self" || stripGenerics(returnType) == stripGenerics(carrier) else {
                continue
            }
            // First declaration wins, so overloads do not multiply the rows.
            let key = stripGenerics(carrier)
            if byCarrier[key, default: [:]][summary.name] == nil {
                byCarrier[key, default: [:]][summary.name] = summary
            }
        }

        var result: [ScaledUnitShape] = []
        for (carrier, units) in byCarrier.sorted(by: { $0.key < $1.key }) where units.count >= 2 {
            let ordered = units.keys
                .compactMap { name in nanosecondsPerUnit[name].map { (name, $0) } }
                .sorted { $0.1 < $1.1 }
            for index in 1 ..< ordered.count {
                let (smallerName, smallerScale) = ordered[index - 1]
                let (largerName, largerScale) = ordered[index]
                guard let smaller = units[smallerName], let larger = units[largerName],
                      smallerScale > 0, largerScale.isMultiple(of: smallerScale) else { continue }
                result.append(ScaledUnitShape(
                    typeName: carrier,
                    larger: larger,
                    smaller: smaller,
                    ratio: largerScale / smallerScale,
                    familySize: units.count
                ))
            }
        }
        return result
    }

    static func stripGenerics(_ typeText: String) -> String {
        let trimmed = typeText.trimmingCharacters(in: .whitespaces)
        guard let angle = trimmed.firstIndex(of: "<") else { return trimmed }
        return String(trimmed[trimmed.startIndex..<angle])
    }
}
