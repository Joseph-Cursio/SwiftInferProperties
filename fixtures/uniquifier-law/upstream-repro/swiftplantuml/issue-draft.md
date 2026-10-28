# Two diagram elements can get the same PlantUML alias when a type name ends in a digit

`PlantUMLContext.uniqName(item:relationship:)` gives a repeated name a new alias by appending one counter shared by all names (`newName += "\(index)"`). It checks only the undecorated name against `uniqElementNames`. It never checks the decorated alias against the aliases already issued, and never adds it to `uniqElementNames` (it is stored only in `uniqueNameForElement`). So one alias can be issued twice, in three ways:

1. **A real type first, then a decoration that spells it.** `struct Vector2` holds `Vector2`; a later decoration of `Vector` made when the counter is 2 also spells `Vector2`.
2. **A decoration first, then a real type with that spelling.** Two types named `Item` get `Item` and `Item0`; a later `struct Item0` also gets `Item0`.
3. **Two decorations of different names.** `"A1" + "0"` and `"A" + "10"` both spell `A10`.

Each needs a type name that ends in a digit. I found this while hand-checking functions that hand out unique names.

## Reproduction (CLI, default options, no `.swiftplantuml.yml`)

`Geometry.swift`:

```swift
struct Vector {}
struct Vector2 {}
struct Vector3 {}
extension Vector2 {}
extension Vector3 {}
extension Vector {}
```

`swiftplantuml classdiagram --output consoleOnly Geometry.swift` prints the following. Output here and below is abridged: the header (`@startuml` through `set namespaceSeparator none`), `@enduml`, blank lines, the `{ }` bodies and trailing spaces are dropped.

```
class "Vector" as Vector << (S, SkyBlue) struct >>
class "Vector2" as Vector2 << (S, SkyBlue) struct >>
class "Vector3" as Vector3 << (S, SkyBlue) struct >>
class "Vector2" as Vector20 << (X, Orchid) extension >>
class "Vector3" as Vector31 << (X, Orchid) extension >>
class "Vector" as Vector2 << (X, Orchid) extension >>
Vector2 <.. Vector20 : ext
Vector3 <.. Vector31 : ext
Vector <.. Vector2 : ext
```

`Vector2` is declared as the alias of both `struct Vector2` and `extension Vector`, and the last line links `Vector` to that alias. I did not render the script. From its text I expect PlantUML to treat the two declarations as one element, so the `ext` line would connect `Vector` to the struct `Vector2` (inferred, not checked).

**Expected:** six distinct aliases, and an `ext` line from `Vector` to the extension's own alias. (With `--merge-extensions` this example does not collide, because the extensions are merged into their types.)

<details><summary>The other two ways, and the same thing across two files</summary>

`Items.swift` holds `struct Item {}`, `struct Item {}`, `struct Item0 {}`. Both `swiftplantuml classdiagram --output consoleOnly Items.swift` and the same command with `--merge-extensions` print:

```
class "Item" as Item << (S, SkyBlue) struct >>
class "Item" as Item0 << (S, SkyBlue) struct >>
class "Item0" as Item0 << (S, SkyBlue) struct >>
```

Two files: `ModuleA/Item.swift` holds `struct Item {}`, and `ModuleB/Item.swift` holds `struct Item {}` and `struct Item0 {}`. From their parent folder, `swiftplantuml classdiagram --output consoleOnly .` prints the following, with or without `--merge-extensions`. The file collector read `ModuleB` first, which is the first way; read in the other order, the input is the `Items.swift` sequence above (not run in that order).

```
class "Item" as Item << (S, SkyBlue) struct >>
class "Item0" as Item0 << (S, SkyBlue) struct >>
class "Item" as Item0 << (S, SkyBlue) struct >>
```

`Deco.swift` holds `struct A1 {}` twice, then `struct B {}` ten times, then `struct A {}` twice. The default command prints `A1`, `A10`, `B`, `B1` … `B9`, `A`, `A10`: the second `A1` and the second `A` share `A10`.

</details>

## Proposed fix

Keep the decorated aliases in their own list. Increase the suffix until the candidate is in neither list, then record it. A type whose own name was taken by an earlier decoration is decorated too, but is still registered under its own name the first time that name is seen, so it keeps its link type and `addLinking` does not fall back to `--ERROR--`.

```diff
--- a/Sources/SwiftPlantUMLFramework/Internal/PlantUMLContext.swift
+++ b/Sources/SwiftPlantUMLFramework/Internal/PlantUMLContext.swift
@@ -7,6 +7,8 @@
     var uniqueNameForElement: [SyntaxStructure: String] = [:]
 
     var uniqElementNames: [String] = []
+    // decorated names (e.g. "aPublicStruct0") issued so far; never issued twice
+    var decoratedElementNames: [String] = []
     var uniqElementAndTypes: [String: String] = [:]
     // var style: [String: String] = [:]
     private(set) var connections: [String] = []
@@ -86,10 +88,15 @@
         guard let name = item.fullName else { return "" }
         var newName = name
         let linkTypeKey = name + "LinkType"
-        if uniqElementNames.contains(name) {
-            newName += "\(index)"
-            index += 1
-            if item.kind == ElementKind.extension,
+        // true if an earlier element has this name (not merely a decorated alias spelled like it)
+        let nameSeen = uniqElementNames.contains(name)
+        if nameSeen || decoratedElementNames.contains(name) {
+            repeat {
+                newName = name + "\(index)"
+                index += 1
+            } while uniqElementNames.contains(newName) || decoratedElementNames.contains(newName)
+            decoratedElementNames.append(newName)
+            if item.kind == ElementKind.extension, nameSeen,
                uniqueNameForElement.keys.first(where: { $0.name == name && $0.kind != .extension }) != nil
             {
                 var connect = "\(name) \(linkTypeDependency) \(newName)"
@@ -99,7 +106,8 @@
                 connect += " : \(configuration.relationships.dependency?.label ?? relationship)"
                 extnConnections.append(connect) // "aPublicStruct <.. aPublicStruct0 : ext"
             }
-        } else {
+        }
+        if !nameSeen {
             uniqElementNames.append(name)
             uniqElementAndTypes[name] = relationship
 
```

With the patch, `Geometry.swift` gives `class "Vector" as Vector4 << (X, Orchid) extension >>` and `Vector <.. Vector4 : ext`. `Items.swift` gives `Item`, `Item0`, `Item01`; the two files give `Item`, `Item0`, `Item1`; `Deco.swift` gives the second `A` the alias `A11`.

The `nameSeen` condition on the `ext` line means the line is written in exactly the cases where it is written today. Without it, the existing check `$0.name == name`, which compares a short name with the extension's `fullName`, would add a wrong line on a colliding input. For `struct Item {}`, `struct Item {}`, `struct Outer { struct Item0 {} }`, `extension Item0 {}`, the extension gets `Item01` and the script would gain `Item0 <.. Item01 : ext`, which points at the second `Item`. With the condition, that input gets no `ext` line, as it does today.

**Output without a collision is unchanged.** I compared CLI output before and after the patch, with `--show-extensions` and with `--merge-extensions`, for this package's `Sources/`, for the five Swift sources stored as `.txt` in `TestData` (`basics`, `demo`, `nestedTypes`, `packageAccessModifier`, `protocols`, copied to `.swift`) one at a time, and for all five together; all 14 output pairs were byte-identical. I also generated the scripts for 3,000 generated Swift sources with `PlantUMLScript` in both builds, each with the default configuration and with merged extensions. All 5,177 scripts without a collision were byte-identical. No patched script declared an alias twice or contained `--ERROR--`, and in all 6,000 the `ext` lines had the same left-hand sides in both builds. On input that already collides, aliases after the first collision can get different numbers, because the counter skips numbers that are taken.

**Tests.** I have five XCTest cases in a new file, `Tests/SwiftPlantUMLFrameworkTests/PlantUMLContextUniqNameTests.swift`. They cover a direct `uniqName` check for each of the first two ways, and the Vector, Item and nested-extension examples above, checked on the generated script. All five fail on `main` and pass with the patch. The rest of the suite is unchanged. In my checkout, 13 `FileCollectorTests` / `GlobsTests` cases fail with and without the patch; I did not check why, and they do not use `PlantUMLContext`.

CONTRIBUTING asks for PRs against `dev`. There the context line reads `guard let name = item.name else { return "" }`, so that one line of the diff needs changing; with it, the diff applies to `dev`'s copy of the file without fuzz. I ran the tests on `main` only.

**Not addressed by this patch.** Relationship lines name a type by its Swift name, not its alias: the lines built in `addLinking`, and the `ext` line in `uniqName`. When a type's own name was taken by an earlier decoration, its lines attach to whichever element holds that alias. With `class Base {}`, `struct Item {}`, `struct Item {}`, `class Item0: Base {}`, the patched script declares `class "Item0" as Item01` but still writes `Base <|-- Item0 : inherits`. That alias now belongs only to the second `Item`; today it is the alias that `Item0` shares with the second `Item`. Adding `extension Item0 {}` gives `Item0 <.. Item02 : ext` with the same problem. This seemed a separate change.

**Environment:** `main` at `0f5875ec7d4f1ef9ff98079babed44ccf3437fd6` (2024-02-22); `dev` has the same logic in `uniqName`, using `item.name`. Xcode 27.1 (27A9275), Apple Swift 6.4 (swiftlang-6.4.0.34.1), macOS 27.2, arm64. I removed `.swift-version` (5.3) locally to build with Swift 6.4.
