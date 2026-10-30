// Drop into Tests/FoundationEssentialsTests/ and run
//     swift test --filter XMLPlistForbiddenCharacterTests
// The first test fails on `main` for all 30 arguments: `encode` returns a document that is not well-formed XML.
import Testing

#if FOUNDATION_FRAMEWORK
@testable import Foundation
#elseif canImport(FoundationEssentials)
@testable import FoundationEssentials
#endif

@Suite("XML property list: characters XML 1.0 forbids")
private struct XMLPlistForbiddenCharacterTests {
    /// The characters XML 1.0's `Char` production leaves out, other than NUL (which #2039 already rejects):
    /// U+0001–U+0008, U+000B, U+000C, U+000E–U+001F, U+FFFE and U+FFFF. No escape writes them, not even `&#1;`.
    static let forbidden: [UInt32] = Array(0x01...0x08) + [0x0B, 0x0C] + Array(0x0E...0x1F) + [0xFFFE, 0xFFFF]

    @Test(arguments: forbidden)
    func xmlEncodingRejectsStringsWithForbiddenCharacters(scalar: UInt32) throws {
        let character = String(Unicode.Scalar(scalar)!)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml

        #expect(throws: (any Error).self, "a value holding U+\(String(scalar, radix: 16))") {
            _ = try encoder.encode(["key": "a\(character)b"])
        }
        #expect(throws: (any Error).self, "a key holding U+\(String(scalar, radix: 16))") {
            _ = try encoder.encode(["k\(character)y": "value"])
        }
    }

    /// Control: tab, line feed, DEL, NEL, other scalars led by the byte EF (U+FEFF, U+FF01, U+FFFD) and a
    /// noncharacter outside the BMP are all XML characters, and still round-trip.
    @Test(arguments: [0x09, 0x0A, 0x7F, 0x85, 0xFEFF, 0xFF01, 0xFFFD, 0x1FFFE] as [UInt32])
    func xmlEncodingAcceptsOtherCharacters(scalar: UInt32) throws {
        let value = ["k": "a" + String(Unicode.Scalar(scalar)!) + "b"]
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(value)
        #expect(try PropertyListDecoder().decode([String: String].self, from: data) == value)
    }
}
