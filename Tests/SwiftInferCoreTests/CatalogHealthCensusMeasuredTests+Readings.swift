import Foundation
import SwiftInferTemplates
import Testing

@testable import SwiftInferCore

/// **The secondary readings of `CatalogHealthCensusMeasuredTests`' single scan.**
///
/// Carrier shape, visibility/widenability and the validity-predicate pairing all read the
/// *same* discover pass over the 17 corpora that suite already performs. They live in an
/// extension rather than their own suites because a separate census would re-scan
/// seventeen corpora to re-derive identical rows — doubling a seven-minute cost against a
/// ~65-minute gate — and in their own FILE because four censuses in one file crossed
/// SwiftLint's type-body and file-length caps.
extension CatalogHealthCensusMeasuredTests {

    /// **Sizes the collection-carrier build.** `docs/measurements/result-carrier-reach.md`
    /// and the pairing fixture both end at the same blocker: the carrier-dispatched
    /// emitters accept only `Complex<Double>` / `Double` / `Int`. The home corpus's
    /// survey shows **0 of 47** `unsupported-carrier` declines are collection-shaped —
    /// but that repo analyses syntax and its types are structs, so the zero must not be
    /// carried. This is the cross-corpus reading.
    @Test("census — carrier shape across the manifest, and the two-operand slice")
    func carrierShapeCensus() {
        var lines: [String] = ["", "CARRIER SHAPE — ALL MANIFEST CORPORA", ""]
        var byShape: [CarrierShape: Int] = [:]
        for row in Self.rows { byShape[row.shape, default: 0] += 1 }
        lines.append("all \(Self.rows.count) discovery rows:")
        for shape in CarrierShape.allCases {
            let count = byShape[shape] ?? 0
            let percent = Self.rows.isEmpty ? 0 : count * 100 / Self.rows.count
            let label = shape.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)
            lines.append("  \(label)\(count) (\(percent)%)")
        }

        let twoOperand = Self.rows.filter { Self.twoOperandTemplates.contains($0.template) }
        lines.append("")
        lines.append("two-operand templates (commutativity + associativity): \(twoOperand.count) rows")
        var twoByShape: [CarrierShape: Int] = [:]
        for row in twoOperand { twoByShape[row.shape, default: 0] += 1 }
        for shape in CarrierShape.allCases {
            let label = shape.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)
            lines.append("  \(label)\(twoByShape[shape] ?? 0)")
        }
        lines.append("")
        lines.append("collection carriers seen, by name:")
        let names = Self.rows.filter { $0.shape == .collection }.compactMap(\.carrier)
        let grouped = Dictionary(grouping: names) { $0 }.mapValues(\.count)
        let ranked = grouped.sorted { ($0.value, $0.key) > ($1.value, $1.key) }
        for (name, count) in ranked.prefix(20) {
            lines.append("  \(count)  \(name)")
        }
        print(lines.joined(separator: "\n"))
    }

    /// **How many rows are blocked by visibility, and how many of those would ONE
    /// widened access modifier free?**
    ///
    /// The home survey put visibility at **204 of 344 declines (59%)** and showed five
    /// templates — `value-round-trip`, `comparator`, `round-trip`, `input-totality`,
    /// `monotonicity` — existing *entirely* behind the wall while what ran was 87%
    /// `predicate` + `idempotence`. That was one corpus, from a syntax tool whose small
    /// pure functions are nearly all `private` helpers. This is the cross-corpus reading.
    ///
    /// **Widenable is not the same as blocked.** `SpeculativeWidening.isWidenable`
    /// admits only `.notVisibleToTests`; a member of a private *type* cannot be freed by
    /// widening the member, which is that design's named trap.
    @Test("census — visibility blocking and widenability across the manifest")
    func visibilityCensus() {
        let blocked = Self.rows.filter { $0.restriction != nil }
        let widenable = blocked.filter(\.isWidenable)
        var lines: [String] = ["", "VISIBILITY — ALL MANIFEST CORPORA", ""]
        let blockedShare = Self.rows.isEmpty ? 0 : blocked.count * 100 / Self.rows.count
        lines.append("rows \(Self.rows.count) · restricted subject \(blocked.count) (\(blockedShare)%)")
        let widenShare = blocked.isEmpty ? 0 : widenable.count * 100 / blocked.count
        lines.append("of those, ONE widened modifier would free \(widenable.count) (\(widenShare)%)")
        lines.append("")
        lines.append("restriction reasons:")
        var byReason: [String: Int] = [:]
        for row in blocked { byReason[String(describing: row.restriction!), default: 0] += 1 }
        for (reason, count) in byReason.sorted(by: { $0.value > $1.value }) {
            lines.append("  \(count)  \(reason)")
        }
        lines.append("")
        lines.append("template                        blocked  widenable  reachable")
        var templates = Set(Self.rows.map(\.template)).sorted()
        templates = templates.filter { name in Self.rows.contains { $0.template == name } }
        for name in templates {
            let rows = Self.rows.filter { $0.template == name }
            let blockedHere = rows.filter { $0.restriction != nil }
            guard !blockedHere.isEmpty else { continue }
            lines.append(
                name.padding(toLength: 32, withPad: " ", startingAt: 0)
                    + String(blockedHere.count).padding(toLength: 9, withPad: " ", startingAt: 0)
                    + String(blockedHere.filter(\.isWidenable).count)
                        .padding(toLength: 11, withPad: " ", startingAt: 0)
                    + String(rows.count - blockedHere.count)
            )
        }
        print(lines.joined(separator: "\n"))
    }

    /// **How many types declare BOTH a validity predicate and a same-type normaliser?**
    ///
    /// `fixtures/branch-reaching-generator/`'s law comparison measured that on a
    /// legalise-shaped subject the **postcondition** `isValid(f(x))` refutes **4 of 4**
    /// real bugs while **idempotence refutes 1 of 4** — and the tool emitted the
    /// idempotence law. On `swift-http-types`, `HTTPField` declares `isValidValue`
    /// immediately above `legalizeValue`, so the predicate the strong law needs was in
    /// the same file.
    ///
    /// **This is the population question, asked before the template is built.**
    /// `cross-type-roundtrip` and `parameter-role` were both declined on exactly this,
    /// and both were measured after the argument rather than before it.
    ///
    /// The shape: within one containing type, a function `(T) -> Bool` and a function
    /// `(T) -> T` over the same `T`. Name relation is reported separately rather than
    /// required, because requiring it is the assumption a census should test — and
    /// `purity-refuting-fixpoint-census.md` measured name-matching at **61% false**.
    struct Pair {
        let container: String
        let predicate: String
        let normaliser: String
        let type: String
    }

    /// The scan, split from the report only for the 50-line body cap.
    static func normaliserPairs() -> (pairs: [Pair], containers: Int) {
        var pairs: [Pair] = []
        var containersScanned = 0

        for corpus in CorpusManifest.available {
            guard let scanned = try? FunctionScanner.scanCorpus(directory: corpus.primaryRoot)
            else { continue }
            let byContainer = Dictionary(grouping: scanned.summaries) { $0.containingTypeName ?? "" }
            for (container, members) in byContainer where !container.isEmpty {
                containersScanned += 1
                // `(T) -> Bool`, one parameter.
                let predicates = members.filter {
                    $0.returnTypeText == "Bool" && $0.parameters.count == 1
                }
                // `(T) -> T`, one parameter, same type in and out.
                let normalisers = members.filter {
                    $0.parameters.count == 1
                        && $0.returnTypeText != nil
                        && $0.returnTypeText == $0.parameters[0].typeText
                }
                for predicate in predicates {
                    let subject = predicate.parameters[0].typeText
                    // **Exclude binary operations on the container itself.** `isDisjoint(BitSet)
                    // -> Bool` beside `union(BitSet) -> BitSet` matches the shape exactly, and
                    // the parameter is the OTHER OPERAND rather than a value being validated.
                    // For every `Set`-like type each predicate pairs with each operation, which
                    // is what dominated this census's first run: 449 raw pairs, and the sample's
                    // first twenty were all index arithmetic and set algebra. The motivating case
                    // has parameter `ISOLatin1String` against container `HTTPField` — different
                    // types — so requiring that costs nothing and removes the whole false class.
                    guard subject != container, !subject.hasPrefix(container + ".") else { continue }
                    for normaliser in normalisers where normaliser.parameters[0].typeText == subject {
                        pairs.append(
                            Pair(
                                container: "\(corpus.id):\(container)",
                                predicate: predicate.name,
                                normaliser: normaliser.name,
                                type: subject
                            )
                        )
                    }
                }
            }
        }

        return (pairs, containersScanned)
    }

    @Test("census — validity-predicate / normaliser pairs across the manifest")
    func normaliserPairCensus() {
        let (pairs, containersScanned) = Self.normaliserPairs()

        // **A shared trailing noun**, reported and NOT required. `isValidValue` and
        // `legalizeValue` both end in `Value`; the first version of this stripped known
        // verb prefixes instead and produced `validvalue` against `value`, so **the
        // motivating example itself would not have counted** — an instrument that cannot
        // see the case it was built for. Caught by reading the sample rows.
        func trailingNoun(_ name: String) -> String? {
            var words: [String] = []
            var current = ""
            for character in name {
                if character.isUppercase, !current.isEmpty { words.append(current); current = "" }
                current.append(character)
            }
            if !current.isEmpty { words.append(current) }
            guard let last = words.last, last.count >= 3 else { return nil }
            return last.lowercased()
        }
        let named = pairs.filter {
            guard let left = trailingNoun($0.predicate), let right = trailingNoun($0.normaliser)
            else { return false }
            return left == right
        }

        var lines: [String] = ["", "VALIDITY-PREDICATE / NORMALISER PAIRS — ALL MANIFEST CORPORA", ""]
        lines.append("containers scanned: \(containersScanned)")
        lines.append("pairs (T)->Bool alongside (T)->T in one type: \(pairs.count)")
        lines.append("of those, sharing a trailing noun: \(named.count)")
        for pair in named.prefix(12) {
            lines.append("    NAMED \(pair.container): \(pair.predicate) / \(pair.normaliser)")
        }
        lines.append("")
        lines.append("sample (first 20 by container):")
        for pair in pairs.sorted(by: { $0.container < $1.container }).prefix(20) {
            lines.append("  \(pair.container): \(pair.predicate) / \(pair.normaliser)  [\(pair.type)]")
        }
        print(lines.joined(separator: "\n"))
    }
}
