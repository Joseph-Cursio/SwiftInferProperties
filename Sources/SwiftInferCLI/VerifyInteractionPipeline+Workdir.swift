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
        // Tier 2 — depend on the library product that vends the reducer module
        // (may differ from the module name); the stub still imports the module.
        let product = PackageProductResolver.libraryProduct(
            exposingModule: request.userModuleName,
            packageRoot: request.packageRoot
        ) ?? request.userModuleName
        return (workdir, VerifierWorkdir.Inputs(
            workdir: workdir,
            userPackage: VerifierWorkdir.UserPackageReference(
                packagePath: request.packageRoot,
                productNames: [product]
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

    /// Walk up from `directory` looking for `Package.swift`.
    ///
    /// Shares `DirectoryAncestors` with every other loader rather than the walk itself. The
    /// independent-loader posture the previous comment described is about API coupling; it was
    /// never an argument for seven copies of an untestable loop.
    static func findPackageRoot(startingFrom directory: URL) -> URL? {
        DirectoryAncestors.nearest(from: directory) { candidate in
            FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("Package.swift").path
            )
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
    ///
    /// The segment is `nameSegment(_:)`, which is injective: `Outer.Inner.body` and
    /// `Outer_Inner.body` used to share one segment, so a run on one overwrote the other's
    /// trace and shared its workdir (#716).
    static func workdirSegment(
        for candidate: ReducerCandidate,
        identity: String? = nil
    ) -> String {
        let base = nameSegment(candidate.qualifiedName)
        guard let identity, !identity.isEmpty else { return base }
        return "\(base)__\(identity)"
    }

    /// An injective spelling of a qualified name (#716).
    ///
    /// Injective, not sanitising: only `_`, `.` and `-` are rewritten. Anything else passes
    /// through as it always has, so a backticked name (`` `Default`.body ``) or a generic
    /// extension's (`Foo<Int>.body`) still yields a segment that is not a Swift identifier.
    ///
    /// - **A name with no `_` and no `-`** keeps the historical spelling, `.` → `_`
    ///   (`Inbox.body` → `Inbox_body`). Every `_` in it was a dot, so it decodes, and every
    ///   existing workdir and trace path for such a name stays where it was.
    /// - **Any other name** is spelled `__` followed by a prefix-free escape: `_` → `_u`,
    ///   `.` → `_d`, `-` → `_h` (`Outer_Inner.body` → `__Outer_uInner_dbody`). Inside the
    ///   escape every `_` is followed by `u`, `d` or `h`, so it decodes too.
    ///
    /// The two families cannot meet: a plain spelling never starts with `_` (a Swift name with
    /// no `_` starts with a letter), and an escaped one always does. Nor can either meet the
    /// `__<identity>` suffix `workdirSegment` appends: a plain spelling holds no `__`, and in
    /// an escaped one `__` occurs only as the leading marker.
    static func nameSegment(_ qualifiedName: String) -> String {
        guard qualifiedName.contains(where: { $0 == "_" || $0 == "-" }) else {
            return qualifiedName.replacingOccurrences(of: ".", with: "_")
        }
        var escaped = "__"
        for character in qualifiedName {
            switch character {
            case "_": escaped += "_u"
            case ".": escaped += "_d"
            case "-": escaped += "_h"
            default: escaped.append(character)
            }
        }
        return escaped
    }
}
