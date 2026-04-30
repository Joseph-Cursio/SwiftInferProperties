import Testing
@testable import SwiftInfer

@Test
func skeletonNamespaceCompiles() {
    #expect(SwiftInfer.version == "0.0.0-skeleton")
}
