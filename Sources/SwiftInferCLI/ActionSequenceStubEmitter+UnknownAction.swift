import Foundation
import SwiftInferCore

// V2.0 — `unknownActionIsNoOp` stub-emission helpers, lifted out of the main
// file via extension so it stays under SwiftLint's `file_length` cap. Same
// split pattern as `+FamilyChecks.swift` / `+Types.swift`. The family mints a
// file-scope probe conforming to the reducer's *open* Action alphabet and
// drives an empty action sequence (open alphabets have no `CaseIterable` action
// set to generate from), so the post-loop probe check exercises the reducer on
// the initial state — `reduce(s, unknown) == s`.

extension ActionSequenceStubEmitter {

    /// The file-scope probe declaration for the `unknownActionIsNoOp` family:
    /// a fresh type conforming to the reducer's open Action alphabet, so
    /// `reduce(s, probe)` must be a no-op. Empty for every other family.
    static func probeDeclarationLines(_ inputs: Inputs) -> [String] {
        guard inputs.invariant?.family == .unknownActionIsNoOp else { return [] }
        return [
            "struct \(unknownActionProbeTypeName): \(inputs.candidate.actionTypeName) {}",
            ""
        ]
    }

    /// The `let generator = …` line(s). `unknownActionIsNoOp` open alphabets
    /// have no `CaseIterable` action set to generate from, so they drive an
    /// empty sequence (the loop runs zero steps) and the post-loop probe check
    /// exercises the reducer on the initial state; every other family uses the
    /// normal `makeGeneratorBlock`.
    static func generatorLines(inputs: Inputs, isTCA: Bool) -> [String] {
        if inputs.invariant?.family == .unknownActionIsNoOp {
            return ["        let generator = Gen.always([\(unknownActionProbeTypeName)]())"]
        }
        return makeGeneratorBlock(inputs: inputs, isTCA: isTCA)
    }
}
