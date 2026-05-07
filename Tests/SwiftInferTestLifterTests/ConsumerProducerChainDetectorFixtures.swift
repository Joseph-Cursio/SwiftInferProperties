import SwiftInferCore
@testable import SwiftInferTestLifter

/// Shared fixture helpers for the M16.1 detector test suites.
/// Split out so `ConsumerProducerChainDetectorTests` (five-criterion
/// scope) and `ConsumerProducerChainDetectorVetoTests` (four producer-
/// veto reasons + edge cases) both stay under SwiftLint's per-suite
/// 250-line `type_body_length` cap.
enum ConsumerProducerChainDetectorFixtures {

    /// Producer that returns `String` from a single non-throwing
    /// non-async `T` argument. Tests can mutate the throws / async /
    /// parameter-count axes for the four-veto coverage. The default
    /// shape pairs with the consumer fixture below to satisfy
    /// type-alignment (`returnTypeText == "String"`).
    static func formatProducer(
        name: String = "format",
        isThrows: Bool = false,
        isAsync: Bool = false,
        parameterCount: Int = 1,
        returnTypeText: String? = "String",
        argTypeText: String = "Doc"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: (0..<parameterCount).map { idx in
                Parameter(label: nil, internalName: "p\(idx)", typeText: argTypeText, isInout: false)
            },
            returnTypeText: returnTypeText,
            isThrows: isThrows,
            isAsync: isAsync,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Format.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }

    /// Consumer with `String` first parameter — pairs with the default
    /// producer's `returnTypeText == "String"` to satisfy type-alignment.
    static func validateConsumer(argTypeText: String = "String") -> FunctionSummary {
        FunctionSummary(
            name: "validate",
            parameters: [
                Parameter(label: nil, internalName: "s", typeText: argTypeText, isInout: false)
            ],
            returnTypeText: "Bool",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Validate.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }

    static func sites(
        count: Int,
        producer: String = "format"
    ) -> [DomainCallSite] {
        (0..<count).map { _ in DomainCallSite(argument: .callOutput(producerName: producer)) }
    }
}
