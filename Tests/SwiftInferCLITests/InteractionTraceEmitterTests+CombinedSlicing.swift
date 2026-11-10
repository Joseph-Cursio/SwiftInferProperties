import Foundation
@testable import SwiftInferCLI
import Testing

// V2.0 M8.D.4 — combined drop-prefix + drop-suffix slicing.
// Extension-grouped so the parent struct stays under SwiftLint's
// type_body_length cap.
extension InteractionTraceEmitterTests {

    @Test("M8.D.4: both suffixStart and prefix supplied — emits dropFirst+prefix combo")
    func traceWithBothSliceAxes() {
        let both = InteractionTraceEmitter.Inputs(
            candidate: candidate(),
            userModuleName: "MyApp",
            failingSequenceIndex: 7,
            minimumFailingPrefixLength: 5,
            minimumFailingSuffixStart: 3
        )
        let source = InteractionTraceEmitter.emit(both)
        #expect(source.contains("let actions = Array(rawActions.dropFirst(3).prefix(5))"))
        #expect(source.contains("// Minimum failing prefix length: 5"))
        #expect(source.contains("// Minimum failing suffix start: 3"))
    }

    @Test("M8.D.4: only suffixStart supplied — emits dropFirst-only slice")
    func traceWithSuffixStartOnly() {
        let onlyStart = InteractionTraceEmitter.Inputs(
            candidate: candidate(),
            userModuleName: "MyApp",
            failingSequenceIndex: 7,
            minimumFailingPrefixLength: nil,
            minimumFailingSuffixStart: 3
        )
        let source = InteractionTraceEmitter.emit(onlyStart)
        #expect(source.contains("let actions = Array(rawActions.dropFirst(3))"))
        #expect(source.contains("// Minimum failing suffix start: 3"))
    }

    @Test("M8.D.4: makeShrunkActionsExpression returns the right form for each axis combo")
    func makeShrunkActionsExpressionShape() {
        let bothPresent = InteractionTraceEmitter.makeShrunkActionsExpression(
            suffixStart: 2,
            prefixLength: 4
        )
        #expect(bothPresent.contains("Array(rawActions.dropFirst(2).prefix(4))"))
        let onlyPrefix = InteractionTraceEmitter.makeShrunkActionsExpression(
            suffixStart: nil,
            prefixLength: 4
        )
        #expect(onlyPrefix.contains("Array(rawActions.prefix(4))"))
        let onlyStart = InteractionTraceEmitter.makeShrunkActionsExpression(
            suffixStart: 2,
            prefixLength: nil
        )
        #expect(onlyStart.contains("Array(rawActions.dropFirst(2))"))
        let neither = InteractionTraceEmitter.makeShrunkActionsExpression(
            suffixStart: nil,
            prefixLength: nil
        )
        #expect(neither.contains("let actions = rawActions"))
    }
}
