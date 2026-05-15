import Testing
import PropertyLawKit
import PropertyBased

// V2.0.M2 smoke test — pins the v2.2.0 SwiftPropertyLaws surface
// (ActionSequenceFactory + StatefulGuard + Xoshiro re-exported via
// PropertyLawKit's `@_exported import PropertyBased`) against
// accidental tightening of the kit's public API. Same posture as
// `DerivationStrategistSmokeTests` for the v1.6.0 strategist hoist.
//
// Drafted in `docs/calibration-cycle-73-findings.md` and held back
// until the kit tag was published; landed in this commit.

@Suite("ActionSequenceFactory smoke — V2.0.M2 kit-pin wiring")
struct ActionSequenceFactorySmokeTests {

    enum SmokeAction: CaseIterable, Sendable {
        case one, two, three
    }

    private func makeRNG() -> Xoshiro {
        Xoshiro(seed: (0x01, 0x02, 0x03, 0x04))
    }

    @Test("convenience entry is reachable + produces a non-empty sequence")
    func convenienceEntryReachable() {
        let gen = ActionSequenceFactory.actionSequence(
            forCaseIterable: SmokeAction.self,
            length: 5...5
        )
        var rng = makeRNG()
        let sequence = gen.run(using: &rng)
        #expect(sequence.count == 5)
        for action in sequence {
            #expect(SmokeAction.allCases.contains(action))
        }
    }

    @Test("primary entry is reachable")
    func primaryEntryReachable() {
        let gen = ActionSequenceFactory.actionSequence(
            from: Gen<SmokeAction>.case,
            length: 3...3
        )
        var rng = makeRNG()
        let sequence = gen.run(using: &rng)
        #expect(sequence.count == 3)
    }

    @Test("ActionSequenceFactory.defaultLength == 0...16")
    func defaultLengthIsZeroToSixteen() {
        #expect(ActionSequenceFactory.defaultLength == 0...16)
    }
}
