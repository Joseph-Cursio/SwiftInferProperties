import Foundation
import SwiftInferCLI
import SwiftInferCore
import Testing

/// V1.89 lint pass — shared fixture for the verify-pipeline
/// integration suites. Previously file-private helpers in
/// `VerifyPipelineIntegrationTests`; lifted to a sibling enum so
/// the suite can be split across multiple files without each one
/// re-declaring the same helpers. All callers stay in
/// `Tests/SwiftInferIntegrationTests/` so no widening beyond the
/// target boundary.
enum VerifyPipelineIntegrationFixture {

    static func makeWorkdir() throws -> URL {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("verify-pipeline-integration")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }

    static func cleanUp(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static let canonicalSeed = RoundTripStubEmitter.SeedHex(
        stateA: 0x01,
        stateB: 0x02,
        stateC: 0x03,
        stateD: 0x04
    )

    /// Build + run a synthesized verifier workdir against the given
    /// pair of call expressions. Returns the parsed outcome so the
    /// test can assert against it. Round-trip variant — uses
    /// `RoundTripStubEmitter`.
    static func runPipeline(
        forwardCall: String,
        inverseCall: String,
        budget: RoundTripStubEmitter.TrialBudget = .small
    ) throws -> VerifyOutcome {
        let workdir = try makeWorkdir()
        defer { cleanUp(workdir) }
        let stubSource = try RoundTripStubEmitter.emit(
            RoundTripStubEmitter.Inputs(
                forwardCall: forwardCall,
                inverseCall: inverseCall,
                extraImports: [],
                carrierType: "Complex<Double>",
                seedHex: canonicalSeed,
                trialBudget: budget
            )
        )
        _ = try VerifierWorkdir.synthesize(
            VerifierWorkdir.Inputs(
                workdir: workdir,
                userPackage: nil,
                stubSource: stubSource
            )
        )
        let buildOutput = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
        guard buildOutput.exitCode == 0 else {
            return .error(reason: "build failed: \(buildOutput.stderr)")
        }
        let runOutput = try VerifierSubprocess.runVerifierBinary(workdir: workdir)
        return VerifyResultParser.parse(runOutput)
    }

    /// Idempotence-template variant — asserts `f(f(x)) ≈ f(x)` (or
    /// `f(f(x)) == f(x)` for Int).
    static func runIdempotencePipeline(
        functionCall: String,
        carrierType: String,
        budget: IdempotenceStubEmitter.TrialBudget = .small
    ) throws -> VerifyOutcome {
        let workdir = try makeWorkdir()
        defer { cleanUp(workdir) }
        let stubSource = try IdempotenceStubEmitter.emit(
            IdempotenceStubEmitter.Inputs(
                functionCall: functionCall,
                extraImports: [],
                carrierType: carrierType,
                seedHex: canonicalSeed,
                trialBudget: budget
            )
        )
        _ = try VerifierWorkdir.synthesize(
            VerifierWorkdir.Inputs(
                workdir: workdir,
                userPackage: nil,
                stubSource: stubSource
            )
        )
        let buildOutput = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
        guard buildOutput.exitCode == 0 else {
            return .error(reason: "build failed: \(buildOutput.stderr)")
        }
        let runOutput = try VerifierSubprocess.runVerifierBinary(workdir: workdir)
        return VerifyResultParser.parse(runOutput)
    }

    /// Commutativity-template variant — asserts `f(a, b) ≈ f(b, a)`
    /// (or `f(a, b) == f(b, a)` for Int).
    static func runCommutativityPipeline(
        functionCall: String,
        carrierType: String,
        budget: CommutativityStubEmitter.TrialBudget = .small
    ) throws -> VerifyOutcome {
        let workdir = try makeWorkdir()
        defer { cleanUp(workdir) }
        let stubSource = try CommutativityStubEmitter.emit(
            CommutativityStubEmitter.Inputs(
                functionCall: functionCall,
                extraImports: [],
                carrierType: carrierType,
                seedHex: canonicalSeed,
                trialBudget: budget
            )
        )
        _ = try VerifierWorkdir.synthesize(
            VerifierWorkdir.Inputs(
                workdir: workdir,
                userPackage: nil,
                stubSource: stubSource
            )
        )
        let buildOutput = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
        guard buildOutput.exitCode == 0 else {
            return .error(reason: "build failed: \(buildOutput.stderr)")
        }
        let runOutput = try VerifierSubprocess.runVerifierBinary(workdir: workdir)
        return VerifyResultParser.parse(runOutput)
    }

    /// Associativity-template variant — asserts `f(f(a, b), c) ≈
    /// f(a, f(b, c))` (or `==` for Int).
    static func runAssociativityPipeline(
        functionCall: String,
        carrierType: String,
        budget: AssociativityStubEmitter.TrialBudget = .small
    ) throws -> VerifyOutcome {
        let workdir = try makeWorkdir()
        defer { cleanUp(workdir) }
        let stubSource = try AssociativityStubEmitter.emit(
            AssociativityStubEmitter.Inputs(
                functionCall: functionCall,
                extraImports: [],
                carrierType: carrierType,
                seedHex: canonicalSeed,
                trialBudget: budget
            )
        )
        _ = try VerifierWorkdir.synthesize(
            VerifierWorkdir.Inputs(
                workdir: workdir,
                userPackage: nil,
                stubSource: stubSource
            )
        )
        let buildOutput = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
        guard buildOutput.exitCode == 0 else {
            return .error(reason: "build failed: \(buildOutput.stderr)")
        }
        let runOutput = try VerifierSubprocess.runVerifierBinary(workdir: workdir)
        return VerifyResultParser.parse(runOutput)
    }

    /// V1.47.E strategist-routed pipeline — uses
    /// `StrategistDispatchEmitter` so the stub picks its own generator
    /// strategy based on the supplied carrier + typeShape.
    static func runStrategistPipeline(
        functionCalls: [String],
        carrier: String,
        typeShape: IndexedTypeShape? = nil,
        template: String,
        budget: StrategistDispatchEmitter.TrialBudget = .small
    ) throws -> VerifyOutcome {
        let workdir = try makeWorkdir()
        defer { cleanUp(workdir) }
        let stubSource = try StrategistDispatchEmitter.emit(
            StrategistDispatchEmitter.Inputs(
                carrier: carrier,
                typeShape: typeShape,
                template: template,
                functionCalls: functionCalls,
                extraImports: [],
                seedHex: canonicalSeed,
                trialBudget: budget
            )
        )
        _ = try VerifierWorkdir.synthesize(
            VerifierWorkdir.Inputs(
                workdir: workdir,
                userPackage: nil,
                stubSource: stubSource
            )
        )
        let buildOutput = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
        guard buildOutput.exitCode == 0 else {
            return .error(reason: "build failed: \(buildOutput.stderr)")
        }
        let runOutput = try VerifierSubprocess.runVerifierBinary(workdir: workdir)
        return VerifyResultParser.parse(runOutput)
    }
}
