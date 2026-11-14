@testable import SwiftInferCLI

/// One name per `VerifyError` case: the expected set both refusal populations are checked
/// against (`RefusalFlagVocabularyTests.coversEveryCase`). Its `allCases` IS the expected set, so
/// there is no count to forget; `VerifyError.sampledCase` is what forces a new name into it.
enum VerifyErrorCase: String, CaseIterable {
    case suggestionNotFound
    case ambiguousPrefix
    case indexMissing
    case indexEmpty
    case unsupportedCarrier
    case buildFailed
    case runnerCrashed
    case unsupportedTemplate
    case unsupportedPair
    case missingPairedFunction
    case staleIndexEntry
    case noInputToGenerate
    case monotonicityDomainNotComparable
    case carrierNotEquatable
    case declinedByDesign
    case deferredComposer
    case invalidArguments
}

extension VerifyError {
    /// The case this value is. **The exhaustiveness guard both refusal populations lean on**
    /// (`RefusalFlagVocabularyTests.verifyRefusals`, `VerifyCommandTests`' prophecy list): an array literal is
    /// never checked for coverage — #701 added four cases (`staleIndexEntry`, `noInputToGenerate`,
    /// `declinedByDesign`, `deferredComposer`) and neither list on `main` held any of them, and
    /// `carrierNotEquatable` had been missing from both lists since it shipped. This `switch` has
    /// no `default`, so a new case fails to compile here; its arm must return a
    /// `VerifyErrorCase`, so the new name joins `VerifyErrorCase.allCases`, and both list-coverage
    /// checks fail until each list carries a sample of it. (An arm returning another case's name
    /// is caught for every sampled value by `sampledArmsNameTheirOwnCase`.) A computed property
    /// rather than a function, as `UnverifiableCause.label` is, so one arm per case does not read
    /// as branching.
    var sampledCase: VerifyErrorCase {
        switch self {
        case .suggestionNotFound: .suggestionNotFound
        case .ambiguousPrefix: .ambiguousPrefix
        case .indexMissing: .indexMissing
        case .indexEmpty: .indexEmpty
        case .unsupportedCarrier: .unsupportedCarrier
        case .buildFailed: .buildFailed
        case .runnerCrashed: .runnerCrashed
        case .unsupportedTemplate: .unsupportedTemplate
        case .unsupportedPair: .unsupportedPair
        case .missingPairedFunction: .missingPairedFunction
        case .staleIndexEntry: .staleIndexEntry
        case .noInputToGenerate: .noInputToGenerate
        case .monotonicityDomainNotComparable: .monotonicityDomainNotComparable
        case .carrierNotEquatable: .carrierNotEquatable
        case .declinedByDesign: .declinedByDesign
        case .deferredComposer: .deferredComposer
        case .invalidArguments: .invalidArguments
        }
    }
}
