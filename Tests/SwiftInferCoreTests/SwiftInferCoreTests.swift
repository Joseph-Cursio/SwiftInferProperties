import Testing
@testable import SwiftInferCore

@Test
func scaffoldNamespaceCompiles() {
    #expect(SwiftInferCore.version == "0.0.0-scaffold")
}
