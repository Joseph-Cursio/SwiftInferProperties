# Checkstyle, JUnit and GitLab reports can be malformed XML: control characters and `<` before a combining mark get through

### New Issue Checklist

- [x] I've Updated SwiftLint to the latest version.
- [x] I've searched for [existing GitHub issues](https://github.com/realm/SwiftLint/issues).

### Bug Description

`String.escapedForXML()` (`Source/SwiftLintFramework/Extensions/String+XML.swift`) replaces `&`, `"`, `'`, `>` and
`<`, and nothing else. Two kinds of text get through it, and either one makes a `checkstyle`, `junit` or `gitlab`
report malformed, so a tool that parses the report as XML rejects all of it:

1. **C0 control characters.** XML 1.0 does not allow U+0001–U+0008, U+000B, U+000C or U+000E–U+001F anywhere in a
   document, not even as a character reference (`&#27;` is just as malformed), and U+FFFE and U+FFFF are out too.
   `escapedForXML` copies them through.
2. **`<`, `&`, `"` or `'` followed by a combining mark.** `replacingOccurrences(of:with:)` matches whole
   `Character`s, and `<` followed by U+0301 COMBINING ACUTE ACCENT is one `Character`, which is not `<`. So the `<`
   is written raw.

Both are reachable with only the default rules, from Swift that compiles: `todo` copies up to 30 characters of the
comment into the reason, and the compiler accepts these characters in a comment. A pasted terminal colour code
(ESC, U+001B) is the likeliest way in. A `custom_rules` message or a file path gets there the same way.

Separately, `GitLabJUnitReporter` writes `violation.ruleIdentifier` unescaped, in the `testcase` name and in the
body, so a `custom_rules` key such as `a<b` breaks the `gitlab` report. (`CheckstyleReporter` escapes the identifier,
and `JUnitReporter` does not write it.)

```bash
mkdir repro && cd repro && touch .swiftlint.yml
printf '// TODO: \033[1mbold\033[0m later\nlet y = 2\n' > Todo.swift   # ESC pasted into a comment
swiftc -typecheck Todo.swift                                        # compiles
swiftlint lint --quiet --reporter checkstyle > checkstyle.xml
xmllint --noout checkstyle.xml
# checkstyle.xml:5: parser error : invalid character in attribute value
```

Line 5 of `checkstyle.xml`, through `cat -v`:

```
<error line="1" column="4" severity="warning" message="TODOs should be resolved (^[[1mbold^[[0m later)" source="swiftlint.rules.todo"/>
```

Each input, run the same way with each reporter (`xmllint`'s first error; Foundation's `XMLParser` fails on the
same line, with code 9, 38 or 68):

| input | `checkstyle` | `junit` | `gitlab` |
|---|---|---|---|
| `// TODO: ␛[1mbold␛[0m later` (ESC) | invalid character in attribute value | invalid character in attribute value | PCDATA invalid Char value 27 |
| `// TODO: use a <́ b` (`<` + U+0301, written `printf '// TODO: use a <\314\201 b\n'`) | Unescaped '<' not allowed in attributes values | Unescaped '<' not allowed in attributes values | StartTag: invalid element name |
| `custom_rules` key `"a<b"` (config below) | well-formed | well-formed | Unescaped '<' not allowed in attributes values |

**Expected:** a well-formed report in each case.

### Proposed fix

Walk Unicode scalars in `escapedForXML()`, write U+FFFD for each character XML 1.0 cannot hold, and escape the GitLab
rule identifier:

```diff
--- a/Source/SwiftLintFramework/Extensions/String+XML.swift
+++ b/Source/SwiftLintFramework/Extensions/String+XML.swift
@@ -1,19 +1,25 @@
 import Foundation
 
 extension String {
+    /// Escapes `&`, `"`, `'`, `>` and `<`, and replaces each character XML 1.0 cannot hold at all, not even as a
+    /// character reference, with U+FFFD: the C0 controls other than tab, line feed and carriage return, U+FFFE and
+    /// U+FFFF. Works on Unicode scalars, because `<` followed by a combining mark is one `Character`, and
+    /// `replacingOccurrences(of: "<", …)` does not find the `<` in it.
     func escapedForXML() -> String {
-        // & needs to go first, otherwise other replacements will be replaced again
-        let htmlEscapes = [
-            ("&", "&amp;"),
-            ("\"", "&quot;"),
-            ("'", "&apos;"),
-            (">", "&gt;"),
-            ("<", "&lt;"),
-        ]
-        var newString = self
-        for (key, value) in htmlEscapes {
-            newString = newString.replacingOccurrences(of: key, with: value)
+        var escaped = ""
+        escaped.reserveCapacity(utf8.count)
+        for scalar in unicodeScalars {
+            switch scalar {
+            case "&": escaped += "&amp;"
+            case "\"": escaped += "&quot;"
+            case "'": escaped += "&apos;"
+            case ">": escaped += "&gt;"
+            case "<": escaped += "&lt;"
+            case "\t", "\n", "\r": escaped.unicodeScalars.append(scalar)
+            case "\u{0}"..."\u{1F}", "\u{FFFE}", "\u{FFFF}": escaped += "\u{FFFD}"
+            default: escaped.unicodeScalars.append(scalar)
+            }
         }
-        return newString
+        return escaped
     }
 }
--- a/Source/SwiftLintFramework/Reporters/GitLabJUnitReporter.swift
+++ b/Source/SwiftLintFramework/Reporters/GitLabJUnitReporter.swift
@@ -14,7 +14,7 @@ struct GitLabJUnitReporter: Reporter {
                 let column = violation.location.character.map(String.init)
 
                 let severity = violation.severity.rawValue
-                let rule = violation.ruleIdentifier
+                let rule = violation.ruleIdentifier.escapedForXML()
                 let reason = violation.reason.escapedForXML()
 
                 let location = [fileName, line].compactMap(\.self).joined(separator: ":")
```

U+FFFD keeps the report readable and shows that something was there; dropping the character would work too. With
the patch, every report above is well-formed.

**Tests.** I have a Swift Testing file, `Tests/FileSystemAccessTests/XMLReporterWellFormedTests.swift`: 11 cases (the
inputs above, U+FFFE, `&` and `"` before a combining mark, a control character in a file path, `a&b` and `it's` as
rule identifiers, and a control case), each rendered with all three reporters and parsed with `XMLParser`. On `main`
10 of the 11 fail, 22 expectations in all, and the control passes. With the patch all pass, and so does
`ReporterTests`, whose canned reports are unchanged. Text without these characters comes out byte for byte the same,
since the loop writes the same five replacements and copies every other scalar. The full `swift test` (1,114 tests)
passes with the patch apart from `SwiftVersionTests.detectSwiftVersion` and
`ConfigPathResolutionTests.symlinkedFileAndFolderAreFollowed`, which fail the same way without it on my machine.
`HTMLReporter` also calls `escapedForXML`, so its output changes the same way for these inputs. Happy to open a PR
with the patch and the test file.

### Environment

* SwiftLint 0.65.1 (`swiftlint version`). `main` at `ec4691d` (0.65.1-21) has the same `String+XML.swift`,
  reporters and `TodoRule`; the tests above ran on a checkout of it.
* Xcode 27.2 (27B52), Swift 6.4.2, macOS 27.2, arm64
* Installation method: Homebrew
* Configuration file: empty for the TODO cases. For the custom rule:

```yml
only_rules:
  - custom_rules
custom_rules:
  "a<b":
    regex: 'print\('
    message: "Avoid print"
```

No nested configurations.

Found while checking whether XML written by Swift packages parses.
