# A scheme or workspace with a control character in a value is written as malformed XML, and XcodeProj can't read it back

## Context 🕵️‍♀️

`XCScheme.write(path:override:)`, `XCWorkspaceData.write(path:override:)` and their `dataRepresentation()` render
through `AEXMLDocument.xmlXcodeFormat` (`Sources/XcodeProj/Extensions/AEXML+XcodeFormat.swift`). It escapes every
attribute value with AEXML's `String.xmlEscaped`, which handles `&`, `<`, `>`, `'`, `"`, `\n`, `\r` and `\t`. XML 1.0
also forbids, outright, the other C0 controls (U+0001–U+0008, U+000B, U+000C, U+000E–U+001F) and U+FFFE and U+FFFF.
No escape can write them; `&#27;` is malformed too. `xmlEscaped` copies them through, so the file XcodeProj writes is
not well-formed, and `XCScheme(path:)` / `XCWorkspaceData(path:)` throw on it.

The values come from callers: an environment variable's value, a pre- or post-action's `scriptText`, a command-line
argument, a file reference's path. Tools that generate schemes from a manifest pass such strings straight through.
#530 is an XcodeGen pre-action script that reached this writer. A terminal colour code pasted into a value, with a
raw ESC (U+001B), is the likeliest way in.

## What 🌱

```swift
import PathKit
import XcodeProj

let launch = XCScheme.LaunchAction(
    runnable: nil,
    buildConfiguration: "Debug",
    environmentVariables: [XCScheme.EnvironmentVariable(variable: "PROMPT", value: "\u{1B}[31m$ \u{1B}[0m", enabled: true)]
)
let path = Path("App.xcscheme")
try XCScheme(name: "App", lastUpgradeVersion: "2600", version: "1.7", launchAction: launch).write(path: path, override: true)
_ = try XCScheme(path: path)
// throws: Error Domain=NSXMLParserErrorDomain Code=9 "(null)"
//   UserInfo={NSXMLParserErrorLineNumber=18, NSXMLParserErrorColumn=22, NSXMLParserErrorMessage=invalid character in attribute value}
```

Line 18 of `App.xcscheme`, through `cat -v`: `value = "^[[31m$ ^[[0m"`. A workspace does the same: a `FileRef` at
`.group("a\u{1}b.swift")` is written as `location = "group:a^Ab.swift"`, and `XCWorkspaceData(path:)` throws code 9
at line 5. With `"red $ "` and `"ab.swift"` instead, both files read back. Every one of the 30 code points fails the
same way.

## Proposal 🎉

Replace each of those characters with U+FFFD in `xmlXcodeFormat`, after `xmlEscaped`:

```diff
--- a/Sources/XcodeProj/Extensions/AEXML+XcodeFormat.swift
+++ b/Sources/XcodeProj/Extensions/AEXML+XcodeFormat.swift
@@ -124,7 +124,7 @@ extension AEXMLElement {
         func print(key: String, value: String) {
             xml += "\n"
             xml += indent(withDepth: parentsCount)
-            xml += "\(key) = \"\(value.xmlEscaped)\""
+            xml += "\(key) = \"\(value.xcodeFormatEscaped)\""
         }
 
         if !attributes.isEmpty {
@@ -156,7 +156,7 @@ extension AEXMLElement {
                 // insert string value and close element
                 xml += ">\n"
                 xml += indent(withDepth: parentsCount - 1)
-                xml += ">\n\(string.xmlEscaped)"
+                xml += ">\n\(string.xcodeFormatEscaped)"
             }
         }
 
@@ -190,3 +190,21 @@ extension AEXMLElement {
         return indent
     }
 }
+
+extension String {
+    /// `xmlEscaped`, with U+FFFD in place of each character XML 1.0 cannot hold at all, even as a reference:
+    /// a C0 control other than tab, line feed and carriage return, U+FFFE or U+FFFF. A file holding one is not
+    /// well-formed, so neither XcodeProj nor any other XML reader can load it.
+    fileprivate var xcodeFormatEscaped: String {
+        var scalars = String.UnicodeScalarView()
+        for scalar in xmlEscaped.unicodeScalars {
+            switch scalar {
+            case "\u{0}"..."\u{8}", "\u{B}", "\u{C}", "\u{E}"..."\u{1F}", "\u{FFFE}", "\u{FFFF}":
+                scalars.append("\u{FFFD}")
+            default:
+                scalars.append(scalar)
+            }
+        }
+        return String(scalars)
+    }
+}
```

This loses the character, but the file stays loadable. The alternative is to throw from `write` and
`dataRepresentation`, which would mean `xmlXcodeFormat` throwing too. Output without these characters is unchanged.

I have an XCTest file, `Tests/XcodeProjTests/Extensions/XcodeFormatForbiddenCharacterTests.swift`, with four tests:
the scheme and the workspace above, all 30 code points in an attribute value, and a control (`&`, `<`, `>`, quotes,
tab and newline, which round-trip today). On `main` the three tests fail (32 assertions) and the control passes.
With the patch all four pass, and so does the full `swift test`: 387 XCTest and 95 Swift Testing tests. Happy to
open a PR with both.

AEXML's own `xml` output has the same gap in `String.xmlEscaped` (4.7.3, unchanged on its `master`). I have not
reported it there.

**Environment.** XcodeProj `main` at `948280a` (AEXML 4.7.3). Xcode 27.2 (Swift 6.4.2), macOS 27.2, arm64.

Found while checking whether XML written by Swift packages parses.
