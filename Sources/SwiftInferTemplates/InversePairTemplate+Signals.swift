import SwiftInferCore

/// V1.18.A — bundle helper split out of `InversePairTemplate.suggest`
/// to keep the suggest entry-point under SwiftLint's cyclomatic-
/// complexity ceiling and the enum body under the 250-line type-body
/// budget. Each helper called here retains independent firing semantics;
/// the bundling is purely structural.
extension InversePairTemplate {
    static func counterAndCoverageSignals(
        for pair: FunctionPair,
        vocabulary: Vocabulary,
        inheritedTypesByName: [String: Set<String>],
        carrierKindResolver: CarrierKindResolver?
    ) -> [Signal] {
        var signals: [Signal] = []
        if let name = nameSignal(for: pair, vocabulary: vocabulary) {
            signals.append(name)
        }
        if let fpCounter = floatingPointStorageCounterSignal(for: pair) {
            signals.append(fpCounter)
        }
        if let direction = directionLabelCounterSignal(for: pair) {
            signals.append(direction)
        }
        if let domainMarker = domainMarkerCounterSignal(for: pair) {
            signals.append(domainMarker)
        }
        if let setAlgebra = setAlgebraShapeVeto(for: pair) {
            signals.append(setAlgebra)
        }
        if let carrier = carrierKindResolver?.carrierKindSignal(
            forContainingTypeName: pair.forward.containingTypeName
        ) {
            signals.append(carrier)
        }
        if let veto = nonDeterministicVeto(for: pair) {
            signals.append(veto)
        }
        if let coverageVeto = protocolCoverageVeto(
            for: pair,
            inheritedTypesByName: inheritedTypesByName
        ) {
            signals.append(coverageVeto)
        }
        return signals
    }
}
