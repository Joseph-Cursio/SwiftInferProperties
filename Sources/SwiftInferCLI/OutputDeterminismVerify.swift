import Foundation
import SwiftInferCore

/// PROTOTYPE (Slice B3b) — orchestrates a measured `outputDeterminism` verify for
/// one convention role: resolve its output protocol, emit the recording-fake
/// verifier (`OutputDeterminismVerifierEmitter`), build it against the packaged
/// corpus (a path-dependency workdir the caller sets up), run it, and parse the
/// outcome. The productionized form of the Slice B2 measured proof, so the
/// verify-evidence join (`OutputDeterminismVerifyEvidence`) can promote a
/// verified role in `discover-interaction`.
public enum OutputDeterminismVerify {

    /// Emit + build + run the output-determinism verifier for `role` against a
    /// prepared path-dependency `workdir` (its `Package.swift` already declares
    /// the packaged corpus). Returns `.error` when the role can't be verified
    /// (no output collaborator, not recordable/constructible, or a build failure).
    public static func verify(
        role: StatefulRole,
        protocols: [ViewModelProtocolScanner.ProtocolDecl],
        moduleName: String,
        workdir: URL,
        mainFile: URL
    ) throws -> VerifyOutcome {
        guard let output = outputProtocol(for: role, protocols: protocols) else {
            return .error(reason: "no assertable output collaborator")
        }
        guard let source = OutputDeterminismVerifierEmitter.emit(
            role: role,
            outputProtocol: output,
            dependencyProtocols: protocols,
            moduleName: moduleName
        ) else {
            return .error(reason: "role not verifiable (not recordable / constructible)")
        }
        try source.write(to: mainFile, atomically: true, encoding: .utf8)
        let build = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
        guard build.exitCode == 0 else {
            return .error(reason: "build failed: \(build.stderr)")
        }
        return VerifyResultParser.parse(try VerifierSubprocess.runVerifierBinary(workdir: workdir))
    }

    /// The `ProtocolDecl` of the role's assertable output collaborator.
    public static func outputProtocol(
        for role: StatefulRole,
        protocols: [ViewModelProtocolScanner.ProtocolDecl]
    ) -> ViewModelProtocolScanner.ProtocolDecl? {
        let outputCollaborator = role.collaborators.first { collaborator in
            if case .output = collaborator.role { return true }
            return false
        }
        guard let outputCollaborator else { return nil }
        var bare = outputCollaborator.protocolType.trimmingCharacters(in: .whitespaces)
        if bare.hasPrefix("any ") { bare = String(bare.dropFirst(4)) }
        bare = bare.trimmingCharacters(in: CharacterSet(charactersIn: "?! "))
        return protocols.first { $0.name == bare }
    }
}
