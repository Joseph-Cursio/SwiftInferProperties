import Foundation
@testable import SwiftInferCore

/// The fingerprint of a suggestion's subject, as the scanner reads it out of `directory`.
///
/// **Why fixture tests need this at all (v1.149).** Verify evidence is applied only when it
/// was measured against the body that is there now — see `SubjectFingerprint` and road test
/// §10.2. Any test that hand-writes evidence for a fixture and expects it to be *applied*
/// must therefore stamp it with the real value; without one, the pipeline correctly withholds
/// the outcome and the arm fails for a reason that has nothing to do with what it is testing.
///
/// **Derived, never hardcoded.** It goes through the same production join the discover
/// pipeline uses (`byLocation` + `forSuggestion`). A literal hash would silently stop matching
/// the first time a fixture's source was reindented, and the arm would then pass only because
/// the evidence was being discarded — green for the opposite of the intended reason.
///
/// Returns `nil` when the subject cannot be fingerprinted; callers `#require` it, so a fixture
/// that stops being scannable fails loudly rather than quietly testing the staleness path.
func subjectFingerprint(of suggestion: Suggestion, in directory: URL) throws -> String? {
    let summaries = try FunctionScanner.scan(directory: directory)
    return SubjectFingerprint.forSuggestion(
        evidenceLocations: suggestion.evidence.map(\.location),
        byLocation: SubjectFingerprint.byLocation(summaries)
    )
}
