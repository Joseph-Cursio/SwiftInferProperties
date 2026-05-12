import Testing

/// V1.49.D — Swift Testing tags for the integration test target.
///
/// **`.subprocess`** marks tests that spawn a real `swift build` /
/// verifier-binary subprocess. These tests are load-bearing for the
/// verify pipeline's end-to-end correctness but cost ~10–15s each
/// (cold SwiftPM resolve + dependency compile), and at v1.49's 21
/// parallel subprocess builds the contention pressure has surfaced
/// the §13 perf-test flake intermittently.
///
/// **CI usage (swift test name-regex filtering)**: Swift Testing's
/// tag system is informational metadata; `swift test` itself filters
/// by test/suite name patterns, not tags. The practical CI command
/// patterns are:
///
/// - Default `swift test` runs everything (subprocess + non-subprocess).
/// - `swift test --skip VerifyPipelineIntegrationTests` skips the
///   subprocess-heavy suite — useful for CI when running alongside
///   §13 perf-budget tests.
/// - `swift test --filter VerifyPipelineIntegrationTests` runs only
///   the subprocess tests — useful for verify-pipeline-focused
///   changes.
///
/// The `.subprocess` tag itself carries the contract: tests with this
/// tag are subprocess-heavy and contention-sensitive. Future tooling
/// (Xcode Test Plans, custom test runners) can use the tag directly.
///
/// All 21 V1.42.D / V1.44.E / V1.45.E / V1.46.D / V1.47.G / V1.48.H /
/// V1.49.F subprocess integration tests in
/// `VerifyPipelineIntegrationTests` carry this tag at the suite level.
extension Tag {
    @Tag public static var subprocess: Self
}
