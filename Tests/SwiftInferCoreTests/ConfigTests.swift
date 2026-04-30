import Testing
@testable import SwiftInferCore

@Suite("Config — pure value type")
struct ConfigTests {

    @Test(".defaults match a freshly-default-initialised Config")
    func defaultsMatchInit() {
        #expect(Config.defaults == Config())
    }

    @Test(".defaults hide Possible tier and have no vocabulary override")
    func defaultsAreConservative() {
        #expect(Config.defaults.includePossible == false)
        #expect(Config.defaults.vocabularyPath == nil)
    }

    @Test("Equality is structural across both fields")
    func equalityStructural() {
        let lhs = Config(includePossible: true, vocabularyPath: "vocab.json")
        let rhs = Config(includePossible: true, vocabularyPath: "vocab.json")
        let differentBool = Config(includePossible: false, vocabularyPath: "vocab.json")
        let differentPath = Config(includePossible: true, vocabularyPath: "other.json")
        #expect(lhs == rhs)
        #expect(lhs != differentBool)
        #expect(lhs != differentPath)
    }
}
