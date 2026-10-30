# Exported SVG is malformed, and Graffle can't import it back, when a layer name or text holds a control character

`SVGExport.escape(_:)` replaces `&`, `<`, `>` and `"`, and nothing else. Two kinds of text get through it into a
`data-name` attribute or a `<tspan>`, and either one makes the whole SVG fail to parse:

1. **Characters XML 1.0 forbids outright**: the C0 controls other than tab, LF and CR, and U+FFFE and U+FFFF. No
   escape can write them; `&#1;` is malformed too.
2. **`<` followed by a combining mark.** `replacingOccurrences(of: "<", with: "&lt;")` compares whole characters,
   and `<` + U+0301 COMBINING ACUTE ACCENT is one character, so the `<` is written raw. `&` and `"` go the same way.

The app's own self-test ("SVG export is well-formed …") checks the export with `XMLDocument`, and `SVGImport` reads
`data-name` back with it. So **Export as SVG…** gives a file that **Import SVG** refuses.

```swift
@testable import Graffle

var drawing = Drawing()
drawing.layers[0].name = "Layer\u{1}1"
let svg = SVGExport.svg(for: drawing, bounds: CGRect(x: 0, y: 0, width: 400, height: 300))
XMLParser(data: Data(svg.utf8)).parse()           // false: code 9, "invalid character in attribute value", line 4
try SVGImport.parse(Data(svg.utf8), name: "x")    // throws unreadable("Line 4: invalid character in attribute value …")
```

| input | where it lands | `XMLParser`'s first error | `SVGImport.parse` |
|---|---|---|---|
| layer name `"Layer\u{1}1"` | `data-name="…"` | 9, invalid character in attribute value | throws |
| rectangle text `"x\u{1B}[0my"` (ESC) | `<tspan>` | 9, PCDATA invalid Char value 27 | throws |
| connector label `"go\u{1}now"` | `<tspan>` | 9, PCDATA invalid Char value 1 | throws |
| layer name `"a <\u{301} b"` | `data-name="…"` | 38, Unescaped '<' not allowed in attributes values | throws |
| layer name `"Tom & \"Jerry\" <3>"`, text `"a < b & c"` (control) | | well-formed | reads it |

These are not characters anyone types, but they arrive by paste. `CanvasView.renameLayer` trims only whitespace, and
`endEditing` stores the text field's `stringValue` as it is. I have not driven this through the UI. The table comes
from an XCTest file that calls `SVGExport.svg` directly, the same call `CanvasView.svgData()` makes for
**Export as SVG…**.

## A possible fix

Walk scalars, and write U+FFFD for what XML can't hold:

```diff
--- a/Sources/Graffle/SVGExport.swift
+++ b/Sources/Graffle/SVGExport.swift
@@ -26,9 +26,24 @@ enum SVGExport {
 
     fileprivate static func hex(_ c: NSColor) -> String { hex(RGBA(c)) }
 
+    /// Escapes `&`, `<`, `>` and `"`, and writes U+FFFD for a character XML 1.0 can't hold at all, even as a
+    /// reference: a C0 control other than tab, LF and CR, or U+FFFE / U+FFFF. Works on scalars: a `<` followed by a
+    /// combining mark is one Character, and `replacingOccurrences(of: "<", …)` doesn't find the `<` in it.
     fileprivate static func escape(_ s: String) -> String {
-        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
-            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
+        var out = ""
+        out.reserveCapacity(s.utf8.count)
+        for scalar in s.unicodeScalars {
+            switch scalar {
+            case "&": out += "&amp;"
+            case "<": out += "&lt;"
+            case ">": out += "&gt;"
+            case "\"": out += "&quot;"
+            case "\t", "\n", "\r": out.unicodeScalars.append(scalar)
+            case "\u{0}"..."\u{1F}", "\u{FFFE}", "\u{FFFF}": out += "\u{FFFD}"
+            default: out.unicodeScalars.append(scalar)
+            }
+        }
+        return out
     }
```

Output changes only for text that holds one of those characters. With the patch, every row above is well-formed and
imports back. The repository has no test target, so I added one locally:
`.testTarget(name: "GraffleTests", dependencies: ["Graffle"], path: "Tests/GraffleTests")`, with
`@testable import Graffle`. Its five tests are the rows above. On `main`, four fail and the control passes. With the
patch all five pass. `.build/debug/Graffle --selftest` prints `ALL PASSED` with and without the patch. Happy to open
a PR with the fix, with or without the test target.

**Environment.** `main` at `53b93b0`. Xcode 27.2 (Swift 6.4.2), macOS 27.2, arm64.

Found while checking whether XML written by Swift packages parses.
