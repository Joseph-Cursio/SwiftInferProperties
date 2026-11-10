import PropertyLawCore
import PropertyLawSyntaxSupport
import SwiftSyntax

extension MemberBlockInspector {

    /// Replace a carrier generic parameter with `Int` inside an array type.
    ///
    /// Narrow on purpose: only `[T]` where `T` is one of the carrier's own generic parameter
    /// names. That is the exact shape `SequenceInitializerNormalizer` produces for the
    /// canonical collection constructor, and nothing else. A broader textual substitution
    /// would rewrite types it does not understand, and the cost of being wrong is emitted
    /// code that does not compile.
    ///
    /// `Int` matches `ConcreteInstantiation` — the carrier is named `Deque<Int>`, so its
    /// elements must be `Int` for the call to typecheck — and matches the kit's own recipes,
    /// which bind element types to `Int` and say so.
    static func substitutingCarrierGenerics(
        _ typeName: String,
        carrierGenericParameters: [String]
    ) -> String {
        guard !carrierGenericParameters.isEmpty,
              typeName.hasPrefix("["), typeName.hasSuffix("]") else { return typeName }
        let element = String(typeName.dropFirst().dropLast())
        guard carrierGenericParameters.contains(element) else { return typeName }
        return "[Int]"
    }
}
