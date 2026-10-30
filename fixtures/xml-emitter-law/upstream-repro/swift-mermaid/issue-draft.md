# `svgString()` writes malformed SVG when a label holds a control character, or `<` or `&` before a combining mark

`escapeText(_:)` in `Sources/Mermaid/Core/SVGRenderer.swift` escapes `&`, `<` and `>`, and copies every other
`Character` unchanged. Two kinds of label text get through it, and either makes the whole document fail to parse as
XML:

1. **Characters XML 1.0 forbids outright**: the C0 controls other than tab, LF and CR, and U+FFFE and U+FFFF. No
   escape can write them; `&#1;` is malformed too.
2. **`<` or `&` followed by a combining mark.** `<` + U+0301 COMBINING ACUTE ACCENT is one `Character`, and it is
   not `"<"`, so the `switch` falls to `default` and writes the `<` raw.

Both arrive from diagram source, through the public API:

```swift
import Foundation
import Mermaid

let svg = try Mermaid.render("flowchart LR\n  A[a\u{1}b] --> B[ok]").svgString()
print(XMLParser(data: Data(svg.utf8)).parse())  // false
```

Line 6 of the document, through `cat -v`:

```
<text x="46" y="41.82" font-family="Helvetica, 'Helvetica Neue', Helvetica, Arial, sans-serif" font-size="16" fill="#333333" text-anchor="middle" dominant-baseline="alphabetic">a^Ab</text>
```

| source, as a Swift string passed to `Mermaid.render` | `XMLParser`'s first error |
|---|---|
| `"flowchart LR\n  A[a\u{1}b] --> B[ok]"` | 9, PCDATA invalid Char value 1 |
| `"flowchart LR\n  A[a \u{1B}[1mb\u{1B}[0m] --> B[ok]"` (ESC, as pasted from a terminal) | 9, PCDATA invalid Char value 27 |
| `"flowchart LR\n  A[a\u{FFFE}b] --> B[ok]"` | 9, Char 0xFFFE out of allowed range |
| `"sequenceDiagram\n  Alice->>Bob: hi\u{7}there"` | 9, PCDATA invalid Char value 7 |
| `"flowchart LR\n  A[a <\u{301} b] --> B[ok]"` | 68, StartTag: invalid element name |
| `"flowchart LR\n  A[a &\u{301} b] --> B[ok]"` | 68, xmlParseEntityRef: no name |
| `"flowchart LR\n  A[a & b < c] --> B[ok]"` (control) | well-formed |

These characters are rare in a hand-written diagram, but nothing between `Mermaid.render` and `svgString()` filters
them. A document that holds one is rejected as a whole by any XML or SVG reader.

## A possible fix

Walk scalars instead of `Character`s, and write U+FFFD for what XML can't hold. `escapeAttr` builds on `escapeText`;
its `"` replacement also misses a `"` followed by a combining mark, so it gets `options: .literal`:

```diff
--- a/Sources/Mermaid/Core/SVGRenderer.swift
+++ b/Sources/Mermaid/Core/SVGRenderer.swift
@@ -90,15 +90,20 @@ enum SVGPath {
     }
 }
 
+/// Escapes `&`, `<` and `>`, and writes U+FFFD for a character XML 1.0 cannot hold at all, even as a
+/// reference: a C0 control other than tab, LF and CR, or U+FFFE / U+FFFF. Walks scalars, not Characters:
+/// "<" followed by a combining mark is one Character, and it is not "<".
 func escapeText(_ s: String) -> String {
     var out = ""
-    out.reserveCapacity(s.count)
-    for ch in s {
-        switch ch {
+    out.reserveCapacity(s.utf8.count)
+    for scalar in s.unicodeScalars {
+        switch scalar {
         case "&": out += "&amp;"
         case "<": out += "&lt;"
         case ">": out += "&gt;"
-        default: out.append(ch)
+        case "\t", "\n", "\r": out.unicodeScalars.append(scalar)
+        case "\u{0}"..."\u{1F}", "\u{FFFE}", "\u{FFFF}": out += "\u{FFFD}"
+        default: out.unicodeScalars.append(scalar)
         }
     }
     return out
@@ -106,6 +111,6 @@ func escapeText(_ s: String) -> String {
 
 func escapeAttr(_ s: String) -> String {
     var out = escapeText(s)
-    out = out.replacingOccurrences(of: "\"", with: "&quot;")
+    out = out.replacingOccurrences(of: "\"", with: "&quot;", options: .literal)
     return out
 }
```

Output changes only for text holding one of those characters, so the byte-stable SVG stays as it is for everything
else. The control above comes out byte for byte the same. I have an XCTest file, `SVGTextWellFormedTests.swift`, with
the sources above and a check of every forbidden code point through `escapeText`. On `main`, 7 of its 8 tests fail and
the control passes. With the patch all 8 pass, and so do the other 121 tests in `swift test`. Happy to open a PR with
both.

**Environment.** `main` at `ee4b50b`. Xcode 27.2 (Swift 6.4.2), macOS 27.2, arm64.

Found while checking whether XML written by Swift packages parses.
