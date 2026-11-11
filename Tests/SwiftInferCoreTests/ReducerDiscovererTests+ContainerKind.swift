@testable import SwiftInferCore
import Testing

// Container declaration-kind invariance. A reducer whose enclosing type
// holds only static members can be written as a `struct` or as a
// caseless `enum` — the latter is exactly the rewrite SwiftLint's
// `convenience_type` rule prescribes. `ReducerDiscoverer` visits
// `StructDeclSyntax` and `EnumDeclSyntax` identically (same
// `extractTCACandidatesIfReducerConformer` call; the kind is never
// threaded through), so the two forms must yield identical discovery.
//
// This pins the equivalence that lets the v2.0 calibration corpus stay
// frozen: a lint-driven struct→enum rewrite of a `HandRolled` fixture
// would be a no-op for the tool, not a silent baseline shift. It is the
// regression-test counterpart to excluding `Tests/Fixtures` from lint.
extension ReducerDiscovererTests {

    /// The `HandRolled/Hand01_Conservation` fixture shape, parameterized
    /// on the enclosing type's declaration keyword. Line layout is fixed
    /// so the only difference between `struct` and `enum` is the keyword
    /// itself — keeping the recorded `location` line numbers identical.
    private static func conservationReducerSource(container: String) -> String {
        """
        \(container) CountedListReducer {
            struct State {
                var itemCount: Int
                var items: [String]
            }
            enum Action {
                case add(String)
                case noop
            }
            static func reduce(_ state: State, _ action: Action) -> State {
                return state
            }
        }
        """
    }

    @Test("struct vs caseless-enum container yields an identical ReducerCandidate")
    func containerKindInvariantStructVsEnum() {
        let structResult = ReducerDiscoverer.discover(
            source: Self.conservationReducerSource(container: "struct"),
            file: "F.swift"
        )
        let enumResult = ReducerDiscoverer.discover(
            source: Self.conservationReducerSource(container: "enum"),
            file: "F.swift"
        )

        #expect(structResult.count == 1)
        #expect(enumResult.count == 1)
        // `ReducerCandidate` is `Equatable` and the two sources are
        // line-for-line identical apart from the keyword, so a matching
        // candidate is fully ==-equal — `location` included.
        #expect(structResult == enumResult)
        #expect(enumResult.first?.enclosingTypeName == "CountedListReducer")
        #expect(enumResult.first?.functionName == "reduce")
        #expect(enumResult.first?.signatureShape == .stateActionReturnsState)
    }
}
