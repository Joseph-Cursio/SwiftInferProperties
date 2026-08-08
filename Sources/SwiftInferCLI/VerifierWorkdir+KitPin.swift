import Foundation

// Extracted from `VerifierWorkdir.swift` to keep that file under the
// `file_length` cap. The constant is small but load-bearing enough to want
// its own file: it is the single point where the synthesized verifier's
// SwiftPropertyLaws requirement is decided, and it is guarded against
// drifting from `Package.swift` by `VerifierWorkdirKitPinTests`.
extension VerifierWorkdir {

    /// The `SwiftPropertyLaws` lower bound every synthesized verifier declares.
    ///
    /// **Must equal this package's own `Package.swift` requirement**, and
    /// `VerifierWorkdirKitPinTests` fails the build if it drifts. The two are
    /// not independent: a `--corpus-module` survey adds a `.package(path:)` on
    /// the working-dir package, so SwiftPM has to reconcile the verifier's
    /// requirement with the corpus's. If they name disjoint major ranges the
    /// resolve fails outright and *every* entry in the survey is recorded as
    /// `measured-error: build-failed` — a verdict-shaped non-verdict that reads
    /// like "the property could not be checked" when nothing about the property
    /// was ever involved.
    ///
    /// This constant replaced four hand-written literals (`2.1.0` on the
    /// algebraic path, `2.2.0` on the three interaction paths) that had drifted
    /// a whole major version behind the repo's requirement at the time,
    /// `from: "3.17.0"`. The self-dogfood
    /// road test found it the only way it could be found — by running a survey
    /// against a corpus that is itself a SwiftPropertyLaws consumer. See
    /// `docs/measurements/roadtest-self-dogfood.md` §9.
    static let swiftPropertyLawsRequirement = "3.27.0"

    static var swiftPropertyLawsDependencyLine: String {
        ".package(url: \"https://github.com/Joseph-Cursio/SwiftPropertyLaws.git\", "
            + "from: \"\(swiftPropertyLawsRequirement)\")"
    }
}
