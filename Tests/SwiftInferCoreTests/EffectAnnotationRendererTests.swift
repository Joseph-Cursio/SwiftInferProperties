@testable import SwiftInferCore
import Testing

@Suite("EffectAnnotationRenderer")
struct EffectAnnotationRendererTests {

    private func advice(_ name: String) -> EffectAnnotationAdvice {
        EffectAnnotationAdvice(
            displayName: name,
            signature: "(Int) -> Int",
            location: SourceLocation(file: "Math.swift", line: 7, column: 5)
        )
    }

    @Test("Empty advice renders the empty string")
    func emptyRendersNothing() {
        #expect(EffectAnnotationRenderer.render([]).isEmpty)
    }

    @Test("Rendered block names each function, its location, and the annotation")
    func rendersAdvice() {
        let block = EffectAnnotationRenderer.render([advice("square(_:)")])
        #expect(block.contains("Pure-effect annotations (1 function):"))
        #expect(block.contains("square(_:)"))
        #expect(block.contains("Math.swift:7"))
        #expect(block.contains("/// @lint.effect pure"))
    }

    @Test("Count noun pluralizes")
    func pluralizes() {
        let block = EffectAnnotationRenderer.render([advice("a(_:)"), advice("b(_:)")])
        #expect(block.contains("(2 functions):"))
    }
}
