import Foundation

/// The SwiftPropertyLaws release a generated stub needs, checked against the release the package
/// actually resolves.
///
/// ## The defect this closes
///
/// A derived generator spells the kit's Foundation generators — `Gen<URL>.url()`,
/// `Gen<Data>.data()` — and those arrived in SwiftPropertyLaws 3.10.0. SwiftLintRuleStudioCore
/// requires the kit `from: "3.0.0"` and resolves **3.3.0**, so the stubs written there failed with
/// *type 'Gen<URL>' has no member 'url'* — which reads as a generator this tool invented, for one
/// that exists a `swift package update` away. Measured: 6 `Gen<URL>.url(` and 4 `Gen<Data>.data(`
/// spellings among 36 stubs accepted on that package.
///
/// So the stub is still written — it is correct against any kit since the floor — and accept says
/// which release it needs and how to get it.
///
/// ## Degradation
///
/// No `Package.resolved`, no `swiftpropertylaws` pin, or a pin by branch or revision with no
/// version: nothing is said. The note is only for a version this can read and compare.
enum KitAPIFloor {

    /// A kit API a stub may spell, and the release that added it.
    struct Floor: Equatable {
        let spelling: String
        let version: [Int]
    }

    static let floors: [Floor] = [
        Floor(spelling: "Gen<Date>.date(", version: [3, 10, 0]),
        Floor(spelling: "Gen<UUID>.uuid(", version: [3, 10, 0]),
        Floor(spelling: "Gen<Data>.data(", version: [3, 10, 0]),
        Floor(spelling: "Gen<URL>.url(", version: [3, 10, 0]),
        Floor(spelling: "Gen<Decimal>.decimal(", version: [3, 11, 0])
    ]

    /// What to tell the reader when `stub` needs a newer kit than `resolved`, or `nil`.
    static func note(stub: String, resolved: [Int]?) -> String? {
        guard let resolved else { return nil }
        let unmet = floors.filter { stub.contains($0.spelling) && isOlder(resolved, than: $0.version) }
        guard let highest = unmet.map(\.version).max(by: isOlder) else { return nil }
        let apis = unmet.map { "`\($0.spelling))`" }.joined(separator: ", ")
        return "this stub calls \(apis), which SwiftPropertyLaws added in \(spelled(highest)); this "
            + "package resolves \(spelled(resolved)), so it will not compile until you run "
            + "`swift package update SwiftPropertyLaws`"
    }

    /// The `swiftpropertylaws` version `Package.resolved` under `packageRoot` pins, or `nil`.
    static func resolvedVersion(packageRoot: URL) -> [Int]? {
        let url = packageRoot.appendingPathComponent("Package.resolved")
        guard let data = try? Data(contentsOf: url),
              let resolved = try? JSONDecoder().decode(ResolvedFile.self, from: data) else { return nil }
        let pins = resolved.pins ?? resolved.object?.pins ?? []
        guard let pin = pins.first(where: { ($0.identity ?? $0.package)?.lowercased() == "swiftpropertylaws" }),
              let version = pin.state.version else { return nil }
        let parts = version.split(separator: ".").compactMap { Int($0) }
        return parts.isEmpty ? nil : parts
    }

    static func isOlder(_ lhs: [Int], than rhs: [Int]) -> Bool {
        for index in 0 ..< max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    private static func spelled(_ version: [Int]) -> String {
        version.map(String.init).joined(separator: ".")
    }
}

/// `Package.resolved`, v2/v3 (`pins` at the top) or v1 (`object.pins`) — what `KitAPIFloor` reads.
private struct ResolvedFile: Decodable {
    let pins: [ResolvedPin]?
    let object: ResolvedObject?
}

private struct ResolvedObject: Decodable {
    let pins: [ResolvedPin]
}

private struct ResolvedPin: Decodable {
    let identity: String?
    let package: String?
    let state: ResolvedState
}

private struct ResolvedState: Decodable {
    let version: String?
}
