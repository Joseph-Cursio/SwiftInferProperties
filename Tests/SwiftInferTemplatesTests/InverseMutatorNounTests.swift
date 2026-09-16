import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The noun gate on `state-machine`'s pairing, one test per row of the population it was measured
/// against.
///
/// **Every row here is a real declaration**, taken from
/// `docs/measurements/normal-form-state-machine-writers.md` §3 — the 16 `state-machine` rows across
/// the corpus-funnel repositories and the 20 manifest corpora, hand-checked exhaustively — plus the
/// two pairs the `first(where:)` cap was hiding and the canonical `navigateToFolder` case the
/// template was built for. A gate argued rather than measured is the thing this project keeps
/// paying for; these are the exhibits.
@Suite("state-machine pairing — the noun, not just the verb")
struct InverseMutatorNounTests {

    private static let loc = SourceLocation(file: "Subject.swift", line: 1, column: 1)

    private func move(
        _ name: String,
        _ parameters: [Parameter] = [],
        type: String = "Subject"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: nil,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: Self.loc,
            containingTypeName: type,
            bodySignals: .empty,
            docComment: nil
        )
    }

    private func labelled(_ label: String?, _ type: String = "Value") -> Parameter {
        Parameter(label: label, internalName: "value", typeText: type, isInout: false)
    }

    private func names(_ pairs: [InverseMutatorPair]) -> [String] {
        pairs.map { "\($0.forward.name)/\($0.backward.name)" }.sorted()
    }

    // MARK: - The five rows that named a pair the code does not owe

    @Test("SwiftFormatRuleStudio: addRule is not undone by removeOption")
    func differentNounsInTheNameAreNotAPair() {
        // `SwiftFormatConfig+Editing.swift` — `removeOption(key:)` is at line 34 and
        // `removeRule(_:from:)` at line 77, so `first(where:)` took the wrong one.
        let pairs = InverseMutatorPairing.candidates(in: [
            move("setOption", [labelled("key"), labelled("value")]),
            move("removeOption", [labelled("key")]),
            move("addRule", [labelled(nil), labelled("to")]),
            move("removeRule", [labelled(nil), labelled("from")])
        ])

        // The right pair, and ONLY the right pair.
        #expect(names(pairs) == ["addRule/removeRule"])
    }

    @Test("SwiftLintRuleStudio: three add/remove pairs yield three rows, correctly matched")
    func everyPairIsEmittedAndEachIsMatchedByItsNoun() {
        // `RuleDetailViewModel+ConfigMutation.swift` declares Disabled, OptIn and Only. The shipped
        // rule emitted ONE row and it cross-paired Disabled with OptIn.
        let pairs = InverseMutatorPairing.candidates(in: [
            move("addDisabledRuleIfNeeded", [labelled("to")]),
            move("addOptInRuleIfNeeded", [labelled("to")]),
            move("removeOptInRuleIfPresent", [labelled("from")]),
            move("removeDisabledRuleIfPresent", [labelled("from")]),
            move("addOnlyRuleIfNeeded", [labelled("to")]),
            move("removeOnlyRuleIfPresent", [labelled("from")])
        ])

        #expect(names(pairs) == [
            "addDisabledRuleIfNeeded/removeDisabledRuleIfPresent",
            "addOnlyRuleIfNeeded/removeOnlyRuleIfPresent",
            "addOptInRuleIfNeeded/removeOptInRuleIfPresent"
        ])
    }

    @Test("SwiftPM: an upsert is not an add — addOrUpdate has no inverse in remove")
    func aNameCoveringTwoOperationsIsNotAMove() {
        // `AuthorizationProvider.swift`. `addOrUpdate` OVERWRITES an existing credential, so
        // `remove ∘ addOrUpdate` restores nothing — the law is false exactly when the entry
        // already existed, which is the case a generated sequence reaches first.
        let pairs = InverseMutatorPairing.candidates(in: [
            move("addOrUpdate", [labelled("for"), labelled("user"), labelled("password")]),
            move("remove", [labelled("for")])
        ])

        #expect(pairs.isEmpty)
    }

    @Test("swiftlang-swift: adding a VALUE is not undone by removing an INDEX")
    func anEmptyForwardNounIsNotExcused() {
        // `_SwiftNSMutableArray` — `add(_ anObject: AnyObject)` at :244 and
        // `removeObject(at index: Int)` at :239. The composition is the identity only when the
        // index happens to be the last one, and a stub would have to invent it.
        let pairs = InverseMutatorPairing.candidates(in: [
            move("removeObject", [labelled("at", "Int")]),
            move("add", [labelled(nil, "AnyObject")])
        ])

        #expect(pairs.isEmpty)
    }

    // MARK: - The eleven that are sound, and must survive

    @Test("the noun is in the NAME on both sides")
    func matchingNameNounsPair() {
        #expect(names(InverseMutatorPairing.candidates(in: [
            move("addAvoidPattern", [labelled(nil, "String")]),
            move("removeAvoidPattern", [labelled(nil, "String")])
        ])) == ["addAvoidPattern/removeAvoidPattern"])

        #expect(names(InverseMutatorPairing.candidates(in: [
            move("addHandler", [labelled(nil), labelled("name"), labelled("position")]),
            move("removeHandler", [labelled(nil)])
        ])) == ["addHandler/removeHandler"])

        #expect(names(InverseMutatorPairing.candidates(in: [
            move("pushType", [labelled(nil), labelled("genericParams")]),
            move("popType")
        ])) == ["pushType/popType"])
    }

    @Test("addTo… and removeFrom… name the same noun")
    func directionPrepositionsAreStripped() {
        // SwiftLintRuleStudio `WorkspaceManager+RecentWorkspaces.swift`. The conventions already
        // carry the direction, so `To`/`From` cannot be part of what is being moved.
        #expect(names(InverseMutatorPairing.candidates(in: [
            move("addToRecentWorkspaces", [labelled(nil, "Workspace")]),
            move("removeFromRecentWorkspaces", [labelled(nil, "Workspace")])
        ])) == ["addToRecentWorkspaces/removeFromRecentWorkspaces"])
    }

    @Test("GRDB: the noun is entirely in the ARGUMENT LABEL, on both sides")
    func matchingLabelNounsPair() {
        // `Database.swift` declares TWO pairs — function at 777/783 and collation at 804/823 — and
        // both moves are spelled bare `add`/`remove`. The corpus-funnel repositories contain no
        // example of a noun in the label, so a gate written against them alone would read "" for
        // every side here and pair `add(function:)` with `remove(collation:)`.
        let pairs = InverseMutatorPairing.candidates(in: [
            move("add", [labelled("function", "DatabaseFunction")]),
            move("remove", [labelled("function", "DatabaseFunction")]),
            move("add", [labelled("collation", "DatabaseCollation")]),
            move("remove", [labelled("collation", "DatabaseCollation")])
        ])

        // Two rows, and neither crosses.
        #expect(pairs.count == 2)
        for pair in pairs {
            #expect(pair.forward.parameters.first?.label == pair.backward.parameters.first?.label)
        }
    }

    @Test("swift-foundation: the noun is in the LABEL on one side and the NAME on the other")
    func aNounSplitAcrossLabelAndNamePairs() {
        // `JSONDecoder.swift` — `push(value:)` / `popValue()`. Also absent from the corpus-funnel
        // repositories.
        #expect(names(InverseMutatorPairing.candidates(in: [
            move("push", [labelled("value", "JSONMap.Value")]),
            move("popValue")
        ])) == ["push/popValue"])
    }

    @Test("select/deselect: neither side names anything, and that is a match")
    func twoEmptyNounsPair() {
        #expect(names(InverseMutatorPairing.candidates(in: [
            move("select", [labelled(nil, "Int")]),
            move("deselect")
        ])) == ["select/deselect"])
    }

    // MARK: - The canonical case, where only the BACKWARD names nothing

    @Test("navigateToFolder/navigateUp survives — there is only one way up")
    func anEmptyBackwardNounIsExcusedWhenThereIsOneWayDown() {
        #expect(names(InverseMutatorPairing.candidates(in: [
            move("navigateToFolder", [labelled(nil, "MacCloudFile")]),
            move("navigateUp")
        ])) == ["navigateToFolder/navigateUp"])
    }

    @Test("…but not when there are two ways down")
    func anEmptyBackwardNounIsNotExcusedWhenItIsAmbiguous() {
        // With two forward moves nothing says which one a single unnamed backward undoes, so the
        // excuse is withdrawn rather than applied twice. This costs rows on purpose: a pair the
        // tool cannot identify is worse than none, which is `selectAllFiles`' lesson.
        let pairs = InverseMutatorPairing.candidates(in: [
            move("navigateToFolder", [labelled(nil, "MacCloudFile")]),
            move("navigateToRoot", [labelled(nil, "Root")]),
            move("navigateUp")
        ])

        #expect(pairs.isEmpty)
    }
}
