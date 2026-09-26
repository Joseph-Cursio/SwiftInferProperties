@testable import SwiftInferCore
import Testing

/// An identifier starting with `_` is a name like any other — `_base` is a stored property no test can
/// reach — while an underscored TYPE stays nameable in a returned expression.
@Suite("guard-domain — underscored names")
struct GuardDomainUnderscoreTests {

    @Test("an underscored identifier is a free name")
    func underscoredNameIsFree() {
        #expect(!GuardDomainReader.mentionsOnly("index", in: "index.base == _base.endIndex"))
        #expect(!GuardDomainReader.mentionsOnly("element", in: "_predicate(element)"))
        #expect(GuardDomainReader.mentionsOnly("value", in: "value.isEmpty"))
    }

    @Test("an underscored type name is still a type name in a returned expression")
    func underscoredTypeIsNameable() {
        #expect(GuardDomainReader.mentionsOnly("text", in: "_AttributeStorage()", allowingTypeNames: true))
        #expect(!GuardDomainReader.mentionsOnly("text", in: "_storage.count", allowingTypeNames: true))
    }

    @Test("the bare wildcard is not a name")
    func wildcardIsNotAName() {
        #expect(!GuardDomainReader.isName("_"))
        #expect(GuardDomainReader.isName("_base"))
        #expect(GuardDomainReader.isName("value"))
    }
}
