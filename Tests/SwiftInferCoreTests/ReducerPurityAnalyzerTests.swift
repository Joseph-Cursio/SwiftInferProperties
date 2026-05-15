import Foundation
import SwiftParser
import SwiftSyntax
import Testing
@testable import SwiftInferCore

// V2.0 M3.A — purity classification tests. Each test parses a
// reducer body via SwiftParser, hands it to ReducerPurityAnalyzer,
// and asserts on the emitted ReducerPurity label. Pure: no
// subprocess, no disk I/O.

@Suite("ReducerPurityAnalyzer — V2.0 M3.A purity classification")
struct ReducerPurityAnalyzerTests {

    // Parse a snippet into a FunctionDeclSyntax for the analyzer.
    // Tests that fail to parse should produce a clear test failure
    // rather than a runtime crash — every helper test source below
    // is a well-formed function decl, so this is defence-in-depth.
    private func parse(_ source: String) -> FunctionDeclSyntax? {
        let tree = Parser.parse(source: source)
        for stmt in tree.statements {
            if let function = stmt.item.as(FunctionDeclSyntax.self) {
                return function
            }
        }
        return nil
    }

    /// Convenience wrapper: parse a source and immediately call
    /// `analyze` on the resulting function. Used by every test below.
    private func analyze(_ source: String) -> ReducerPurity {
        guard let function = parse(source) else {
            Issue.record("source did not parse to a FunctionDeclSyntax")
            return .pure
        }
        return ReducerPurityAnalyzer.analyze(function)
    }

    // MARK: - .pure

    @Test("empty body is .pure")
    func emptyBodyIsPure() {
        let purity = analyze("func reduce(_ s: AppState, _ a: AppAction) -> AppState { return s }")
        #expect(purity == .pure)
    }

    @Test("body with only state mutation and local arithmetic is .pure")
    func plainBodyIsPure() {
        let purity = analyze("""
        func reduce(_ s: inout AppState, _ a: AppAction) {
            s.counter += 1
            s.items.append("x")
        }
        """)
        #expect(purity == .pure)
    }

    @Test("body referencing User-defined types is .pure (no false positive)")
    func userTypesArePure() {
        let purity = analyze("""
        func reduce(_ s: AppState, _ a: AppAction) -> AppState {
            var copy = s
            copy.items = AppCollection.shared.values
            return copy
        }
        """)
        // `AppCollection.shared` is a read, not a write to a static.
        // The analyzer's hidden-mutability detector is for writes only.
        #expect(purity == .pure)
    }

    // MARK: - .effectBearing

    @Test("body with Effect type reference is .effectBearing")
    func effectTypeReferenceIsEffectBearing() {
        let purity = analyze("""
        func reduce(_ s: AppState, _ a: AppAction) -> (AppState, Effect<AppAction>) {
            return (s, Effect.none)
        }
        """)
        #expect(purity == .effectBearing)
    }

    @Test("body using `await` is .effectBearing")
    func awaitIsEffectBearing() {
        let purity = analyze("""
        func reduce(_ s: inout AppState, _ a: AppAction) async {
            s.value = await fetchValue()
        }
        """)
        #expect(purity == .effectBearing)
    }

    @Test("body calling .run on any base is .effectBearing")
    func effectRunIsEffectBearing() {
        let purity = analyze("""
        func reduce(_ s: inout AppState, _ a: AppAction) {
            Effect.run { send in await send(.refresh) }
        }
        """)
        #expect(purity == .effectBearing)
    }

    @Test("body calling .cancel on any base is .effectBearing")
    func cancelIsEffectBearing() {
        let purity = analyze("""
        func reduce(_ s: inout AppState, _ a: AppAction) {
            s.cancellable?.cancel()
        }
        """)
        #expect(purity == .effectBearing)
    }

    @Test("body referencing Task type is .effectBearing")
    func taskTypeIsEffectBearing() {
        let purity = analyze("""
        func reduce(_ s: inout AppState, _ a: AppAction) {
            s.task = Task { try await Task.sleep(for: .seconds(1)) }
        }
        """)
        #expect(purity == .effectBearing)
    }

    @Test("body referencing AnyCancellable is .effectBearing")
    func anyCancellableIsEffectBearing() {
        let purity = analyze("""
        func reduce(_ s: AppState, _ a: AppAction) -> AppState {
            var copy = s
            let token: AnyCancellable? = nil
            copy.token = token
            return copy
        }
        """)
        #expect(purity == .effectBearing)
    }

    // MARK: - .hiddenMutability

    @Test("body writing to Self.staticVar is .hiddenMutability")
    func selfStaticWriteIsHiddenMutability() {
        let purity = analyze("""
        func reduce(_ s: AppState, _ a: AppAction) -> AppState {
            Self.counter += 1
            return s
        }
        """)
        #expect(purity == .hiddenMutability)
    }

    @Test("body writing to a TypeName.staticVar is .hiddenMutability")
    func typeNameStaticWriteIsHiddenMutability() {
        let purity = analyze("""
        func reduce(_ s: AppState, _ a: AppAction) -> AppState {
            AppLogger.invocationCount = AppLogger.invocationCount + 1
            return s
        }
        """)
        #expect(purity == .hiddenMutability)
    }

    @Test("hidden mutability takes priority over effect signals — both detected, .hiddenMutability wins")
    func hiddenMutabilityPriority() {
        let purity = analyze("""
        func reduce(_ s: inout AppState, _ a: AppAction) async {
            Self.counter += 1
            s.value = await fetchValue()
        }
        """)
        #expect(purity == .hiddenMutability)
    }

    // MARK: - rawValue stability

    @Test("ReducerPurity rawValues are stable strings")
    func purityRawValues() {
        #expect(ReducerPurity.pure.rawValue == "pure")
        #expect(ReducerPurity.effectBearing.rawValue == "effect-bearing")
        #expect(ReducerPurity.hiddenMutability.rawValue == "hidden-mutability")
        #expect(ReducerPurity.allCases.count == 3)
    }
}
