import Foundation
import Testing

/// A deferral that names the symbol which would prove it wrong.
///
/// ## Why prose could not be guarded, and this can
///
/// `docs/measurements/stale-summary-guard-declined.md` records four text-based
/// detectors for stale summaries, all refuted. The one that killed them is
/// structural: this repo corrects by **annotation, not rewriting**, so a corrected
/// doc still contains the wrong sentence and every text detector keeps firing on
/// it forever. A stale claim and its correction are lexically identical.
///
/// So the claim has to carry something that is not prose. A deferral written
///
///     Deferred kit-side: `CommutativeGroup` (falsifier: `SwiftPropertyLaws/checkCommutativeGroupPropertyLaws`).
///
/// says *"if that symbol ever exists, I am wrong"* — and that is checkable against
/// the tree rather than against another sentence. When the symbol appears, this
/// test fails and names the doc to update. Deleting the falsifier to silence it is
/// possible but conspicuous, which is the most a guard can ask.
///
/// **All three stale summaries this month would have failed here**: slice 3c's
/// deferral against `IdentifiedActionResolver.maxChildDepth`, and the taxonomy's
/// "gated on a kit-side harness" against `SwiftPropertyLaws/StatefulGuard`.
///
/// ## The convention
///
/// `(falsifier: ``Symbol``)` next to the claim. `Symbol` is either a name in this
/// repo's `Sources/`, or `Repo/Name` for a sibling checkout (`../Repo/Sources/`) —
/// the same repo-in-the-path spelling the citation guards use.
///
/// ## What it does not check
///
/// Resolution is by **declared identifier**, matching the last dotted component:
/// `Type.member` finds `member` anywhere in the target's sources, without
/// confirming it is declared inside `Type`. Tightening that means parsing rather
/// than matching, and the failure it would prevent — a same-named member on an
/// unrelated type — costs one false alarm on a claim someone is already reading.
/// A false *negative* would be the bad direction, and matching wide avoids it.
@Suite("Deferral falsifiers — a deferral names what would refute it")
struct DeferralFalsifierTests {

    /// The point of the whole suite: a falsifier that resolves means the deferral
    /// is no longer true.
    @Test("no deferral names a falsifier that now exists")
    func noFalsifierHasLanded() throws {
        let landed = try Self.falsifiers().filter { Self.resolves($0.symbol) == .resolved }

        #expect(
            landed.isEmpty,
            """
            These docs defer something whose falsifier now EXISTS in the tree, so the \
            deferral is stale — update the claim (and say when, per the dated-correction \
            practice in stale-summary-guard-declined.md §5):
            \(Self.render(landed))
            """
        )
    }

    /// **The arm-4 trap, guarded.** The declined stale-summary work had one design
    /// that scored zero at every revision — green because it could not fire. A
    /// resolver that answers "absent" to everything would make this suite exactly
    /// that, and nothing else here would notice.
    @Test("the resolver finds a symbol that exists and rejects one that does not")
    func resolverActuallyResolves() {
        #expect(
            Self.resolves("IdentifiedActionResolver.maxChildDepth") == .resolved,
            "a known local symbol must resolve — otherwise this suite cannot fail"
        )
        #expect(Self.resolves("checkRingPropertyLaws") == .absent, "not a symbol of THIS repo")
        #expect(Self.resolves("thisSymbolDoesNotExistAnywhere") == .absent)

        // And the sibling form, which is where the taxonomy's falsifier would live.
        if Self.repositoryRoot(for: "SwiftPropertyLaws") != nil {
            #expect(Self.resolves("SwiftPropertyLaws/checkRingPropertyLaws") == .resolved)
            #expect(Self.resolves("SwiftPropertyLaws/checkNoSuchLaw") == .absent)
        }
    }

    /// A syntax slip in one doc would silently shrink the population; a slip in the
    /// pattern would empty it. Either way the suite would pass by seeing nothing.
    @Test("the convention is actually in use")
    func populationIsNotEmpty() throws {
        let found = try Self.falsifiers()
        #expect(!found.isEmpty, "no `(falsifier: …)` annotations parsed — the pattern or the docs moved")

        // At least one must be answerable without a sibling checkout, so a missing
        // sibling cannot green the whole suite.
        #expect(
            found.contains { !$0.symbol.contains("/") },
            "every falsifier is sibling-scoped; a missing checkout would silence this guard entirely"
        )
    }

    /// A sibling-scoped falsifier is unanswerable without the checkout. That is a
    /// third state, reported rather than folded into "absent" — folding it would
    /// turn a missing clone into a clean bill of health.
    @Test("sibling-scoped falsifiers are answerable, or say so")
    func siblingFalsifiersAreAnswerable() throws {
        let unavailable = try Self.falsifiers().filter { Self.resolves($0.symbol) == .unavailable }
        for entry in unavailable {
            Issue.record(
                """
                \(entry.file):\(entry.line) names `\(entry.symbol)`, but that sibling \
                checkout is missing, so this deferral cannot be checked. Clone it beside \
                this repo (CLAUDE.md expects it) or the claim goes unverified.
                """
            )
        }
    }

    static func render(_ entries: [Falsifier]) -> String {
        let lines = entries.map { "\($0.file):\($0.line) — falsifier `\($0.symbol)` has landed" }
        return lines.sorted().joined(separator: "\n")
    }

    // MARK: - Resolution

    enum Resolution: Equatable {
        case resolved
        case absent
        /// Sibling repo named but not checked out — not evidence either way.
        case unavailable
    }

    static func resolves(_ symbol: String) -> Resolution {
        let parts = symbol.split(separator: "/", maxSplits: 1)
        let repo = parts.count == 2 ? String(parts[0]) : nil
        let name = String(parts.last ?? "").split(separator: ".").last.map(String.init) ?? ""
        guard !name.isEmpty else { return .absent }

        let root: URL
        if let repo {
            guard let sibling = repositoryRoot(for: repo) else { return .unavailable }
            root = sibling
        } else {
            root = repositoryRoot.appendingPathComponent("Sources")
        }

        // A *declaration*, not a mention — a doc naming the symbol, or a call site,
        // must not read as "it exists".
        let declaration = try? NSRegularExpression(
            pattern: "\\b(?:func|let|var|case|struct|class|enum|protocol|actor|typealias)\\s+"
                + NSRegularExpression.escapedPattern(for: name) + "\\b"
        )
        guard let declaration else { return .absent }

        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if declaration.firstMatch(in: text, range: range) != nil { return .resolved }
        }
        return .absent
    }

    static func repositoryRoot(for repo: String) -> URL? {
        let sources = repositoryRoot
            .deletingLastPathComponent()
            .appendingPathComponent(repo)
            .appendingPathComponent("Sources")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sources.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return nil }
        return sources
    }

    // MARK: - Parsing

    struct Falsifier {
        let symbol: String
        let file: String
        let line: Int
    }

    static let repositoryRoot: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }()

    /// `(falsifier: ``Symbol``)`, anywhere in the docs or the index. This file is
    /// excluded — its own prose spells the pattern out.
    static func falsifiers() throws -> [Falsifier] {
        let pattern = try NSRegularExpression(pattern: "falsifier:\\s*`([^`]+)`")
        var found: [Falsifier] = []

        var paths = ["CLAUDE.md"]
        let docs = repositoryRoot.appendingPathComponent("docs")
        let enumerator = FileManager.default.enumerator(at: docs, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "md" else { continue }
            paths.append(url.path.replacingOccurrences(of: repositoryRoot.path + "/", with: ""))
        }

        for relative in paths.sorted() {
            let url = repositoryRoot.appendingPathComponent(relative)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (offset, line) in text.components(separatedBy: "\n").enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                for match in pattern.matches(in: line, range: range) {
                    guard let symbolRange = Range(match.range(at: 1), in: line) else { continue }
                    found.append(
                        Falsifier(
                            symbol: String(line[symbolRange]),
                            file: relative,
                            line: offset + 1
                        )
                    )
                }
            }
        }
        return found
    }
}
