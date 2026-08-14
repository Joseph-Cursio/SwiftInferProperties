import Foundation
@testable import SwiftInferCore
import Testing

/// Guards the domain split made 2026-08-14 in `CollisionBias`.
///
/// `rulesAlreadyPresent(_ name: String, kind:)` — a rule-name lookup whose domain contains no
/// separators — was handed a four-symbol alphabet including `/`, a rationale about *"any path
/// contains its own ancestors"*, and advice about confusing `strip the prefix` with `strip
/// every occurrence` (`docs/measurements/exploratory-swiftformatrulestudio.md` §5.3). The
/// carrier recipe went further and named `SwiftFormatConfig(currentPath: $0)` — a property that
/// type does not have.
///
/// **The collision advice was always sound; the domain it asserted was invented.** The type's
/// own header argues that *"what generalises is not the shape but the alphabet"*, and
/// `IdempotenceTemplate+Generators` declines to reuse this recipe precisely because it *"is
/// path-flavored"*. Both were right about the code they described and the code did the other
/// thing.
@Suite("CollisionBias — the alphabet generalises, the shape does not")
struct CollisionBiasDomainTests {

    // MARK: - Selection

    @Test(
        "a path-shaped parameter keeps the path form",
        arguments: ["path", "filePath", "url", "directory", "root", "fromPath"]
    )
    func pathShapedKeepsPathForm(name: String) {
        // The form has a measured witness behind it (the road test's `isImmediateChild`), so
        // the split must not cost it. `fromPath` is included because label normalisation feeds
        // this set.
        let recipe = CollisionBias.collidingString(subject: name)
        #expect(recipe.rationale.contains("ancestors"))
        #expect(recipe.expression.contains("\"/\" + "))
    }

    @Test(
        "a non-path parameter gets the neutral form",
        arguments: ["name", "key", "identifier", "ruleName", "query", "text"]
    )
    func nonPathGetsNeutralForm(name: String) {
        let recipe = CollisionBias.collidingString(subject: name)
        #expect(!recipe.rationale.contains("ancestors"))
        #expect(!recipe.rationale.contains("strip the prefix"))
        #expect(!recipe.expression.contains("\"/\" + "))
    }

    @Test("`name` and `key` are locations but NOT path-shaped")
    func pathSetIsNarrowerThanLocationSet() {
        // The distinction the witness turns on. `HostileInputEntryPoints.locationLabels`
        // answers "is this a location rather than a payload" and contains `name`, `key` and
        // `identifier`; none of them implies separators or ancestors. Reusing that set whole
        // would have reproduced the defect on exactly the witness.
        for label in ["name", "key", "identifier"] {
            #expect(HostileInputEntryPoints.isLocationLabel(label))
            #expect(!CollisionBias.isPathShaped(label))
        }
    }

    // MARK: - Both forms keep the mechanism

    @Test("both forms keep the tiny alphabet — the part that actually works")
    func bothFormsKeepTheAlphabet() {
        // The fix removes an asserted DOMAIN, not the collision bias. If the neutral form
        // widened the alphabet it would silently switch off the thing the recipe exists for,
        // and every law would pass for the wrong reason — `fixtures/domain-transfer-signal`'s
        // failure mode, arriving through a doc edit.
        for subject in ["path", "name"] {
            let expression = CollisionBias.collidingString(subject: subject).expression
            for symbol in CollisionBias.alphabet {
                #expect(expression.contains("\"\(symbol)\""))
            }
            #expect(expression.contains("array(of: 0...6)"))
        }
    }

    // MARK: - The carrier recipe

    @Test("the carrier recipe never invents an initialiser parameter")
    func carrierRecipeInventsNothing() {
        // The worst half of the defect: `SwiftFormatConfig(currentPath: $0)` LOOKS specific, so
        // a reader pastes it and it does not compile. Worse than the `gen()` mistake the
        // original comment was written to prevent, which named a method that exists nowhere.
        let recipe = CollisionBias.carrierState(typeName: "SwiftFormatConfig", subject: "name")
        #expect(!recipe.expression.contains("currentPath"))
        #expect(!recipe.expression.contains("SwiftFormatConfig("))
        // It must still name the manual step, or it is honest and useless.
        #expect(recipe.expression.contains("build the carrier from it"))
    }

    @Test("the carrier recipe takes the same form as its argument")
    func carrierFormMatchesArgument() {
        // A path rationale beside a neutral argument recipe is the same misattribution one
        // line further down the output.
        let neutral = CollisionBias.carrierState(typeName: "Cfg", subject: "name")
        #expect(!neutral.expression.contains("ancestors"))

        let pathShaped = CollisionBias.carrierState(typeName: "Nav", subject: "path")
        #expect(pathShaped.expression.contains("ancestors"))
        #expect(pathShaped.expression.contains("path-like String state"))
    }

    @Test("an unknown subject defaults to neutral, not to path")
    func unknownSubjectDefaultsNeutral() {
        // Direction of the default matters: a neutral recipe on a path subject loses a little
        // bias, while a path recipe on a rule-name subject asserts a domain that does not
        // exist — and the second is what shipped.
        #expect(!CollisionBias.carrierState(typeName: "T").expression.contains("ancestors"))
        #expect(!CollisionBias.collidingString(subject: "").rationale.contains("ancestors"))
    }
}
