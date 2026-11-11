@testable import SwiftInferCLI
import Testing

@Suite("InteractiveTriage — bounded determinism generator (#3 overflow)")
struct InteractiveTriageBoundedGeneratorTests {

    @Test func boundsIntToAvoidOverflowTraps() {
        #expect(
            InteractiveTriage.boundedDeterminismGenerator(forTypeName: "Int")
                == "Gen<Int>.int(in: -10_000 ... 10_000)"
        )
    }

    @Test func leavesNonNumericTypesToTheNormalChooser() {
        #expect(InteractiveTriage.boundedDeterminismGenerator(forTypeName: "String") == nil)
        #expect(InteractiveTriage.boundedDeterminismGenerator(forTypeName: "Point") == nil)
        #expect(InteractiveTriage.boundedDeterminismGenerator(forTypeName: "Double") == nil)
    }
}
