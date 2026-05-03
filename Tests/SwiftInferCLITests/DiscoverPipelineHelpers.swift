import Foundation
@testable import SwiftInferCLI

func makeDPFixtureDirectory(name: String) throws -> URL {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("SwiftInferCLITests-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
}

func writeDPFixture(name: String, contents: String) throws -> URL {
    let directory = try makeDPFixtureDirectory(name: name)
    let file = directory.appendingPathComponent("Source.swift")
    try contents.write(to: file, atomically: true, encoding: .utf8)
    return directory
}

/// Substitute the dynamic fixture-directory absolute path with a
/// `<FIXTURE>` placeholder so byte-stable goldens can pin the rest of
/// the diagnostic line. macOS sometimes canonicalises tmp paths
/// through the `/private` symlink during scan; substitute both forms,
/// longest-first, so whichever shape lands in the diagnostic
/// normalises identically.
func normalizeDPDiagnostics(
    _ lines: [String],
    fixture directory: URL
) -> [String] {
    let raw = directory.path
    let withPrivatePrefix = raw.hasPrefix("/private") ? raw : "/private" + raw
    let withoutPrivatePrefix = raw.hasPrefix("/private/")
        ? String(raw.dropFirst("/private".count))
        : raw
    let candidates = [withPrivatePrefix, withoutPrivatePrefix, raw]
        .sorted { $0.count > $1.count }
    return lines.map { line in
        var result = line
        for path in candidates {
            result = result.replacingOccurrences(of: path, with: "<FIXTURE>")
        }
        return result
    }
}

/// In-memory output sink used by the pipeline tests so they can assert
/// against rendered text without going through stdout.
final class DPRecordingOutput: DiscoverOutput, @unchecked Sendable {
    var text: String = ""
    func write(_ text: String) {
        self.text = text
    }
}

/// In-memory diagnostic sink used by the M2.1 vocabulary tests to
/// assert against stderr-bound warnings without writing to the real
/// stderr.
final class DPRecordingDiagnosticOutput: DiagnosticOutput, @unchecked Sendable {
    var lines: [String] = []
    func writeDiagnostic(_ text: String) {
        lines.append(text)
    }
}
