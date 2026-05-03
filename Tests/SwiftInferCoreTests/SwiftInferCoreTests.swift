import Testing
@testable import SwiftInferCore

@Test
func moduleSurfaceIsReachable() {
    // Scaffold marker test from the very first SwiftInferCore commit.
    // The original `SwiftInferCore.version` enum was removed when the
    // module-name collision blocked TestLifter M1.1's SourceLocation
    // resolution; we keep a smoke test here that proves a real Core
    // type is reachable from the test target.
    let location = SourceLocation(file: "X.swift", line: 1, column: 1)
    #expect(location.file == "X.swift")
}
