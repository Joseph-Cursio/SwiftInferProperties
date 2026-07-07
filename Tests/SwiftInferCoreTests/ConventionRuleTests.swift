@testable import SwiftInferCore
import Testing

/// Unit tests for `ConventionRule` recognition — the name-suffix / conformance
/// match that drives VIPER/MVP discovery.
struct ConventionRuleTests {

    @Test("matches on a name suffix")
    func matchesNameSuffix() {
        let rule = ConventionRule(paradigm: .mvp, nameSuffixes: ["Presenter"], outputCollaboratorNames: ["view"])
        #expect(rule.matches(typeName: "LoginPresenter", inheritedTypeNames: []))
        #expect(!rule.matches(typeName: "LoginService", inheritedTypeNames: []))
    }

    @Test("matches on a conformance suffix even when the name doesn't")
    func matchesConformanceSuffix() {
        let rule = ConventionRule(
            paradigm: .viper,
            nameSuffixes: ["Interactor"],
            conformanceSuffixes: ["InteractorInput"],
            outputCollaboratorNames: ["output"]
        )
        // Name doesn't end in Interactor, but it conforms to *InteractorInput.
        #expect(rule.matches(typeName: "LoginService", inheritedTypeNames: ["LoginInteractorInput"]))
        // Neither signal → no match.
        #expect(!rule.matches(typeName: "LoginService", inheritedTypeNames: ["Codable"]))
    }

    @Test("built-in defaults cover MVP presenters and VIPER interactors")
    func builtInDefaults() {
        let mvp = ConventionRule.builtInDefaults.first { $0.paradigm == .mvp }
        let viper = ConventionRule.builtInDefaults.first { $0.paradigm == .viper }
        #expect(mvp?.matches(typeName: "ProfilePresenter", inheritedTypeNames: []) == true)
        #expect(mvp?.outputCollaboratorNames == ["view"])
        #expect(viper?.matches(typeName: "ProfileInteractor", inheritedTypeNames: []) == true)
        #expect(viper?.outputCollaboratorNames.contains("presenter") == true)
    }
}
