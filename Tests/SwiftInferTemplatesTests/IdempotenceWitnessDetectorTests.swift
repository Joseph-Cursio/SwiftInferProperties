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
}
