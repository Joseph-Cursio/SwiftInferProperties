import Foundation
import Testing

@testable import SwiftInferCore

// MARK: - M: hidden is a name, not a flag

extension ConstructionUniverseSymlinkTests {

    /// Sets the macOS `UF_HIDDEN` flag on `url` (what `chflags hidden` sets), reporting whether it held.
    static func setHiddenFlag(on url: URL) -> Bool {
        var target = url
        var values = URLResourceValues()
        values.isHidden = true
        guard (try? target.setResourceValues(values)) != nil else { return false }
        target.removeAllCachedResourceValues()
        return (try? target.resourceValues(forKeys: [.isHiddenKey]))?.isHidden == true
    }

    /// Whether this volume takes the flag at all — the suite's cases are skipped where it does not.
    static let hiddenFlagIsAvailable: Bool = {
        let probe = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("uf-hidden-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: probe.path, contents: Data()) else { return false }
        defer { try? FileManager.default.removeItem(at: probe) }
        return setHiddenFlag(on: probe)
    }()

    /// The shared spec's amendment M: SwiftPM compiles a file or directory carrying `UF_HIDDEN`
    /// (`chflags hidden`), so neither walk skips one — the review found SwiftProjectLint's did, and
    /// dropped a compiled `UUID`-minting type. A flagged file in a scanned SYMLINKED target is the
    /// case this repo got wrong: the root walk never enters the link, and the union read the
    /// scanned directory through `SwiftSourceFiles`, which skips the flag.
    @Test("a UF_HIDDEN file or directory is in the universe", .enabled(if: Self.hiddenFlagIsAvailable))
    func hiddenFlagIsNotHiddenName() throws {
        let outside = try Wiring.makePackage(
            ["Lib/Make.swift": Wiring.make, "Lib/Flagged.swift": "struct Flagged {}"], manifest: false
        )
        defer { try? FileManager.default.removeItem(at: outside) }
        let root = try Wiring.makePackage([
            "Sources/Model/Item.swift": Wiring.item,
            "Sources/Model/Stamp.swift": "struct Stamp { let at = Date() }",
            "Sources/FlaggedDir/InFlagged.swift": "struct InFlagged { let id = UUID() }",
            "Sources/Model/.Dotted.swift": "struct Dotted { let id = UUID() }",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.link("Sources/Lib", in: root, to: outside.appendingPathComponent("Lib").path)
        for flagged in ["Sources/Model/Stamp.swift", "Sources/FlaggedDir"] {
            #expect(Self.setHiddenFlag(on: root.appendingPathComponent(flagged)), "\(flagged) took no flag")
        }
        #expect(Self.setHiddenFlag(on: outside.appendingPathComponent("Lib/Flagged.swift")))
        let lib = root.appendingPathComponent("Sources/Lib")
        #expect(ConstructionUniverse.files(forScanOf: lib).map(\.relativePath) == [
            "Sources/FlaggedDir/InFlagged.swift", "Sources/Lib/Flagged.swift", "Sources/Lib/Make.swift",
            "Sources/Model/Item.swift", "Sources/Model/Stamp.swift",
        ], "a dot-prefixed name stays out; a flagged one does not")
    }
}
