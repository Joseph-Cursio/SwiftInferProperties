# PropertyListEncoder writes XML that is not well-formed when a string holds a C0 control character, U+FFFE or U+FFFF

**Describe the bug**

#2039 made the XML property list writer throw on NUL, because "The XML spec explicitly forbids NUL bytes". XML 1.0
forbids 30 more code points the same way: U+0001–U+0008, U+000B, U+000C, U+000E–U+001F, U+FFFE and U+FFFF, which
its `Char` production leaves out. No escape can write them; `&#1;` is not well-formed either.
`_XMLPlistEncodingFormat.Writer.appendEscaped(_:)` escapes `<`, `>` and `&`, throws on `0x00`, and copies these
characters into `<string>` and `<key>` raw. So `PropertyListEncoder` with `.xml` returns a document that
`XMLParser`, `xmllint` and other XML readers reject.

Foundation's own readers accept it: `PropertyListDecoder` decodes it back, and `plutil -lint` reports OK. So a
round trip through Foundation looks fine, and the problem shows up only when another XML reader gets the file.

**To Reproduce**

```swift
import Foundation

struct Settings: Codable, Equatable { var title: String }

let encoder = PropertyListEncoder()
encoder.outputFormat = .xml
let data = try encoder.encode(Settings(title: "\u{1B}[0m"))  // e.g. a pasted terminal colour code
// line 6 of the document: "\t<string>\u{1B}[0m</string>"

print(XMLParser(data: data).parse())  // false: NSXMLParserErrorDomain 9, "PCDATA invalid Char value 27", line 6
print(try PropertyListDecoder().decode(Settings.self, from: data).title == "\u{1B}[0m")  // true
```

I ran this with macOS 27.2's Foundation, and against `main` (`aff1e7f`) built from source, importing
`FoundationEssentials` alone. On `main` I encoded each of the 30 code points as a value and as a dictionary key, 60
documents in all. `XMLParser` rejected every one with code 9. NUL threw, as #2039 intends. Tab, LF, CR, U+0020,
U+007F, U+0085, U+FFFD and U+1FFFE all gave well-formed documents.

**Expected behavior**

`encode` throws `CocoaError(.propertyListWriteInvalid)`, as it does for NUL. XML has no way to write these
characters, so throwing seems the only faithful option; the binary format still holds them.

**A possible fix**

Throw for the other C0 controls in the same `switch` as NUL. U+FFFE and U+FFFF are `EF BF BE` and `EF BF BF` in
UTF-8, so the scan also stops at a lead byte `EF` and looks at the two bytes after it:

```diff
@@ Sources/FoundationEssentials/PropertyList/XMLPlistEncodingFormat.swift, Writer.appendEscaped(_ str: String) @@
                     let nextToEscapeIdx = try subBuffer.firstIndex {
                         switch $0 {
-                        case ._openangle, ._closeangle, ._ampersand:
+                        case ._openangle, ._closeangle, ._ampersand, 0xEF:
                             return true
                         case 0x00:
                             throw CocoaError(.propertyListWriteInvalid, userInfo: [
                                 NSDebugDescriptionErrorKey: "Property list strings cannot contain embedded null characters in XML format."
                             ])
+                        case 0x01...0x08, 0x0B, 0x0C, 0x0E...0x1F:
+                            // XML 1.0 allows no other C0 control, not even as a character reference.
+                            throw CocoaError(.propertyListWriteInvalid, userInfo: [
+                                NSDebugDescriptionErrorKey: "Property list strings cannot contain control characters other than tab, line feed and carriage return in XML format."
+                            ])
                         default:
                             return false
                         }
                     }
 
                     if let nextToEscapeIdx {
                         let bufferToNextEscaped = UnsafeBufferPointer(rebasing: subBuffer[..<nextToEscapeIdx])
                         append(bufferToNextEscaped)
-                        appendEscaped(subBuffer[nextToEscapeIdx])
+                        if subBuffer[nextToEscapeIdx] == 0xEF {
+                            // EF BF BE and EF BF BF are U+FFFE and U+FFFF, which XML 1.0 does not allow. Any other
+                            // lead byte EF is copied, and the scan goes on from the byte after it.
+                            if nextToEscapeIdx + 2 < subBuffer.count,
+                               subBuffer[nextToEscapeIdx + 1] == 0xBF, subBuffer[nextToEscapeIdx + 2] & 0xFE == 0xBE {
+                                throw CocoaError(.propertyListWriteInvalid, userInfo: [
+                                    NSDebugDescriptionErrorKey: "Property list strings cannot contain U+FFFE or U+FFFF in XML format."
+                                ])
+                            }
+                            append(UnsafeBufferPointer(rebasing: subBuffer[nextToEscapeIdx ..< nextToEscapeIdx + 1]))
+                        } else {
+                            appendEscaped(subBuffer[nextToEscapeIdx])
+                        }
                         ptr = ptr.advanced(by: nextToEscapeIdx + 1)
```

With the patch, all 60 documents above throw instead. The other 16 encode as before, and the plain control comes out
byte for byte the same. I added a test file in the style of #2039's `xmlEncodingRejectsStringsWithEmbeddedNUL`. It
checks the 30 code points as a value and as a key, and also checks that eight allowed scalars still round-trip: tab,
LF, DEL, U+0085, U+FEFF, U+FF01, U+FFFD and U+1FFFE. The middle three are led by `EF`. On `main` the first test
fails for all 30 arguments and the second passes. With the patch both pass, and so does the existing
`PropertyListEncoder` suite (93 tests). I did not run the rest of `FoundationEssentialsTests`.

Two costs to weigh, which is why this is a sketch rather than a PR. First, `encode` now throws where it used to
return data that Foundation itself could read back, which can break a caller that only ever reads its own files.
Second, every scalar from U+F000 to U+FFFF now leaves the fast path for one byte. That range includes the
full-width forms common in CJK text. I have not measured the cost. Happy to turn it into a PR if throwing is the
behaviour you want.

**Configuration:**
 - Swift Version: 6.4.2 (Xcode 27.2), and `main` at `aff1e7f`
 - OS: macOS
 - OS Version: 27.2

**Regression information:**
Not a regression that I know of. `PropertyListSerialization.data(fromPropertyList:format: .xml, options:)` writes the
same raw bytes on macOS 27.2. It is a separate writer, and I have not looked at it further.

**Additional context**

Found while checking whether XML written by Swift packages parses.
