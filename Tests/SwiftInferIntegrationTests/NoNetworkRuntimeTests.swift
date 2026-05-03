import Foundation
import Testing
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter

/// PRD v0.4 §14 + §19 success criterion — "All §14 privacy guarantees
/// are testable: integration test verifies no network sockets opened
/// during any subcommand." The contract was implicitly covered by the
/// static no-networking-APIs grep in `HardGuaranteeTests`, but PRD §19
/// explicitly asks for a runtime test.
///
/// **What this test catches.** A globally-registered `URLProtocol`
/// records any URLSession-routed request attempted by the discover /
/// drift / TestLifter code paths. The static grep covers raw
/// `Network.framework` and `Process()`-shelled-out paths via source
/// inspection; the runtime check covers accidental URLSession
/// introduction that the grep wouldn't catch (e.g. a future
/// `URL(string:).resolvedAddress` reach-through, or a third-party
/// dep loading config from a remote URL).
///
/// **Out of scope.** Raw BSD sockets, CFNetwork at the SocketStream
/// level, and unaddressable remote DNS lookups bypass URLProtocol.
/// Those paths are caught by the static grep (`import Network`
/// forbidden); the runtime test layers a second line of defense for
/// the URLSession-shaped case. Open decision #5 in
/// `docs/v1.0 Release Plan.md`.
///
/// R1.1.h — closes the §14 + §19 runtime gap before the v1.0 cut.
@Suite("Privacy — PRD §14 + §19 runtime no-network (R1.1.h)")
struct NoNetworkRuntimeTests {

    @Test("discover + drift + TestLifter open zero URLSession-routed network requests at runtime (PRD §14 + §19)")
    func subcommandsOpenNoNetworkSockets() throws {
        URLProtocol.registerClass(NetworkInterceptor.self)
        defer { URLProtocol.unregisterClass(NetworkInterceptor.self) }
        NetworkInterceptor.reset()

        let packageRoot = try makePackageRoot()
        defer { try? FileManager.default.removeItem(at: packageRoot) }

        let target = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("Lib")
        try writeSyntheticCorpus(at: target)
        try writeTestSuite(at: packageRoot.appendingPathComponent("Tests"))

        // 1. Discover
        try SwiftInferCommand.Discover.run(
            directory: target,
            output: SilentOutput(),
            diagnostics: SilentDiagnosticOutput()
        )

        // 2. Drift
        try SwiftInferCommand.Drift.run(
            directory: target,
            output: SilentOutput(),
            diagnostics: SilentDiagnosticOutput()
        )

        // 3. TestLifter
        _ = try TestLifter.discover(in: packageRoot)

        let captured = NetworkInterceptor.captured()
        #expect(
            captured.isEmpty,
            "Runtime network interception caught \(captured.count) URLSession request(s) during discover/drift/TestLifter — §14 + §19 forbid any: \(captured.map(\.absoluteString))"
        )
    }

    // MARK: - Synthetic corpus

    private func makePackageRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftInferNoNet-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("// swift-tools-version: 6.1\n".utf8).write(
            to: root.appendingPathComponent("Package.swift")
        )
        return root
    }

    private func writeSyntheticCorpus(at directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        struct Payload {}
        struct DataBlob {}

        struct Container {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
            func encode(_ value: Payload) -> DataBlob {
                return DataBlob()
            }
            func decode(_ data: DataBlob) -> Payload {
                return Payload()
            }
        }
        """.write(
            to: directory.appendingPathComponent("Source.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeTestSuite(at directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        import XCTest

        final class CodecTests: XCTestCase {
            func testRoundTrip() {
                let original = Payload()
                let encoded = encode(original)
                let decoded = decode(encoded)
                XCTAssertEqual(original, decoded)
            }
        }
        """.write(
            to: directory.appendingPathComponent("CodecTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }
}

// MARK: - URLProtocol interceptor

/// Global URLProtocol that captures every request URLSession routes
/// through it. Returning `true` from `canInit(with:)` opts the request
/// in; `startLoading` immediately fails it so URLSession returns an
/// error to the caller — no real network I/O happens. The captured
/// request list is what the assertion gates on.
private final class NetworkInterceptor: URLProtocol {

    private static let lock = NSLock()
    nonisolated(unsafe) private static var capturedRequests: [URLRequest] = []

    static func reset() {
        lock.lock()
        capturedRequests.removeAll()
        lock.unlock()
    }

    static func captured() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests.compactMap(\.url)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        lock.lock()
        capturedRequests.append(request)
        lock.unlock()
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }

    override func stopLoading() {}
}

// MARK: - Silent stubs

private final class SilentOutput: DiscoverOutput, @unchecked Sendable {
    func write(_ text: String) {}
}

private final class SilentDiagnosticOutput: DiagnosticOutput, @unchecked Sendable {
    func writeDiagnostic(_ text: String) {}
}
