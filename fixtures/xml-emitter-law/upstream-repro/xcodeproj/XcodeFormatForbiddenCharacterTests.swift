// Drop into Tests/XcodeProjTests/Extensions/ and run `swift test --filter XcodeFormatForbiddenCharacterTests`.
// Each test writes a scheme or a workspace through XcodeProj's public API, then reads it back with XcodeProj.
// On `main`, every test except the control fails: the file is written, but it is not well-formed XML.
import Foundation
import PathKit
import XCTest
@testable import XcodeProj

final class XcodeFormatForbiddenCharacterTests: XCTestCase {
    private var directory: Path!

    override func setUpWithError() throws {
        directory = try Path.uniqueTemporary()
    }

    override func tearDownWithError() throws {
        try? directory.delete()
    }

    private func scheme(environmentValue: String) -> XCScheme {
        let launchAction = XCScheme.LaunchAction(
            runnable: nil,
            buildConfiguration: "Debug",
            environmentVariables: [XCScheme.EnvironmentVariable(variable: "PROMPT", value: environmentValue, enabled: true)]
        )
        return XCScheme(name: "App", lastUpgradeVersion: "2600", version: "1.7", launchAction: launchAction)
    }

    /// A pasted terminal colour code (ESC, U+001B) in an environment variable's value.
    func test_scheme_withEscapeInEnvironmentVariable_canBeReadBack() throws {
        let path = directory + "App.xcscheme"
        try scheme(environmentValue: "\u{1B}[31m$ \u{1B}[0m").write(path: path, override: true)
        XCTAssertNoThrow(try XCScheme(path: path))
    }

    /// U+0001 in a workspace file reference's path.
    func test_workspace_withControlCharacterInPath_canBeReadBack() throws {
        let path = directory + "contents.xcworkspacedata"
        let workspace = XCWorkspaceData(children: [.file(XCWorkspaceDataFileRef(location: .group("a\u{1}b.swift")))])
        try workspace.write(path: path, override: true)
        XCTAssertNoThrow(try XCWorkspaceData(path: path))
    }

    /// Every character XML 1.0 forbids outright, in an attribute value.
    func test_xmlXcodeFormat_isWellFormed_forEveryForbiddenCharacter() throws {
        let forbidden = (0x01 ... 0x1F).filter { ![0x09, 0x0A, 0x0D].contains($0) } + [0xFFFE, 0xFFFF]
        for value in forbidden {
            let character = String(Unicode.Scalar(UInt32(value))!)
            let data = try XCTUnwrap(scheme(environmentValue: "a\(character)b").dataRepresentation())
            XCTAssertTrue(XMLParser(data: data).parse(), "U+\(String(value, radix: 16, uppercase: true))")
        }
    }

    /// Control: the characters `xmlEscaped` handles today.
    func test_scheme_withPredefinedEntitiesAndWhitespace_roundTrips() throws {
        let value = "a < b & \"c\" 'd' >\te\nf"
        let path = directory + "App.xcscheme"
        try scheme(environmentValue: value).write(path: path, override: true)
        XCTAssertEqual(try XCScheme(path: path).launchAction?.environmentVariables?.first?.value, value)
    }
}
