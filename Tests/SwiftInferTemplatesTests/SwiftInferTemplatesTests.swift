import Testing
@testable import SwiftInferTemplates

@Test
func templatesModuleLinks() {
    // Placeholder until M1.3 introduces the first template.
    // The fact that the module imports without warning is the assertion.
    let _: SwiftInferTemplates.Type = SwiftInferTemplates.self
}
