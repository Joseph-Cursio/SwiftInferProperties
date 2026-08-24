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
    ///
    /// **Raised to 4.1.0 on 2026-08-22, because the EMITTER now depends on it.**
    /// `DerivationStrategist` narrows an `ascii:`-labelled `Unicode.Scalar` parameter to
    /// `Gen<Unicode.Scalar>.asciiScalar()`, which does not exist in 4.0.0 — so a workdir that
    /// resolved to 4.0.0 would emit a stub naming a symbol its own dependency does not vend.
    /// A floor is a claim about what the generated code needs, and the generated code changed.
    /// See `docs/measurements/criterion-a-swift-system.md` §8.
    /// **Raised to 4.2.0 on 2026-08-24, because DERIVATION now depends on it.**
    /// `RawType` and `CompositeMemberParser` recognise a module-qualified leaf spelling —
    /// `Swift.String` is `String` — which 4.1.0 does not. A workdir resolving to 4.1.0 derives
    /// no generator for any member a code generator wrote, so every such row reports an
    /// unsupported *carrier*: a claim that the carrier is exotic, about a `String`. Measured on
    /// a generated client, that is the difference between 0 and 15 executing rows.
    /// See `docs/measurements/module-qualified-leaf-spelling.md`.
    static let swiftPropertyLawsRequirement = "4.2.0"

    static var swiftPropertyLawsDependencyLine: String {
        ".package(url: \"https://github.com/Joseph-Cursio/SwiftPropertyLaws.git\", "
            + "from: \"\(swiftPropertyLawsRequirement)\")"
    }

    /// The **engine** requirement, and it is a second pin with the same failure mode.
    ///
    /// `swift-property-based` is a transitive dependency of the kit, but every synthesized
    /// workdir manifest declares it **directly** — deliberately, so resolution does not
    /// lean on the kit's own dep graph. That makes it independent of
    /// `swiftPropertyLawsRequirement`, and independent pins drift.
    ///
    /// **Measured 2026-08-19**: on the 2.0 upgrade the kit moved to `from: "2.0.0"` while
    /// these lines still said `1.0.0`. The intersection is empty, so SwiftPM cannot
    /// resolve and **every** entry reports `measured-error: build-failed` — which reads as
    /// an architectural limitation rather than a broken manifest, exactly the way the kit
    /// pin's own doc says a disjoint range does. `VerifierWorkdirEnginePinTests` is the
    /// guard the kit pin has had since the self-dogfood road test and this one did not.
    static let swiftPropertyBasedRequirement = "2.0.0"

    static var swiftPropertyBasedDependencyLine: String {
        ".package(url: \"https://github.com/x-sheep/swift-property-based.git\", "
            + "from: \"\(swiftPropertyBasedRequirement)\")"
    }
}
