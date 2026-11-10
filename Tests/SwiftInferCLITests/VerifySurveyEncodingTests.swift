import ArgumentParser
import Foundation
import Testing

@testable import SwiftInferCLI

@Suite("V1.50.B — SurveyOutcome + SurveyRecord JSON encoding")
struct VerifySurveyEncodingTests {

    private static let canonicalEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    @Test("SurveyOutcome raw values match the v1.50 plan's 5 categories")
    func surveyOutcomeRawValuesAreLoadBearing() {
        #expect(SwiftInferCommand.Verify.SurveyOutcome.measuredBothPass.rawValue == "measured-bothPass")
        #expect(SwiftInferCommand.Verify.SurveyOutcome.measuredEdgeCaseAdvisory.rawValue == "measured-edgeCaseAdvisory")
        #expect(SwiftInferCommand.Verify.SurveyOutcome.measuredDefaultFails.rawValue == "measured-defaultFails")
        #expect(SwiftInferCommand.Verify.SurveyOutcome.measuredError.rawValue == "measured-error")
        #expect(
            SwiftInferCommand.Verify.SurveyOutcome.architecturalCoveragePending.rawValue
                == "architectural-coverage-pending"
        )
    }

    @Test("SurveyRecord JSON encodes with all five fields + sorted keys")
    func surveyRecordJsonShape() throws {
        let record = SwiftInferCommand.Verify.SurveyRecord(
            identityHash: "0xBC43359C0574816B",
            templateName: "round-trip",
            primaryFunctionName: "exp(_:)",
            carrier: "Complex<Double>",
            outcome: .measuredBothPass,
            outcomeDetail: "defaultTrials=100 edgeTrials=100 edgeSampled=7"
        )
        let data = try Self.canonicalEncoder.encode(record)
        let json = String(data: data, encoding: .utf8) ?? ""
        // All 6 keys present (5 fields + outcomeDetail).
        #expect(json.contains("\"carrier\":\"Complex<Double>\""))
        #expect(json.contains("\"identityHash\":\"0xBC43359C0574816B\""))
        #expect(json.contains("\"outcome\":\"measured-bothPass\""))
        #expect(json.contains("\"outcomeDetail\":\"defaultTrials=100 edgeTrials=100 edgeSampled=7\""))
        #expect(json.contains("\"primaryFunctionName\":\"exp(_:)\""))
        #expect(json.contains("\"templateName\":\"round-trip\""))
    }

    @Test("SurveyRecord round-trips through Codable bit-for-bit")
    func surveyRecordRoundTrips() throws {
        let original = SwiftInferCommand.Verify.SurveyRecord(
            identityHash: "0xABCD",
            templateName: "idempotence",
            primaryFunctionName: "sort()",
            carrier: nil,
            outcome: .architecturalCoveragePending,
            outcomeDetail: "unsupported-carrier: SomeType"
        )
        let data = try Self.canonicalEncoder.encode(original)
        let decoded = try JSONDecoder().decode(
            SwiftInferCommand.Verify.SurveyRecord.self, from: data
        )
        #expect(decoded.identityHash == original.identityHash)
        #expect(decoded.templateName == original.templateName)
        #expect(decoded.primaryFunctionName == original.primaryFunctionName)
        #expect(decoded.carrier == original.carrier)
        #expect(decoded.outcome == original.outcome)
        #expect(decoded.outcomeDetail == original.outcomeDetail)
    }

    @Test("SurveyRecord with nil carrier + nil outcomeDetail round-trips")
    func surveyRecordNilFieldsRoundTrip() throws {
        let original = SwiftInferCommand.Verify.SurveyRecord(
            identityHash: "0x1234",
            templateName: "monotonicity",
            primaryFunctionName: "doubled()",
            carrier: nil,
            outcome: .measuredBothPass,
            outcomeDetail: nil
        )
        let data = try Self.canonicalEncoder.encode(original)
        let decoded = try JSONDecoder().decode(
            SwiftInferCommand.Verify.SurveyRecord.self, from: data
        )
        #expect(decoded.carrier == nil)
        #expect(decoded.outcomeDetail == nil)
    }
}
