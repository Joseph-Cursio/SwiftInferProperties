import Foundation
import PropertyLawCore

// V1.150 — edge-biased String carrier generator.
//
// The kit's raw `String` generator (`Gen<Character>.letterOrNumber.string(of:
// 0...8)`) only ever produces alphanumerics, so a property check over a
// string-processing function never sees whitespace, newlines, or punctuation —
// the exact inputs that falsify structural logic (YAML `- ` markers,
// indentation, trimming, splitting). A determinism/idempotence check on such a
// function then *false-passes*.
//
// V1.152 — the edge-biased generator now lives in its canonical home,
// `PropertyLawCore.RawType.edgeBiasedGeneratorExpression` (SwiftPropertyLaws
// 3.2.0). This override only decides *when* to apply it: at the top level of a
// String carrier. Struct members keep the plain `generatorExpression` (they
// resolve via `member.generatorExpression`, not this path), so their generators
// stay bounded.
extension StrategistDispatchEmitter {

    /// The edge-biased generator expression for a top-level `String` carrier,
    /// or `nil` for any other carrier (callers fall back to
    /// `RawType.generatorExpression`).
    static func edgeBiasedStringExpression(for carrier: String) -> String? {
        RawType(typeName: carrier)?.edgeBiasedGeneratorExpression
    }
}
