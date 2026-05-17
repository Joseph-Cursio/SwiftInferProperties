import Foundation
import Testing
@testable import SwiftInferCore

// V1.93 (cycle-90) — tests for M1.D `@Reducer` macro recognition.
// Sibling to ReducerDiscovererTCATests (M1.B inheritance-clause
// walker) — same body-walk logic, different conformance-detection
// signal. Modern TCA (1.0+) attaches `Reducer` conformance via the
// `@Reducer` macro rather than the explicit `: Reducer` clause;
// cycle-87 measured 0 reducers across all 7 TCA 1.25.5 examples
// because v1.92's M1.B only checked the inheritance clause.

@Suite("ReducerDiscoverer — V1.93 M1.D @Reducer macro recognition")
struct ReducerDiscovererMacroAttributeTests {

    @Test("V1.93 — @Reducer struct without inheritance clause is detected")
    func macroAttributeWithoutInheritanceClause() {
        let source = """
        import ComposableArchitecture

        @Reducer
        struct Inbox {
            var body: some ReducerOf<Self> {
                Reduce { state, action in return .none }
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Inbox.swift")
        #expect(result.count == 1)
        #expect(result[0].enclosingTypeName == "Inbox")
        #expect(result[0].carrierKind == .tca)
        #expect(result[0].signatureShape == .inoutStateActionReturnsEffect)
    }

    @Test("V1.93 — parameterized @Reducer(state: .equatable) form is detected")
    func macroAttributeWithArguments() {
        // Modern TCA's `@Reducer` macro accepts optional configuration
        // arguments. The detector keys on the attribute name only, not
        // the argument list, so both forms fire identically.
        let source = """
        import ComposableArchitecture

        @Reducer(state: .equatable)
        struct Inbox {
            var body: some ReducerOf<Self> {
                Reduce { state, action in return .none }
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Inbox.swift")
        #expect(result.count == 1)
        #expect(result[0].carrierKind == .tca)
    }

    @Test("V1.93 — @Reducer combined with : Reducer conformance does not double-emit")
    func macroAndConformanceClauseTogether() {
        // A type satisfies both M1.B (inheritance-clause walker) and
        // M1.D (attribute walker). The body walk is idempotent for a
        // single decl — only one set of candidates surfaces.
        let source = """
        import ComposableArchitecture

        @Reducer
        struct Inbox: Reducer {
            var body: some ReducerOf<Self> {
                Reduce { state, action in return .none }
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Inbox.swift")
        #expect(result.count == 1)
    }

    @Test("V1.93 — @Reducer with multiple Reduce closures all surface")
    func macroAttributeMultipleReduceClosures() {
        let source = """
        import ComposableArchitecture

        @Reducer
        struct Inbox {
            var body: some ReducerOf<Self> {
                Reduce { state, action in return .none }
                Reduce { state, action in return .none }
                Reduce { state, action in return .none }
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Inbox.swift")
        #expect(result.count == 3)
    }

    @Test("V1.93 — @Reducer without import ComposableArchitecture is skipped")
    func macroAttributeWithoutImportIsSkipped() {
        // `@Reducer` from a non-TCA source (a user-defined macro with
        // the same name? Unlikely but possible) should not fire the
        // detector. Import-gated, same as M1.B.
        let source = """
        @Reducer
        struct Inbox {
            var body: some ReducerOf<Self> {
                Reduce { state, action in return .none }
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Inbox.swift")
        #expect(result.isEmpty)
    }

    @Test("V1.93 — private @Reducer struct is skipped — matches the conformance-walker posture")
    func privateMacroAttributeIsSkipped() {
        let source = """
        import ComposableArchitecture

        @Reducer
        private struct Inbox {
            var body: some ReducerOf<Self> {
                Reduce { state, action in return .none }
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Inbox.swift")
        #expect(result.isEmpty)
    }

    @Test("V1.93 — @Reducer enum with no body emits zero candidates (composition shape)")
    func macroAttributeOnEnumWithoutBody() {
        // TCA's `Path` / `Destination` enums use `@Reducer enum Path {
        // case detail(SyncUpDetail) }` for composition. They have no
        // body, so the walker finds no Reduce closures and emits 0
        // candidates — but the type-stack push/pop still occurs, and
        // a nested @Reducer struct inside the enum would still fire.
        let source = """
        import ComposableArchitecture

        @Reducer
        enum Path {
            case detail(SyncUpDetail)
            case meeting(Meeting)
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Path.swift")
        #expect(result.isEmpty)
    }

    @Test("V1.93 — non-@Reducer attribute (e.g. @MainActor) does not fire the macro path")
    func otherAttributeDoesNotFire() {
        // Only the exact `@Reducer` attribute name fires M1.D. Other
        // attributes the type might carry (`@MainActor`,
        // `@available(...)`, etc.) are inert. Without an inheritance-
        // clause `: Reducer` to fall back on, the type goes
        // undetected.
        let source = """
        import ComposableArchitecture

        @MainActor
        struct Inbox {
            var body: some ReducerOf<Self> {
                Reduce { state, action in return .none }
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Inbox.swift")
        #expect(result.isEmpty)
    }
}
