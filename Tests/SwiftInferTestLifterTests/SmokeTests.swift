import Testing
@testable import SwiftInferTestLifter

@Suite("SwiftInferTestLifter — M1.0 scaffolding smoke")
struct SwiftInferTestLifterSmokeTests {

    @Test("TestLifter namespace is reachable from the test target")
    func namespaceCompiles() {
        // M1.0 acceptance — proves the new SwiftInferTestLifter library
        // target wires correctly into the package graph and is importable
        // from a fresh test target. M1.1+ replace this with real coverage
        // as TestSuiteParser / Slicer / detector land.
        _ = TestLifter.self
    }
}
