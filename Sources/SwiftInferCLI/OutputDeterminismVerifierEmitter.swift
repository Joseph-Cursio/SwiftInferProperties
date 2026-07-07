import Foundation
import SwiftInferCore

/// PROTOTYPE (Slice B) — emits a verifier for the `outputDeterminism` property
/// of a convention role (VIPER interactor / MVP presenter): given the same
/// input, the role's calls to its output protocol are deterministic.
///
/// The verifier constructs the role twice (fresh each time), injecting a
/// `RecordingFakeEmitter` fake for the assertable output collaborator and no-op
/// `ViewModelProtocolFaker` fakes for its other protocol dependencies, drives
/// the same no-arg action sequence, and asserts the two recorded call-logs are
/// equal. A role whose output depends on `Date()` / `UUID()` / `random()`
/// produces differing logs → the run fails. Emits the algebraic
/// `VERIFY_DEFAULT_RESULT` marker contract (single pass, no edge pass), so the
/// existing `VerifyResultParser` reads it as `.bothPass` / `.defaultFails`.
///
/// Gated (`nil`) when the role isn't instance-constructible, the output protocol
/// isn't recordable, or a dependency can't be faked.
public enum OutputDeterminismVerifierEmitter {

    public static func emit(
        role: StatefulRole,
        outputProtocol: ViewModelProtocolScanner.ProtocolDecl,
        dependencyProtocols: [ViewModelProtocolScanner.ProtocolDecl],
        moduleName: String
    ) -> String? {
        guard case let .instance(initParameters, _) = role.construction else { return nil }
        guard let recordingClass = RecordingFakeEmitter.recordingClass(for: outputProtocol) else { return nil }

        let protocolsByName = Dictionary(dependencyProtocols.map { ($0.name, $0) }) { first, _ in first }
        var fakeSources: [String] = [recordingClass]
        var seenFakes: Set<String> = []
        var args: [String] = []
        for parameter in initParameters {
            guard let resolved = satisfy(
                parameter,
                outputProtocolName: outputProtocol.name,
                protocolsByName: protocolsByName
            ) else { return nil }
            if let fakeSource = resolved.fakeSource, seenFakes.insert(resolved.expression).inserted {
                fakeSources.append(fakeSource)
            }
            args.append(parameter.label.map { "\($0): \(resolved.expression)" } ?? resolved.expression)
        }

        let drives = role.actions
            .filter { $0.parameterTypes.isEmpty && !$0.isAsync && !$0.isThrows }
            .map { "        subject.\($0.name)()" }
        let recorderType = RecordingFakeEmitter.typeName(for: outputProtocol.name)
        let construction = "\(role.typeName)(\(args.joined(separator: ", ")))"

        return source(
            moduleName: moduleName,
            fakes: fakeSources,
            recorderType: recorderType,
            construction: construction,
            driveLines: drives
        )
    }

    // MARK: - Init-parameter satisfaction

    private struct Resolved { let expression: String; let fakeSource: String? }

    /// The output-typed parameter gets the recording fake (`recorder`); other
    /// protocol deps get no-op fakes; Optionals get `nil`; scalars get a
    /// default. `nil` gates the whole emit.
    private static func satisfy(
        _ parameter: RoleInitParameter,
        outputProtocolName: String,
        protocolsByName: [String: ViewModelProtocolScanner.ProtocolDecl]
    ) -> Resolved? {
        let bare = bareTypeName(parameter.typeText)
        if bare == outputProtocolName {
            return Resolved(expression: "recorder", fakeSource: nil)
        }
        if parameter.typeText.trimmingCharacters(in: .whitespaces).hasSuffix("?") {
            return Resolved(expression: "nil", fakeSource: nil)
        }
        if let proto = protocolsByName[bare], let fake = ViewModelProtocolFaker.fakeStruct(for: proto) {
            return Resolved(expression: "Fake_\(bare)()", fakeSource: fake)
        }
        if let value = ViewModelDefaultValue.value(for: bare) {
            return Resolved(expression: value, fakeSource: nil)
        }
        return nil
    }

    private static func bareTypeName(_ type: String) -> String {
        var text = type.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("any ") { text = String(text.dropFirst(4)) }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "?! "))
    }

    // MARK: - Source assembly

    private static func source(
        moduleName: String,
        fakes: [String],
        recorderType: String,
        construction: String,
        driveLines: [String]
    ) -> String {
        let drives = driveLines.isEmpty ? "        // (no drivable no-arg actions)" : driveLines.joined(separator: "\n")
        return """
        import Foundation
        import \(moduleName)

        \(fakes.joined(separator: "\n\n"))

        func runOnce() -> [String] {
            let recorder = \(recorderType)()
            let subject = \(construction)
        \(drives)
            return recorder.callLog
        }

        let first = runOnce()
        let second = runOnce()
        if first == second {
            print("VERIFY_DEFAULT_RESULT: PASS")
            print("VERIFY_DEFAULT_TRIALS: 1")
            print("VERIFY_EDGE_RESULT: PASS")
            print("VERIFY_EDGE_TRIALS: 0")
            print("VERIFY_EDGE_SAMPLED: 0")
            exit(0)
        } else {
            print("VERIFY_DEFAULT_RESULT: FAIL")
            print("VERIFY_DEFAULT_TRIAL: 0")
            print("VERIFY_DEFAULT_INPUT: (output-determinism)")
            print("VERIFY_DEFAULT_FORWARD: \\(first)")
            print("VERIFY_DEFAULT_INVERSE: \\(second)")
            exit(1)
        }
        """
    }
}
