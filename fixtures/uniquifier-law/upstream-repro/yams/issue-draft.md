# Redundancy aliasing can give two different values the same anchor, so an alias decodes to the wrong value

With `HashableAliasingStrategy` or `StrictEncodableAliasingStrategy`, `YAMLEncoder` can declare one anchor on two
different values. An alias refers to the most recent node with its anchor, so an alias written for the first value
reads back as the second: `YAMLDecoder` returns wrong values with no error, or, in some layouts, throws
`DecodingError.typeMismatch` on Yams's own output.

```swift
import Yams
struct Item: Codable, Hashable, YamlAnchorCoding { var name: String; var yamlAnchor: Anchor? }
let a = Item(name: "a")
let b = Item(name: "b", yamlAnchor: "2")
let encoder = YAMLEncoder()
encoder.options = YAMLEncoder.Options(redundancyAliasingStrategy: HashableAliasingStrategy())
let yaml = try encoder.encode([a, b, a])  // "- &2\n  name: a\n- &2\n  name: b\n- *2\n"
print(try YAMLDecoder().decode([Item].self, from: yaml).map(\.name))
```

Expected `["a", "b", "a"]`, actual `["a", "b", "b"]`. `StrictEncodableAliasingStrategy()` emits the same YAML.

`UniqueAliasProvider.uniqueAlias(for:)` returns a value's own `yamlAnchor` unchanged and numbers every other value
`"1"`, `"2"`, … from a counter, never checking a name against those already issued. Above, the counter gave `"1"` to
the array (not emitted, as nothing aliases it) and `"2"` to `a`; then `b` dictated `"2"`. On a new strategy, in
either order, `alias(for: 42)` and `alias(for: Item(name: "b", yamlAnchor: "1"))` both return `.anchor("1")`.

<details><summary>Three more inputs (each encoded with a new strategy; same YAML under both strategies)</summary>

1. `[a, b, a]` with `a` and `b` both dictating `"label"` declares `&label` twice and decodes as `["a", "b", "b"]`.
2. `[Item(name: "a", yamlAnchor: "2"), Item(name: "a")]` emits `"- &2\n  name: &2 a\n- name: *2\n"` (the counter
   gives `"2"` to the string inside the mapping that dictated it); decoding throws `typeMismatch` ("Expected value
   of type Scalar. Path: [1].name. Debug description: Expected to decode Scalar but found Mapping instead.").
3. Decode Yams's own `encode([shared, shared])` (`&2`, then `*2`) into `[Item]`, so both carry `yamlAnchor == "2"`,
   add a new `fresh` at the front and the end, and encode with a new strategy: `fresh` and `shared` are both
   declared `&2`, and the result decodes as `["fresh", "shared", "shared", "shared"]`.

</details>

## Proposed fix

- `UniqueAliasProvider` keeps the set of names issued since the last release. The counter skips names in the set,
  and a dictated name already in it is replaced by the next free counter name. The set holds names, not `Anchor`s,
  because nodes hold anchors weakly and an unaliased anchor must still be freed.
- Each strategy's `releaseAnchorReferences()` empties the set and its `remit(anchor:)` (added in #438, 3fe2b5c)
  removes the name, since a remitted anchor is not in the document. The counter is not reset, as today.
- `YAMLEncoder.encode` skips the release when encoding throws (`Encoder.swift:39-41`), so a reused encoder would
  carry a failed document's names into the next document. The patch releases on that path too, by catch-and-rethrow
  rather than `defer`: the release must come before `serialize`, which emits every anchor still alive (with a
  function-level `defer`, 20 existing tests fail on anchors nothing aliases). This also fixes an existing leak under
  `HashableAliasingStrategy`: after an encode throws, a value the failed document anchored comes out of the next
  encode on that encoder as `*x` with no `&x`.

<details><summary>Patch excerpt (the full patch also adds the provider's <code>remit(anchor:)</code> and
<code>releaseAnchorReferences()</code>, and a call to each from both strategies)</summary>

```diff
@@ Sources/Yams/Encoder.swift, YAMLEncoder.encode @@
             var container = encoder.singleValueContainer()
-            try container.encode(value)
+            do {
+                try container.encode(value)
+            } catch {
+                // Release here too, or a strategy reused for the next document keeps this one's anchors.
+                try? options.redundancyAliasingStrategy?.releaseAnchorReferences()
+                throw error
+            }
             try options.redundancyAliasingStrategy?.releaseAnchorReferences()
@@ Sources/Yams/RedundancyAliasingStrategy.swift, UniqueAliasProvider @@
     private var counter = 0
+    private var issuedAnchors: Set<String> = []
 
     func uniqueAlias(for encodable: any Encodable) -> Anchor {
         if let anchorProviding = encodable as? YamlAnchorProviding,
-           let anchor = anchorProviding.yamlAnchor {
+           let anchor = anchorProviding.yamlAnchor,
+           issuedAnchors.insert(anchor.rawValue).inserted {
             return anchor
         } else {
-            counter += 1
+            repeat {
+                counter += 1
+            } while !issuedAnchors.insert(String(counter)).inserted
             return Anchor(rawValue: String(counter))
```

</details>

With the patch, the first example emits `"- &2\n  name: a\n- name: b\n- *2\n"` and decodes correctly, as do the
inputs above. I have an XCTest file of 17 tests (public API only): 13 fail before the patch, all pass after, and the
full suite passes with the patch and the file (`swift test`, 211 tests). Happy to open a PR with both.

**What callers see change.** A dictated anchor whose name was already issued in the same encode is replaced by a
counter name, or dropped if nothing aliases the value, so a `YamlAnchorCoding` round trip reads a different
`yamlAnchor`: `b` above comes back as `nil` instead of `"2"`, and in input 3 `shared` is emitted as `&4` and comes
back as `"4"`. That holds even if the first holder never reached the output: with a new strategy,
`[Item(name: "x"), Item(name: "y", yamlAnchor: "3")]` read back correctly before (the counter had given `"3"` to
the unaliased string `"x"`), and `y` now reads back as `nil`. Output is unchanged unless a name is issued twice
within one release window (one `encode` call, with the patch). In a seeded check (4,000 random `[Item]` arrays with
repeats and dictated anchors, under both strategies), 356 of 8,000 encodings decoded wrong and 574 threw before the
patch, and none after; the 4,620 that issued no name twice were byte-identical, and 1,896 that issued one twice
changed though they had read back correctly. An alternative I have not tried keeps every dictated name instead, and
gives the earlier holder's later occurrences a fresh anchor.

## Not fixed by this patch

- **Values the strategy does not anchor.** The keyed container writes a value's `yamlAnchor` onto its node itself
  (`Encoder.swift:176-177`); the strategy's anchor replaces it only if the strategy anchors that value (`:287`).
  `HashableAliasingStrategy` returns `.none` for a non-`Hashable` value, so the headline symptom stays reachable.
  Continuing the first example, `third` decodes as `"b"`, before and after the patch:

  ```swift
  struct Plain: Codable, YamlAnchorCoding { var name: String; var yamlAnchor: Anchor? }  // Item minus Hashable
  struct Trio: Codable { var first: Item; var second: Plain; var third: Item }
  encoder.options = YAMLEncoder.Options(redundancyAliasingStrategy: HashableAliasingStrategy())  // a new strategy
  let trio = try encoder.encode(Trio(first: a, second: Plain(name: "b", yamlAnchor: "1"), third: a))
  // "first: &1\n  name: a\nsecond: &1\n  name: b\nthird: *1\n"
  print(try YAMLDecoder().decode(Trio.self, from: trio).third.name)  // "b"
  ```

  `StrictEncodableAliasingStrategy` passes every value it has not already aliased to the provider, so it handles
  this (by dropping `second`'s `&1`: `"1"` went to the unemitted `Trio`, and the old output read back correctly).
  This patch leaves that path alone. `HashableAliasingStrategy.alias(for:)` is handed these values (it returns
  `.none` at `RedundancyAliasingStrategy.swift:58-59`), so it could pass one that dictates an anchor to the provider
  and return `.anchor` without storing it; a strategy written that way against the current protocol makes `third`
  decode as `"a"`. No protocol change is needed for `YamlAnchorProviding` values.
- **Re-entrant encoding.** If a value's `encode(to:)` calls the same `YAMLEncoder`, the inner call releases
  mid-document, so a later dictated name can repeat an earlier one. Seen before and after the patch; in my case the
  only alias came before the repeat, so it still pointed at the right value.
- By design, the provider can issue a name again after it is remitted or released; such a name is not in the document.

**Environment.** Yams `df801bc` (`main`); `UniqueAliasProvider` is unchanged since #428 was merged.
Xcode 27.1 (27A9275), Swift 6.4 (`swiftlang-6.4.0.34.1`), macOS 27.2, arm64, `swift test`; Linux, CMake and Bazel
not checked. Found while hand-checking functions that hand out unique names.
