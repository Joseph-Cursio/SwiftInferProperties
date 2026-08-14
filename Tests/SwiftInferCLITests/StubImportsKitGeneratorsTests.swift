import Foundation
import PropertyLawCore
import Testing

@testable import SwiftInferCLI

/// A strategist-routed stub must be able to name the kit's Foundation generators.
///
/// `Gen` belongs to `PropertyBased`; `Gen<Data>.data()`, `Gen<URL>.url()`, `Gen<UUID>.uuid()`,
/// `Gen<Decimal>.decimal()` and `Gen<Date>.date()` are extensions in `PropertyLawKit`. A
/// memberwise or enum-payload recipe embeds each member's expression **verbatim**, so a
/// carrier with a single `Data` field emits a kit call from a code path that never decided to.
///
/// **Measured on GRDB (2026-08-14):** `DatabaseValue` rendered
/// `Gen<Data>.data().map { DatabaseValue.Storage.blob($0) }` into a stub importing
/// `Foundation` and `PropertyBased` only — `type 'Gen<Data>' has no member 'data'`, for a
/// generator that exists (`v3.28.0`) and a product the target already links.
///
/// **Third occurrence of one class**, which is why the fix is a single shared constant rather
/// than a third patched route: `.algebraic` lacked the PRODUCT until 2026-08-04
/// (open-threads → *The `Gen<URL>` defect*), and the composite path lacked the IMPORT until
/// its own fix — whose comment states that a verify stub "imports `PropertyBased` and nothing
/// else". Each fixed the route in front of it.
@Suite("Strategist stubs can name the kit's Foundation generators")
struct StubImportsKitGeneratorsTests {

    private func member(_ name: String, _ expression: String) -> MemberSpec {
        MemberSpec(name: name, generatorExpression: expression)
    }

    @Test("the shared import set names PropertyLawKit")
    func baseImportsNamesTheKit() {
        #expect(StrategistDispatchEmitter.baseImports.contains("PropertyLawKit"))
        // The other two are load-bearing too: `Foundation` for the type spellings, and
        // `PropertyBased` for `Gen` itself.
        #expect(StrategistDispatchEmitter.baseImports.contains("PropertyBased"))
        #expect(StrategistDispatchEmitter.baseImports.contains("Foundation"))
    }

    @Test("a single-member carrier over a kit generator imports the kit")
    func singleMemberCarrierImportsTheKit() {
        // The measured shape, reduced: one `Data` field is enough.
        let recipe = StrategistDispatchEmitter.memberwiseRecipeSingle(
            member: member("payload", "Gen<Data>.data()"),
            carrier: "Envelope"
        )
        #expect(recipe.expression.contains("Gen<Data>.data()"))
        #expect(recipe.imports.contains("PropertyLawKit"))
    }

    @Test("a multi-member carrier over a kit generator imports the kit")
    func multiMemberCarrierImportsTheKit() {
        let recipe = StrategistDispatchEmitter.memberwiseRecipeMulti(
            members: [
                member("identifier", "Gen<UUID>.uuid()"),
                member("payload", "Gen<Data>.data()")
            ],
            carrier: "Envelope"
        )
        #expect(recipe.imports.contains("PropertyLawKit"))
    }

    /// The import is only safe because the product is linked in every mode. If someone drops
    /// it from the manifest, an unconditional `import PropertyLawKit` becomes
    /// *no such module* on every stub at once — a worse failure than the one being fixed.
    ///
    /// Parameterised over `WorkdirMode.allCases` so a new mode cannot join without declaring
    /// it, which is how `.algebraic` became the outlier in the first place.
    @Test("every workdir mode links the product the import needs")
    func everyModeLinksTheProduct() {
        for mode in WorkdirMode.allCases {
            let block = VerifierWorkdir.renderTargetDependenciesBlock(
                userPackage: nil, mode: mode
            )
            #expect(
                block.contains("PropertyLawKit") || block.contains("PropertyLawComplex"),
                Comment(rawValue: "\(mode) links neither PropertyLawKit nor a product "
                    + "re-exporting it, so a stub importing the kit cannot build")
            )
        }
    }

    /// The curated recipes are deliberately NOT changed, and this pins why.
    ///
    /// `ocImports` / `syntaxImports` back fully-fixed expressions that embed no member
    /// generator, so they cannot reference a kit Foundation generator by accident. Widening
    /// them would be cargo-culting the fix rather than applying it.
    @Test("a curated recipe with no embedded member expression is left alone")
    func curatedRecipesAreUnchanged() {
        let recipe = StrategistDispatchEmitter.curatedOCRecipe(carrier: "OrderedSet<Int>")
        #expect(recipe != nil)
        #expect(recipe?.imports.contains("OrderedCollections") == true)
    }
}
