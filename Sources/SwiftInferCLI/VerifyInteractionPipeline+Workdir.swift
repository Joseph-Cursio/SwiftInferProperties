import Foundation
import SwiftInferCore

/// Cycle 120 — workdir/package-root helpers for the interaction verify
/// pipeline, split out of the main file so the core enum body stays under
/// SwiftLint's `file_length` cap (mirrors the `+Evidence` split).
extension VerifyInteractionPipeline {

    /// Cycle 129 — registry of per-workdir-path build locks. The survey
    /// runs identities concurrently; identities sharing a workdir (the
    /// shared TCA corpus workdir) must serialize their synthesize → build →
    /// run so they reuse the warm `.build` instead of clobbering each
    /// other, while identities in distinct workdirs (non-TCA per-reducer)
    /// get distinct locks and stay parallel. Access to the dictionary is
    /// guarded by `workdirLockRegistry`; the returned `NSLock`s are held
    /// across the (synchronous) build, never across an `await`.
    private static let workdirLockRegistry = NSLock()
    nonisolated(unsafe) private static var workdirLocksByPath: [String: NSLock] = [:]

    static func workdirLock(forPath path: String) -> NSLock {
        workdirLockRegistry.lock()
        defer { workdirLockRegistry.unlock() }
        if let existing = workdirLocksByPath[path] { return existing }
        let lock = NSLock()
        workdirLocksByPath[path] = lock
        return lock
    }

    /// The workdir + synthesis inputs for a candidate. Cycle 122: `.tca`
    /// carriers build via direct source inclusion (corpus co-compiled into
    /// the verifier so `internal` types resolve) + a CA-bearing package;
    /// other carriers keep the v1.42 path-dependency model. Cycle 129: TCA
    /// identities share ONE corpus-keyed workdir (heavy deps compile once;
    /// later identities are stub-only incrementals) — non-TCA keeps the
    /// per-(reducer, identity) segment.
    /// The inputs `executeAndParse` resolves before synthesizing a workdir.
    struct WorkdirRequest {
        let candidate: ReducerCandidate
        let stubSource: String
        let userModuleName: String
        let packageRoot: URL
        let identity: String?
        let corpusSourceDirectory: URL?
    }

    static func makeWorkdirInputs(
        _ request: WorkdirRequest
    ) -> (workdir: URL, inputs: VerifierWorkdir.Inputs) {
        // `.tca` / `.mobius` reducers reference framework types, so the corpus
        // is co-compiled INTO the verifier target (direct source inclusion)
        // with that framework declared as a package dependency — vs the
        // standard path-dependency model for plain-Swift carriers.
        let inlinedMode = inlinedCorpusMode(for: request.candidate.carrierKind)
        let usesInlinedCorpus = inlinedMode != nil && request.corpusSourceDirectory != nil
        let segment = usesInlinedCorpus
            ? "\(request.candidate.carrierKind.rawValue)-corpus-"
                + request.userModuleName.replacingOccurrences(of: ".", with: "_")
            : workdirSegment(for: request.candidate, identity: request.identity)
        let workdir = request.packageRoot
            .appendingPathComponent(".swiftinfer")
            .appendingPathComponent("verify-interaction-workdir")
            .appendingPathComponent(segment)
        if let mode = inlinedMode, let corpusSourceDirectory = request.corpusSourceDirectory {
            return (workdir, VerifierWorkdir.Inputs(
                workdir: workdir,
                userPackage: nil,
                stubSource: request.stubSource,
                mode: mode,
                inlinedSources: (try? CorpusPackager.readSwiftSources(in: corpusSourceDirectory)) ?? []
            ))
        }
        return (workdir, VerifierWorkdir.Inputs(
            workdir: workdir,
            userPackage: VerifierWorkdir.UserPackageReference(
                packagePath: request.packageRoot,
                productNames: [request.userModuleName]
            ),
            stubSource: request.stubSource,
            mode: .interaction
        ))
    }

    /// The direct-source-inclusion workdir mode for a carrier whose reducer
    /// references framework types (`.tca` → ComposableArchitecture, `.mobius`
    /// → MobiusCore), or `nil` for the plain-Swift path-dependency carriers.
    private static func inlinedCorpusMode(for kind: ReducerCarrierKind) -> WorkdirMode? {
        switch kind {
        case .tca: return .interactionTCA
        case .mobius: return .interactionMobius
        case .generic, .elmStyle, .reSwift, .workflow: return nil
        }
    }

    /// Walk up from `directory` looking for `Package.swift`. Same shape as
    /// v1.42 verify's package-root resolution + every other loader in the
    /// project — kept inlined here for the same independent-loader posture.
    static func findPackageRoot(startingFrom directory: URL) -> URL? {
        var current = directory.standardizedFileURL
        while true {
            let manifest = current.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: manifest.path) {
                return current
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent == current {
                return nil
            }
            current = parent
        }
    }

    /// Cycle 122 (Phase A) — the corpus's source directory
    /// (`<workingDirectory>/Sources/<target>`), the same layout
    /// `resolveAndEmit` discovers from. Passed to `executeAndParse` so a
    /// `.tca` build can co-compile those sources into the verifier target
    /// (direct source inclusion). Non-`.tca` builds ignore it.
    static func corpusSourceDirectory(target: String, workingDirectory: URL) -> URL {
        workingDirectory
            .appendingPathComponent("Sources")
            .appendingPathComponent(target)
    }

    /// Filename-safe workdir segment from the candidate's qualified
    /// name (`.` → `_`, so `Inbox.body` → `Inbox_body`). Cycle 120:
    /// a non-nil `identity` (the invariant's normalized 16-char hash)
    /// appends `__<identity>` so sibling identities on one reducer get
    /// distinct workdirs and can build concurrently; `nil` (the bare
    /// `runPipeline` path) preserves the reducer-only segment exactly.
    static func workdirSegment(
        for candidate: ReducerCandidate,
        identity: String? = nil
    ) -> String {
        let base = candidate.qualifiedName.replacingOccurrences(of: ".", with: "_")
        guard let identity, !identity.isEmpty else { return base }
        return "\(base)__\(identity)"
    }
}
