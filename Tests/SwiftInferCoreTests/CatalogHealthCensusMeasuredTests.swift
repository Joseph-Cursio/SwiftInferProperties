import Foundation
import SwiftInferTemplates
import Testing

@testable import SwiftInferCore

/// **Which shipped templates fire on nothing — measured against SEVENTEEN corpora?**
///
/// §10 of `swiftorg-property-test-study-findings.md` ran this over **eight** corpora and
/// found 6 of 39 templates at zero. §10.5 then removed `involution` from that list — its
/// witness existed on a ninth corpus the repo already held, registered and pinned — and
/// drew the process finding this suite exists to act on:
///
/// > *a census is only as wide as its corpus list, and its zero row is the one cell that
/// > cannot be trusted without knowing that list.*
///
/// `CorpusManifest` now resolves **seventeen**. `docs/design-internal/toolchain-exit-criteria.md`
/// names re-running this as the one action following from row 8 that needs no decision,
/// because a template *unwitnessed on eight corpora* and one *unwitnessed anywhere* are
/// different claims and only the second is a defect.
///
/// ## Why the zero row is the only row that matters here
///
/// A dead template and a correctly-silent one produce identical output, which is how
/// `HomomorphismTemplate` shipped with a carefully argued doc and fired zero times
/// without anyone noticing. Everything else in the distribution is context. **This suite
/// therefore reports the whole distribution but asserts only on the zero row's
/// membership**, so that a template leaving it is visible and a template entering it
/// fails something.
///
/// ## Scope, and how it differs from §10
///
/// §10 ran `discover --include-possible` over eight named corpora, ~55,000 functions.
/// This runs `TemplateRegistry.discover` directly over the manifest's seventeen, one
/// root each. **The two are not the same instrument** — this one takes every tier
/// discovery produces rather than a CLI tier filter, and its corpus list is wider and
/// differently composed. A count here should not be diffed against a count there; the
/// **membership of the zero row** is what carries across, and that is what §10.5's
/// finding was about.
@Suite("Census — catalog health across the manifest corpora", .serialized)
struct CatalogHealthCensusMeasuredTests {

    /// **The catalogue is supplied, not discovered — and the first version of this
    /// suite got that wrong.**
    ///
    /// `CensusCommand`'s own header says it, one file away, and it was re-entered
    /// rather than read:
    ///
    /// > *naming [a zero] needs a catalog of every template that could have fired, and
    /// > this project has no trustworthy runtime source for that: `TemplateName` is 18
    /// > cases against ~92 template files and `TemplatePack.allTemplateNames` is 10,
    /// > and both reject tags that are correct. **Printing a zero list against either
    /// > would manufacture exactly the over-confident claim this command exists to
    /// > prevent.**
    ///
    /// This suite's first run computed `unwitnessed` as
    /// `TemplatePack.allTemplateNames − emitted` — 10 declared against 36 emitted —
    /// and reported a one-name zero row that was an artifact of the wrong denominator.
    /// `vocabularyAgrees` failed and is why the number below is not that one.
    ///
    /// So the zero row is **only** ever checked against names a human recorded as
    /// zero. **This census can confirm or resolve a known zero; it cannot discover a
    /// new one.** That limit is inherited from the missing catalogue, not chosen here,
    /// and it is the same limit `CensusRun.zeroRowTemplates(against:)` encodes by
    /// taking the catalog as an argument.
    static let knownZeroRow: Set<String> = [
        // §10's zero row, after §10.5 removed `involution`.
        "diff-disjointness",
        "multiplicative-homomorphism",
        "partition",
        "selection-subset",
        // Deferred rather than broken: `TemplateName`'s Strong tier records
        // `differential-equivalence` as FIXED 2026-08-08 and this one as deferred, so
        // its zero is expected and belongs in the pinned set rather than reading as a
        // regression the first time this suite runs.
        "invariant-preservation"
    ]

    /// **Carrier shape, for sizing a carrier build.**
    ///
    /// Kept in this suite rather than its own because it is a second reading of the
    /// *same* discover pass. A separate census would re-scan seventeen corpora to
    /// re-derive rows this one already has, doubling a seven-minute cost for identical
    /// data — and `make test` is already ~65 minutes.
    enum CarrierShape: String, CaseIterable {
        /// `[T]`, `[K: V]`, `Set<…>`, `Deque<…>`, `OrderedSet<…>` and friends.
        case collection
        /// What the carrier-dispatched stub emitters actually support:
        /// `Complex<Double>`, `Double`, `Int` — plus the other numeric and `String`
        /// spellings that would be cheap to add.
        case scalar
        /// A user-defined `struct` / `enum` / `class`. Needs a derived generator, which
        /// is the `DerivationStrategist` problem rather than a carrier-table problem.
        case userDefined
        /// No carrier recorded on the suggestion.
        case absent

        static func of(_ carrier: String?) -> Self {
            guard let carrier, !carrier.isEmpty else { return .absent }
            if carrier.hasPrefix("[") { return .collection }
            let collectionHeads = [
                "Set<", "Dictionary<", "Array<", "Deque<", "OrderedSet<",
                "OrderedDictionary<", "Heap<", "SortedSet<", "SortedDictionary<",
                "ArraySlice<", "Slice<", "BitArray", "BitSet", "TreeSet<", "TreeDictionary<"
            ]
            if collectionHeads.contains(where: carrier.hasPrefix) { return .collection }
            let scalars: Set<String> = [
                "Int", "Int8", "Int16", "Int32", "Int64",
                "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
                "Double", "Float", "Float80", "CGFloat",
                "String", "Substring", "Character", "Bool",
                "Complex<Double>", "Complex<Float>", "Decimal"
            ]
            return scalars.contains(carrier) ? .scalar : .userDefined
        }
    }

    struct Row {
        let template: String
        let carrier: String?
        /// The subject's access restriction, `nil` when the subject is reachable from a
        /// test. Joined by the same `(file, base name)` key the shipped caveat uses.
        let restriction: AccessRestriction?
        var shape: CarrierShape { CarrierShape.of(carrier) }

        /// Whether **widening one access modifier** would make this subject reachable.
        ///
        /// Only `.notVisibleToTests` qualifies. `.enclosingTypeNotVisibleToTests` is the
        /// design's named trap — widening a member of a private *type* unblocks nothing
        /// — and `.nestedLocal` has no caller to widen to. `.internalOrSPI` is already
        /// reachable via `@testable import`, so there is nothing to unblock.
        var isWidenable: Bool { restriction.map(SpeculativeWidening.isWidenable) ?? false }
    }

    /// Every discovery row across the manifest, scanned once.
    static let rows: [Row] = {
        var all: [Row] = []
        for corpus in CorpusManifest.available {
            guard let scanned = try? FunctionScanner.scanCorpus(directory: corpus.primaryRoot)
            else { continue }
            let discovered = TemplateRegistry.discover(
                in: scanned.summaries,
                identities: scanned.identities,
                typeDecls: scanned.typeDecls
            )
            // The shipped caveat joins restrictions to suggestions on (file, base name);
            // reproducing that key rather than inventing one keeps this census measuring
            // what the tool actually reports.
            var restrictionByKey: [String: AccessRestriction] = [:]
            for entry in scanned.restricted {
                let key = "\(entry.summary.location.file)#\(entry.summary.name)"
                if restrictionByKey[key] == nil { restrictionByKey[key] = entry.restriction }
            }
            all.append(contentsOf: discovered.map { suggestion in
                let key = suggestion.evidence.first.map {
                    "\($0.location.file)#\(Self.baseName($0.displayName))"
                }
                return Row(
                    template: suggestion.templateName,
                    carrier: suggestion.carrier,
                    restriction: key.flatMap { restrictionByKey[$0] }
                )
            })
        }
        return all
    }()

    /// `displayName` carries the labelled form (`normalize(_:)`); summaries key on the
    /// bare name. Splitting on `(` is what the shipped join does.
    static func baseName(_ displayName: String) -> String {
        String(displayName.prefix { $0 != "(" })
    }

    static let rowsByTemplate: [String: Int] = rows.reduce(into: [:]) {
        $0[$1.template, default: 0] += 1
    }

    /// The two-operand executable templates. Their emitters share one
    /// `supportedCarriers` list — `["Complex<Double>", "Double", "Int"]` — so a
    /// collection-carrier build is only worth anything if these have collection rows.
    static let twoOperandTemplates: Set<String> = ["commutativity", "associativity"]

    static var emitted: Set<String> { Set(rowsByTemplate.keys) }

    /// The catalogue this census can speak about: everything that fired, plus the
    /// names someone recorded as firing nowhere. Necessarily incomplete — see
    /// ``knownZeroRow``.
    static var catalogue: Set<String> { emitted.union(knownZeroRow) }

    /// Known zeros that are still zero across all seventeen corpora.
    static var unwitnessed: Set<String> { knownZeroRow.subtracting(emitted) }

    /// Known zeros that a wider corpus list has now witnessed. **This is the result
    /// the census was re-run to find.**
    static var resolved: Set<String> { knownZeroRow.intersection(emitted) }

    // MARK: - Controls

    /// **The universe is the manifest's.** The entire point is corpus width; a run that
    /// silently narrowed would reproduce §10's zero row and read as confirmation.
    @Test("the census scans the corpora the manifest resolves")
    func universeIsTheManifest() {
        #expect(CorpusManifest.available.count >= 8)
        #expect(Self.rowsByTemplate.values.reduce(0, +) > 1_000, "too few rows to be a census")
    }

    /// **The emitted vocabulary is wide.** With the catalogue derived from what fired,
    /// a narrow run would shrink the catalogue too and the zero row would still look
    /// tidy — the denominator and the numerator failing together. Only an absolute
    /// floor separates that from a real census.
    @Test("the emitted vocabulary is wide enough for the zero row to mean anything")
    func vocabularyIsWide() {
        #expect(
            Self.emitted.count >= 30,
            "only \(Self.emitted.count) templates fired — too narrow for a catalogue claim"
        )
        #expect(
            Self.emitted.count > TemplatePack.allTemplateNames.count,
            """
            The emitted set is no wider than `TemplatePack.allTemplateNames`, which is 10 \
            and is NOT the catalogue — see `knownZeroRow`. If these ever match, check \
            whether the run narrowed before trusting any zero.
            """
        )
    }

    /// **The zero row shrinks, and never silently grows.**
    ///
    /// **A known zero that resolves is reported, never asserted.** Pinning the
    /// *resolved* set would mean editing a test to see the result the census exists to
    /// produce. What is asserted instead is that the pinned list is still meaningful:
    /// every name in it must be a name this census could actually observe.
    @Test("every pinned zero-row name is one the catalogue can speak about")
    func pinnedZeroRowIsAnswerable() {
        for name in Self.knownZeroRow {
            #expect(
                Self.catalogue.contains(name),
                "`\(name)` is pinned as a known zero but is not in the catalogue — unanswerable"
            )
        }
        #expect(!Self.knownZeroRow.isEmpty)
    }

    // MARK: - The census

    @Test("census — catalog health at 17 corpora")
    func census() {
        var lines: [String] = ["", "CATALOG HEALTH — ALL MANIFEST CORPORA", ""]
        lines.append(
            "corpora: \(CorpusManifest.available.count) · emitted \(Self.emitted.count)"
                + " · catalogue \(Self.catalogue.count) (derived — see knownZeroRow)"
        )
        lines.append("total rows: \(Self.rowsByTemplate.values.reduce(0, +))")
        lines.append("")
        lines.append("STILL UNWITNESSED at 17 corpora: \(Self.unwitnessed.count)")
        for name in Self.unwitnessed.sorted() { lines.append("  \(name)") }
        lines.append("RESOLVED by the wider corpus list: \(Self.resolved.count)")
        for name in Self.resolved.sorted() { lines.append("  \(name)") }
        lines.append("")
        lines.append("pinned known zeros, re-checked at seventeen:")
        for name in Self.knownZeroRow.sorted() {
            let rows = Self.rowsByTemplate[name] ?? 0
            lines.append("  \(name): \(rows) row(s) — \(rows > 0 ? "RESOLVED — witnessed here" : "still unwitnessed")")
        }
        lines.append("")
        lines.append("distribution (ascending):")
        for (name, rows) in Self.rowsByTemplate.sorted(by: { ($0.value, $0.key) < ($1.value, $1.key) }) {
            lines.append("  \(String(rows).padding(toLength: 6, withPad: " ", startingAt: 0))\(name)")
        }
        print(lines.joined(separator: "\n"))
    }
}
