import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// **The name-is-the-contract claim, pinned against the counterexample that falsified it (#476).**
///
/// `filter-subset` and `selection-subset` sat in `Refutability.roleEntailedTemplates` — the set
/// whose members a *correct* implementation cannot fail, which reaches the reader as a stub header
/// reading `Law class: ENTAILED — a correct implementation cannot fail this`, as visibility below
/// the confidence cut, and as a rescue from the seed focus. Both templates' own doc comments
/// simultaneously called the law a **name-conjecture** and said, in as many words, *it is not
/// marked role-entailed for exactly this reason*. Two files, opposite verdicts, and the set is the
/// one that runs.
///
/// The tie was not broken by argument. `pbt-book` ships
///
/// ```swift
/// public func filterThenMap(_ values: [Int]) -> [Int] {
///     values.filter { $0 > 10 }.map { $0 * 2 }
/// }
/// ```
///
/// `[11] -> [22]`, so `Set(result) ⊆ Set(input)` is **false**; the function is correct and its name
/// is honest — it says *then map*. The shipped binary proposed `filter-subset` on it at Possible 35
/// on a run carrying **no** `--include-possible`, which is the role-entailed default path.
///
/// So the standard was right and the GATE was wrong: a verb *prefix* does not bound a compound
/// name, because verbs lead and the tail can revoke what the verb promised. The resolution keeps
/// both templates role-entailed and makes the gate honest.
///
/// ## What these tests are for
///
/// The issue asked for a test that fails if the two descriptions diverge again. A test cannot read
/// a doc comment, so it pins the two things a reader actually sees:
///
/// - the **exhibit** — the counterexample must stay rejected, in both templates;
/// - the **rendered text** — a role-entailed suggestion must not tell the reader its law is a
///   conjecture. That is the contradiction #476 reported, in the form it reached the terminal, and
///   it is mechanical rather than editorial: `Refutability` decides, and the caveat must agree.
@Suite("Subset templates — the name is the contract, and the gate must keep that true")
struct SubsetNameContractTests {

    private static let loc = SourceLocation(file: "Templates.swift", line: 107, column: 1)

    /// A `ConfigTree`-like container with a `[DiscoveredConfig]` member.
    private static let configTreeShapes: [String: TypeShape] = [
        "ConfigTree": TypeShape(
            name: "ConfigTree",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: [StoredMember(name: "configs", typeName: "[DiscoveredConfig]")],
            hasUserInit: false
        )
    ]

    private func fn(_ name: String, _ params: [String], returns: String) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: params.enumerated().map { index, type in
                Parameter(label: nil, internalName: "arg\(index)", typeText: type, isInout: false)
            },
            returnTypeText: returns,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: Self.loc,
            containingTypeName: "Templates",
            bodySignals: .empty
        )
    }

    // MARK: - The exhibit

    /// The counterexample, verbatim from `pbt-book/code/Sources/Ch17Templates/Templates.swift:107`.
    /// Before the fix this produced a `filter-subset` suggestion; the law it proposed is false.
    @Test("filterThenMap — the false law that falsified the gate — is not proposed")
    func theExhibitIsRejected() {
        let summary = fn("filterThenMap", ["[Int]"], returns: "[Int]")
        #expect(FilterSubsetTemplate.isFilter(summary) == false)
        #expect(FilterSubsetTemplate.suggest(for: summary) == nil)
    }

    @Test("a tail announcing a second operation revokes the verb's promise")
    func secondOperationTailsRejected() {
        for name in [
            "filterThenMap",        // the exhibit
            "filterAndMap",         // the connective, without `then`
            "selectAndTransform",
            "keepNormalizedPaths",  // a transform verb with no connective at all
            "filterMappedRules"
        ] {
            #expect(
                FilterSubsetTemplate.nameAnnouncesASecondOperation(name),
                "\(name) promises more than selection"
            )
            #expect(FilterSubsetTemplate.isFilter(fn(name, ["[Int]"], returns: "[Int]")) == false, "\(name)")
        }
    }

    /// **The gate must not eat ordinary filters**, which is the whole reason `transformVerbs` is
    /// short. Every name here has a tail that is a noun phrase, not a second operation — and each
    /// is a shape a real codebase writes.
    @Test("a noun-phrase tail is not a second operation")
    func nounPhraseTailsSurvive() {
        for name in [
            "filterViolations",         // the road-test subject the template was built for
            "filterIssuesByEnabledRules",
            "filterBuildSettings",      // `build` is deliberately NOT a transform verb
            "filterRenderedLines",      // nor `render`
            "filterAndroidTargets",     // `android` must not tokenise to the connective `and`
            "selectRules",
            "keepRules"
        ] {
            #expect(
                FilterSubsetTemplate.nameAnnouncesASecondOperation(name) == false,
                "\(name) is an ordinary filter and must keep its law"
            )
        }
    }

    /// The same gate guards the sibling, which shares the failure mode and did not share the check.
    @Test("selection-subset rejects a second-operation tail too")
    func selectionSubsetSharesTheGate() {
        let shapes = Self.configTreeShapes
        let rejected = fn("selectThenMapConfigs", ["ConfigTree"], returns: "[DiscoveredConfig]")
        #expect(SelectionSubsetTemplate.selectionMatch(for: rejected, shapesByName: shapes) == nil)

        // The motivating subject still matches: `layerChain` tokenises to `layer` + `chain`,
        // and `chain` names the walk, not a second operation.
        let kept = fn("layerChain", ["URL", "ConfigTree"], returns: "[DiscoveredConfig]")
        #expect(SelectionSubsetTemplate.selectionMatch(for: kept, shapesByName: shapes) != nil)
    }

    /// **The derivation verbs are gone.** `collect` / `gather` / `resolve` name building a
    /// collection or turning one thing into another; neither promises the result's elements came
    /// out of the container, so neither can carry role-entailment.
    @Test("selection-subset no longer admits accumulation or derivation verbs")
    func derivationVerbsRemoved() {
        for verb in ["collect", "gather", "resolve"] {
            #expect(
                SelectionSubsetTemplate.curatedVerbPrefixes.contains(verb) == false,
                "`\(verb)` promises no membership and must not gate a role-entailed law"
            )
        }
    }

    // MARK: - The divergence guard

    /// **A role-entailed law must never tell the reader it is a conjecture.**
    ///
    /// This is #476's contradiction in the form it actually reached a terminal: the suggestion
    /// rendered `SUBSET IS NAME-CONJECTURED … is a false positive` while the stub file written from
    /// the same suggestion said `ENTAILED — a correct implementation cannot fail this`. A doc
    /// comment cannot be asserted on; the caveat text can, and it is where the divergence showed.
    @Test("no role-entailed suggestion calls its own law a conjecture")
    func entailedLawsDoNotCallThemselvesConjectures() throws {
        let filter = try #require(
            FilterSubsetTemplate.suggest(for: fn("filterViolations", ["[Violation]"], returns: "[Violation]"))
        )
        let shapes = Self.configTreeShapes
        let selection = try #require(
            SelectionSubsetTemplate.suggest(
                for: fn("layerChain", ["URL", "ConfigTree"], returns: "[DiscoveredConfig]"),
                shapesByName: shapes
            )
        )

        for suggestion in [filter, selection] {
            #expect(Refutability.isRoleEntailed(suggestion), "\(suggestion.templateName)")
            let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n").uppercased()
            let why = "\(suggestion.templateName) is role-entailed and must not describe its law "
                + "as a conjecture — that is exactly the divergence #476 reported"
            #expect(caveats.contains("CONJECTURE") == false, "\(why)")
        }
    }
}
