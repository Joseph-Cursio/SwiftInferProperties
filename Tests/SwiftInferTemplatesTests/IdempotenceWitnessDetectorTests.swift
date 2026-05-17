import Foundation
import Testing
@testable import SwiftInferTemplates

// V2.0 M4.C — IdempotenceWitnessDetector tests. Pure: parse a
// source snippet, look for an Action enum, assert on the detected
// witnesses.

@Suite("IdempotenceWitnessDetector — V2.0 M4.C name-pattern detection")
struct IdempotenceWitnessDetectorTests {

    // MARK: - classify (low-level)

    @Test("exact-name match: refresh / reset / clear / dismiss / cancel / close / hide")
    func classifyExactNames() {
        for name in ["refresh", "reset", "clear", "dismiss", "cancel", "close", "hide"] {
            #expect(IdempotenceWitnessDetector.classify(name) == .exactName)
        }
    }

    @Test("exact-name match is case-insensitive")
    func classifyExactNamesCaseInsensitive() {
        #expect(IdempotenceWitnessDetector.classify("Refresh") == .exactName)
        #expect(IdempotenceWitnessDetector.classify("DISMISS") == .exactName)
    }

    @Test("name-prefix match: setX / selectX / showX / presentX")
    func classifyPrefixes() {
        #expect(IdempotenceWitnessDetector.classify("setColor") == .namePrefix)
        #expect(IdempotenceWitnessDetector.classify("selectMessage") == .namePrefix)
        #expect(IdempotenceWitnessDetector.classify("showSheet") == .namePrefix)
        #expect(IdempotenceWitnessDetector.classify("presentAlert") == .namePrefix)
    }

    @Test("bare `select` is treated as exact-match per PRD §5.3 example")
    func classifyBareSelect() {
        // PRD §5.3 explicitly cites `select(id)` as idempotent — the
        // bare name routes through exact-match (which has priority
        // over prefix-match for length-equal strings).
        #expect(IdempotenceWitnessDetector.classify("select") == .exactName)
    }

    @Test("non-matching names return nil")
    func classifyNonMatching() {
        #expect(IdempotenceWitnessDetector.classify("increment") == nil)
        #expect(IdempotenceWitnessDetector.classify("appendItem") == nil)
        #expect(IdempotenceWitnessDetector.classify("addEntry") == nil)
        #expect(IdempotenceWitnessDetector.classify("submit") == nil)
    }

    // MARK: - Detection happy path

    @Test("nested Inbox.Action with curated cases produces one witness per matching case")
    func nestedActionCuratedCases() {
        let source = """
        struct Inbox {
            enum Action {
                case refresh
                case dismiss
                case increment
                case appendItem(String)
            }
        }
        """
        let witnesses = IdempotenceWitnessDetector.detect(
            actionTypeName: "Inbox.Action",
            in: source
        )
        #expect(witnesses.count == 2)
        #expect(witnesses.map(\.actionCaseName) == ["refresh", "dismiss"])
        #expect(witnesses.allSatisfy { $0.matchKind == .exactName })
    }

    @Test("top-level Action enum is recognized the same way")
    func topLevelActionEnum() {
        let source = """
        enum AppAction {
            case reset
            case selectMessage(UUID)
            case other
        }
        """
        let witnesses = IdempotenceWitnessDetector.detect(
            actionTypeName: "AppAction",
            in: source
        )
        #expect(witnesses.count == 2)
        #expect(witnesses[0].actionCaseName == "reset")
        #expect(witnesses[0].matchKind == .exactName)
        #expect(witnesses[1].actionCaseName == "selectMessage")
        #expect(witnesses[1].matchKind == .namePrefix)
    }

    @Test("multi-element case (case foo, bar) produces one witness per matching element")
    func multiElementCase() {
        let source = """
        enum AppAction {
            case refresh, reset, increment
        }
        """
        let witnesses = IdempotenceWitnessDetector.detect(
            actionTypeName: "AppAction",
            in: source
        )
        #expect(witnesses.count == 2)
        #expect(Set(witnesses.map(\.actionCaseName)) == ["refresh", "reset"])
    }

    @Test("payload-carrying case names still match (verifier handles payload)")
    func payloadCarryingCaseMatches() {
        let source = """
        enum AppAction {
            case setColor(Color)
            case select(id: UUID)
            case unrelated(value: Int)
        }
        """
        let witnesses = IdempotenceWitnessDetector.detect(
            actionTypeName: "AppAction",
            in: source
        )
        #expect(witnesses.count == 2)
        #expect(Set(witnesses.map(\.actionCaseName)) == ["setColor", "select"])
        // setColor is a prefix match (set*); select is exact-match
        // (PRD §5.3's `select(id)` example calls it out directly).
        let byCase = Dictionary(
            uniqueKeysWithValues: witnesses.map { ($0.actionCaseName, $0.matchKind) }
        )
        #expect(byCase["setColor"] == .namePrefix)
        #expect(byCase["select"] == .exactName)
    }

    // MARK: - Negatives

    @Test("target enum not found → empty result")
    func targetEnumNotFound() {
        let source = """
        enum OtherEnum {
            case refresh
            case reset
        }
        """
        let witnesses = IdempotenceWitnessDetector.detect(
            actionTypeName: "AppAction",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("enum with no idempotent-looking cases returns empty")
    func noIdempotentCases() {
        let source = """
        enum AppAction {
            case increment
            case decrement
            case append(String)
        }
        """
        let witnesses = IdempotenceWitnessDetector.detect(
            actionTypeName: "AppAction",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    // MARK: - V1.96 TCA action-name conventions

    @Test("V1.96 — task / delegate / binding classify as exact-name (TCA conventions)")
    func classifyTCAActionConventions() {
        // Cycle-87 finding #5 sub-item (c) — extend the curated
        // exact-name set with TCA's three canonical idempotent
        // Action-name conventions. Every TCA Action enum uses at
        // least one of these.
        #expect(IdempotenceWitnessDetector.classify("task") == .exactName)
        #expect(IdempotenceWitnessDetector.classify("delegate") == .exactName)
        #expect(IdempotenceWitnessDetector.classify("binding") == .exactName)
    }

    @Test("V1.96 — TCA exact-name additions are case-insensitive (like the rest of the set)")
    func classifyTCAActionConventionsCaseInsensitive() {
        #expect(IdempotenceWitnessDetector.classify("Task") == .exactName)
        #expect(IdempotenceWitnessDetector.classify("DELEGATE") == .exactName)
        #expect(IdempotenceWitnessDetector.classify("Binding") == .exactName)
    }

    @Test("V1.96 — toggle / toggleX stays unmatched — toggling is not idempotent")
    func toggleIsNotIdempotent() {
        // Intentionally NOT added to the exact-name set. Toggling
        // toggles — applying twice returns to original state, which
        // is the canonical non-idempotent shape. Confirm both the
        // bare name and the common prefix form stay unmatched.
        #expect(IdempotenceWitnessDetector.classify("toggle") == nil)
        #expect(IdempotenceWitnessDetector.classify("toggleMenu") == nil)
        #expect(IdempotenceWitnessDetector.classify("toggleChanged") == nil)
    }

    @Test("V1.96 — TCA-shaped Action enum fires task / delegate / binding witnesses")
    func tcaShapedActionEnumFires() {
        // Realistic TCA Action enum — `task`, `delegate(...)`, and
        // `binding(BindingAction<State>)` all fire idempotence
        // witnesses with the v1.96 expansion. The
        // `incrementButtonTapped` case stays unmatched (not in
        // either the exact-name set or the prefix list).
        let source = """
        struct Feature {
            enum Action {
                case task
                case delegate(Delegate)
                case binding(BindingAction<State>)
                case incrementButtonTapped
            }
        }
        """
        let witnesses = IdempotenceWitnessDetector.detect(
            actionTypeName: "Feature.Action",
            in: source
        )
        #expect(witnesses.count == 3)
        #expect(Set(witnesses.map(\.actionCaseName)) == ["task", "delegate", "binding"])
        #expect(witnesses.allSatisfy { $0.matchKind == .exactName })
    }
}
