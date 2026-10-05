/// The reference-oracle text f87bb241 printed for a one-parameter free function, frozen.
///
/// Written by `LiftedTestEmitter.referenceOracle(funcName:arguments:returnTypeText:docComment:seed:)`
/// before the scaffold moved onto `agreementProperty`, with `Gen<Double>.double()` as the draw and
/// seed `(1, 2, 3, 4)`. The move is meant to change nothing for this shape, and
/// `aOneParameterFreeFunctionIsByteIdenticalToBefore` holds it to that byte for byte.
enum ReferenceOracleFrozenText {
    // swiftlint:disable line_length
    static let isValidQuantity = #"""
    // Fill in the reference definition below — your docstring already states it:
    //   "A quantity is valid when it is finite and not negative."
    // Then run the test: the generator finds the input where the code disagrees
    // with its own documentation.
    func isValidQuantity_reference(_ quantity: Double) -> Bool {
        fatalError("state the reference definition from the docstring, then replace this line")
    }

    @Test func isValidQuantity_matchesReferenceDefinition() async {
        let backend = SwiftPropertyBasedBackend()
        let seed = Seed(
            stateA: 0x0000000000000001,
            stateB: 0x0000000000000002,
            stateC: 0x0000000000000003,
            stateD: 0x0000000000000004
        )
        let result = await backend.check(
            trials: 100,
            seed: seed,
            sample: { rng in (Gen.frequency((3.0, Gen<Double>.double()), (2.0, Gen<Double?>.element(of: [0.0, -1.0, 1.0] as [Double]).map { $0! }))).run(using: &rng) },
            property: { value in isValidQuantity(value) == isValidQuantity_reference(value) }
        )
        if case let .failed(_, _, input, error) = result {
            Issue.record(
                "isValidQuantity(_:) disagrees with its documented reference definition at input \(input). \(error?.message ?? "")"
            )
        }
    }
    """#
    // swiftlint:enable line_length
}
