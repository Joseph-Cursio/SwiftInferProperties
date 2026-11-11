# Upstream reproductions for #668's XML well-formedness defects

#668's census (`docs/measurements/xml-emitter-census.md`, § *Rows that break the law, hand-checked and run*) found
six repositories whose XML writers make documents `XMLParser` rejects, from input their users can reach. The hand-check
records are in `../handcheck-2026-10-30.json`. This directory reproduces each at upstream `main` as a test (or, for
SwiftLint and swift-foundation, also as a script against the shipping build), with a patch and the issue text.
**All six were filed on 2026-10-30**, with the user's approval, after each `main` was read again unchanged; #700
tracks them:

| repository | filed |
|---|---|
| realm/SwiftLint | realm/SwiftLint#6965 |
| swiftlang/swift-foundation | swiftlang/swift-foundation#2393 |
| 2389-research/MermaidKit | 2389-research/MermaidKit#119 |
| Australware/swift-mermaid | Australware/swift-mermaid#2 |
| yahirvitelugardo/Graffle | yahirvitelugardo/Graffle#1 |
| tuist/XcodeProj | tuist/XcodeProj#1198 |

The common cause is the one SwiftUMLStudio fixed in its #80. Escaping the five predefined entities is not enough,
because XML 1.0 forbids most C0 controls (and U+FFFE, U+FFFF) outright, even as a character reference. Preparing these
turned up a second cause in four of the six: escaping by `Character` (a `switch` over `Character`s, or
`replacingOccurrences` without `.literal`) misses a `<`, `&` or `"` followed by a combining mark, because the two
scalars form one `Character`.

| repository @ revision (upstream `main` on 2026-10-30) | defect | test file → destination in the package | patch |
|---|---|---|---|
| realm/SwiftLint @ `ec4691d` (0.65.1-21) | `escapedForXML` passes C0 controls and `<`/`&`/`"`/`'` before a combining mark into the Checkstyle, JUnit and GitLab reports; `GitLabJUnitReporter` writes the rule identifier unescaped | `XMLReporterWellFormedTests.swift` → `Tests/FileSystemAccessTests/`; `repro.sh` (shipping CLI) | `escapedForXML-fix.patch` |
| swiftlang/swift-foundation @ `aff1e7f` | the XML plist `Writer.appendEscaped` writes 30 forbidden code points raw into `<string>` and `<key>` | `XMLPlistForbiddenCharacterTests.swift` → `Tests/FoundationEssentialsTests/`; `repro.swift` (shipping macOS Foundation); `PlistWitness/` (the 60-document sweep against `main`) | `xml-plist-forbidden-characters-fix.patch` (throws, as #2039 does for NUL) |
| 2389-research/MermaidKit @ `046d49e` (v2.10.1) | `SVGRenderer.escape` passes C0 controls, U+FFFE/U+FFFF, and `<`/`&` before a combining mark (reachable from ASCII source via `&#769;`) | `SVGLabelWellFormedTests.swift` → `Tests/MermaidRenderTests/` | `svg-escape-fix.patch` |
| Australware/swift-mermaid @ `ee4b50b` | `escapeText` passes the same; `escapeAttr` misses `"` before a combining mark | `SVGTextWellFormedTests.swift` → `Tests/MermaidTests/` | `escapeText-fix.patch` |
| yahirvitelugardo/Graffle @ `53b93b0` | `SVGExport.escape` passes the same into `data-name` and `<tspan>`; the app's own `SVGImport` then refuses the export | `SVGExportWellFormedTests.swift` → `Tests/GraffleTests/` (the package has no test target; add `.testTarget(name: "GraffleTests", dependencies: ["Graffle"], path: "Tests/GraffleTests")`) | `svg-escape-fix.patch` |
| tuist/XcodeProj @ `948280a` (AEXML 4.7.3) | `xmlXcodeFormat` passes C0 controls through AEXML's `xmlEscaped` into attribute values; `XCScheme(path:)` and `XCWorkspaceData(path:)` cannot read the file back | `XcodeFormatForbiddenCharacterTests.swift` → `Tests/XcodeProjTests/Extensions/` | `xcode-format-escape-fix.patch` |

Each directory's `issue-draft.md` is the text filed, its first line the issue's title. `xmlparser-check.swift`
judges files with Foundation's `XMLParser` and prints libxml2's first error.

## Run one

```bash
git clone --depth 1 https://github.com/<owner>/<repo> repro && cd repro
cp <test file> <destination>
swift test --filter <test class>   # fails
git apply <patch>
swift test --filter <test class>   # passes
```

## Measured, Xcode 27.2's Swift 6.4.2, macOS 27.2, arm64

**The new tests**, at upstream `main` on 2026-10-30:

| package | without the patch | with the patch |
|---|---|---|
| SwiftLint | 10 of 11 cases fail (22 expectations); the control passes | 11 pass |
| swift-foundation | the forbidden-character test fails for all 30 arguments (60 expectations); the 8-argument control passes | both pass |
| MermaidKit | 5 of 6 fail (34 assertions); the control passes | 6 pass |
| swift-mermaid | 7 of 8 fail (36 assertions); the control passes | 8 pass |
| Graffle | 4 of 5 fail (8 assertions: `XMLParser` and `SVGImport` each); the control passes | 5 pass |
| XcodeProj | 3 of 4 fail (32 assertions); the control passes | 4 pass |

**The packages' own suites with the patch:**

- SwiftLint: `swift test`, 1,114 tests. `SwiftVersionTests.detectSwiftVersion` and
  `ConfigPathResolutionTests.symlinkedFileAndFolderAreFollowed` fail, the same way without the patch.
  `IntegrationTests.lint` (SwiftLint linting itself) passes with the test file added.
- swift-foundation: the `PropertyListEncoder` suite, 93 tests. The rest of `FoundationEssentialsTests` was not run.
- MermaidKit: `swift test`, 508 + 16 tests, 2 skipped.
- swift-mermaid: `swift test`, 121 tests.
- Graffle: no suite. `.build/debug/Graffle --selftest` prints `ALL PASSED` with and without the patch.
- XcodeProj: `swift test`, 387 XCTest and 95 Swift Testing tests.

**The shipping builds.** `swiftlint` 0.65.1 (Homebrew) reproduces every SwiftLint case from the command line
(`swiftlint/repro.sh`), with only the default rules except for the custom-rule case. macOS 27.2's `PropertyListEncoder`
reproduces the swift-foundation case (`swift-foundation/repro.swift`). `PropertyListDecoder` and `plutil -lint` both
accept the malformed plist.

**What each patch leaves alone.** Every patch changes output only for text that holds a forbidden character, or an
escaped character followed by a combining mark. Each control case is byte-identical with and without its patch. The
SVG and report patches write U+FFFD for a forbidden character. The swift-foundation patch throws instead, which
changes `encode`'s behaviour for callers that write these strings today; its draft says so.

## Known limits, also stated in the drafts

- **swift-foundation.** The patch stops the fast byte scan at every `EF` lead byte, U+F000–U+FFFF, which includes the
  full-width forms common in CJK text. Its cost was not measured.
- **Graffle.** Reproduced at the `SVGExport` level, not driven through the UI. The paste route was traced by reading
  `CanvasView.renameLayer` and `endEditing`.
- **XcodeProj.** AEXML's own `xml` output has the same gap in `String.xmlEscaped`. It is mentioned in the draft, and
  not filed separately.
- **swift-foundation.** CF's `PropertyListSerialization` writes the same raw bytes on macOS. It is a separate writer,
  and the draft mentions it without proposing a fix there.
