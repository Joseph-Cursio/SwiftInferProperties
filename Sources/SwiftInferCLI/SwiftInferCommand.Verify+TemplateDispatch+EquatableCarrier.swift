import Foundation
import SwiftInferCore

/// The non-Equatable-carrier gate `buildStubBundle` consults before reporting an
/// `unsupportedTemplate` gap. Split out of `SwiftInferCommand.Verify+TemplateDispatch.swift`,
/// which had reached SwiftLint's 400-line file-length cap (#701).
extension SwiftInferCommand.Verify {

    /// Templates whose emitted law compares two values with `==`.
    ///
    /// **Curated, and deliberately only the two that were measured.** Widening this by
    /// eyeballing template names would re-attribute rows on a guess, and the whole point of
    /// this cause is that it is *more* precise than the two it sits between. A template joins
    /// when someone has looked at its emitted law and seen the `==`.
    static let equalityShapedTemplates: Set<String> = ["inverse-pair", "identity-element"]

    /// Throw `carrierNotEquatable` when the law needs `==` and the carrier provably lacks it.
    ///
    /// **Conservative in the direction that matters: silence unless certain.** Answering
    /// "not Equatable" wrongly would relabel a row whose real blocker is the composer, hiding
    /// a gap that *can* close behind one that cannot. So this fires only when a shape for the
    /// carrier was actually scanned and lists none of `Equatable` / `Hashable` / `Comparable`
    /// — each of which requires or implies `Equatable`. No shape, no claim: an unscanned
    /// carrier, a stdlib type, or a conformance added in a module we did not read all fall
    /// through to the previous behaviour.
    static func requireEquatableCarrierIfLawNeedsIt(
        entry: SemanticIndexEntry,
        allShapes: [String: IndexedTypeShape]
    ) throws {
        guard equalityShapedTemplates.contains(entry.templateName) else { return }
        guard let carrier = entry.carrierTypeName ?? entry.typeName else { return }
        let bare = GenericBindingResolver.bound(carrier)
        // A generic carrier's shape is keyed by its bare name; try both spellings before
        // concluding anything, since concluding requires a shape.
        guard let shape = allShapes[bare] ?? allShapes[carrier] else { return }
        let equalityConformances: Set<String> = ["Equatable", "Hashable", "Comparable"]
        guard shape.inheritedTypes.allSatisfy({ !equalityConformances.contains($0) }) else {
            return
        }
        throw VerifyError.carrierNotEquatable(carrier: carrier, template: entry.templateName)
    }
}
