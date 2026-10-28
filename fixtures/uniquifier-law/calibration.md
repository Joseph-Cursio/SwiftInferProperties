# calibration

These nine rows are in a packet's format. Rows 1 and 3 are in a repository you may read, as any packet's rows are. The others are text only: judge them from what is shown.

## calibration/1

- repository: `SwiftUMLStudio`, at `/Users/josephcursio/xcode_projects/SwiftUMLStudio`
- file: `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Model/DiagramContext.swift`, line 291
- owner: `DiagramContext` (class)
- owner's doc comment: Format-agnostic context accumulated while building a diagram from SyntaxStructures
- the function's doc comment: (none)
- same-file functions it calls: addExtensionEdge, declaresIdentifier, linkType
- same-file functions that call it: (none)
- the owner's other members in this repository (bodies left out):

```swift
// DiagramContext.swift: class DiagramContext
private(set) var configuration: Configuration
let format: DiagramFormat
/// The element-rendering options, without the hop through `configuration`.
///
/// Callers holding a context were reaching `context.configuration.elements.showGenerics` —
/// three levels of knowledge about how a context stores its settings, for a value the context
/// can hand over directly. `configuration` stays public for the callers that want the whole
/// thing (`skip(element:basedOn:)` takes it entire).
var elements: ElementOptions
var uniqueNameForElement: [SyntaxStructure: String] = [:]
/// The arrow for each element's supertype edges, from the relationship `uniqName` named it with,
/// kept per element rather than under `<name>LinkType` in `uniqElementAndTypes`, where a repeat
/// read its name's first declaration's arrow and a type named `PLinkType` overwrote protocol
/// `P`'s. `addLinking` draws an edge to a protocol the sources declare, drawn or hidden, with
/// the realization arrow instead.
private var linkTypeForElement: [SyntaxStructure: String] = [:]
var uniqElementNames: [String] = []
var uniqElementAndTypes: [String: String] = [:]
/// Every id the diagram uses: the ids `reserveIdentifiers(drawing:)` found in it, plus each
/// alias `uniqName` has issued. A suffixed alias must avoid all of them, or Mermaid and
/// PlantUML draw two elements as one.
///
/// Kept apart from `uniqElementNames` and `uniqElementAndTypes` on purpose: `uniqName` decides
/// a first declaration by `uniqElementNames`, and `addLinking` reads `uniqElementAndTypes` by
/// raw name, so a type literally named `Foo0` must still count as a first declaration.
private(set) var takenIdentifiers: Set<String> = []
/// Where the edge of each drawn nested type ends when the diagram does not draw its parent,
/// found by `reserveIdentifiers(drawing:among:)`; a nested type missing here gets no edge.
private var hiddenParentEnds: [ObjectIdentifier: HiddenParentEnd] = [:]
/// The drawn type each drawn extension extends, where its `ext` edge ends, found by
/// `reserveIdentifiers(drawing:among:)`; an extension missing here gets no edge.
private var extendedTypes: [ObjectIdentifier: SyntaxStructure] = [:]
/// Where supertype edges end, found as SVG finds them, set by
/// `reserveIdentifiers(drawing:among:)`.
private var edgeEnds: DrawnEdgeEnds?
/// The supertype edges `addLinking` has drawn. `connections` writes them out once every
/// element has its alias: the element an edge ends on may be drawn after the one it starts at.
private var supertypeEdges: [SupertypeEdge] = []
/// Each box's supertype edge ends so far, so a second edge from a box to the same end is
/// left out, as SVG leaves it out (#76).
private var supertypeEndsDrawn: Set<SupertypeEndKey> = []
/// The edges from nested types to their parents, `collectNestedTypeConnections(items:)` drew.
private var nestingConnections: [String] = []
/// Each supertype edge as the format writes it, in the order `addLinking` drew them, then
/// each nesting edge.
var connections: [String]
private(set) var extnConnections: [String] = []
/// The typealiases among the items the diagram was built from, found by
/// `reserveIdentifiers(drawing:among:)`: a supertype written through one ends on the type it
/// aliases (#125).
private var aliases = TypeAliasResolver.none
private var linkTypeInheritance: String
private var linkTypeRealize: String
private var linkTypeDependency: String
private var linkTypeGeneric: String
init(configuration: Configuration = .default)
var index = 0
/// The name `addLinking` writes for `parent`'s end of an edge, written in `scope`, when the
/// edge ends on no drawn element (`supertypeEnd(for:from:)`), or `nil` when
/// `relationships.inheritance.exclude` or `relationships.realize.exclude` suppresses the
/// edge. Both drawing and `reserveIdentifiers(drawing:)` go through here, so an excluded
/// target is neither drawn nor reserved. A name written through a typealias is the aliased
/// type's, so `struct S: Q` after `typealias Q = Proto` reads as `struct S: Proto` (#125).
func linkTarget(for parent: SyntaxStructure, from scope: DeclarationScope) -> String?
/// Where the edge to `parent`, written in `scope`, ends, as SVG ends it (`DrawnEdgeEnds`): the
/// drawn element the name means there, by file, module and access, or a hidden type's
/// stand-in. Writing the name instead ended the edge on the first box with that name, so
/// `struct U: P` reached another file's `P`. `element` is `nil` when SVG finds none: a type
/// outside the diagram, such as `Codable`, or a hidden type with no stand-in. `isProtocol`
/// says whether the edge is a realization (`DrawnEdgeEnds.supertype(named:from:)`).
private func supertypeEnd(
/// Draws the edge from `item` to its supertype `parent`. It starts at the alias `uniqName` gave
/// `item`, so a second declaration of a name, such as an extension or the other branch of an
/// `#if`, draws its supertypes from its own box (#68). It ends on the drawn element
/// `supertypeEnd(for:from:)` finds, under the alias `uniqName` gives that element. With none,
/// it is written to `linkTarget(for:from:)`, a node of its own, unless a drawn element
/// declares that name: then it is left out, as SVG leaves it out, rather than ending on that
/// unrelated box (`connections`). An edge from `item`'s box that ends where one before it
/// does, as a conformance two `#if` clauses or a merged extension repeat, is left out too.
///
/// The edge is named after the type `parent`'s name means, drawn or hidden, whichever box it
/// ends on: `conforms to` for a protocol, and `inherits` for anything else, a class, an enum's
/// raw type, or a type outside the diagram such as `Codable`, whose kind the diagram does not
/// know. Named `conforms to`, it takes the realization arrow and that label and style;
/// otherwise the arrow of `item`'s own kind. A context that never resolved its ends
/// (`reserveIdentifiers(drawing:among:)`) names an edge as the name's first box drawn so far.
/// `scope` is where `parent`'s name is written, `item`'s own scope by default: a merged
/// extension's scope for a supertype it carried.
func addLinking(item: SyntaxStructure, parent: SyntaxStructure, from scope: DeclarationScope? = nil)
/// `edge` as the format writes it. `nil` when SVG finds no drawn end for it and the name it
/// would be written to is one of the `declared` ids, which would end it on that unrelated
/// element, as `HiddenParentEnd` keeps a nesting edge from doing (#67). A context that never
/// resolved its ends (`reserveIdentifiers(drawing:among:)`) writes every edge.
private func text(of edge: SupertypeEdge, besides declared: Set<String>) -> String?
/// A Nomnoml edge, `[start] arrow label [end]`. nomnoml reads a label only beside the arrow;
/// after the end, where Mermaid and PlantUML take it, it fails the whole diagram (#69). Each
/// end is written as the id `SyntaxStructure.nomnoml(context:)` declares under, so it names
/// that node.
///
/// The label runs to the next `[`, so brackets become parentheses. nomnoml drops a line that
/// starts with `//` and reads one that starts with `#` as a directive before it parses the
/// rest, so a line break becomes a space.
private func nomnomlEdge(from start: String, _ arrow: String, to end: String, label: String? = nil) -> String
/// Whether the edge from extension `item` to the type it extends is drawn: not when
/// `relationships.dependency.exclude` matches the extended type's name, which `addExtensionEdge`
/// tests both as the extension writes it and as the type it extends is declared, so
/// `Foo.Inner` also hides the edge of `extension ModA.Foo.Inner` (#124).
private func drawsExtensionEdge(for item: SyntaxStructure) -> Bool
func relationshipLabel(for name: String) -> String?
func relationshipStyle(for name: String) -> RelationshipStyle?
/// The configured relationship an edge's connection name stands for, or `nil` for a name
/// that is none of them.
private func relationship(named name: String) -> Relationship?
/// Whether this format draws an edge from each nested type to its parent.
private var drawsNestedTypeConnections: Bool
/// Whether this format declares `item` under its alias. Mermaid and Nomnoml write a macro
/// only as a comment, so there a macro's name is no id and must not shift one.
private func declaresIdentifier(of item: SyntaxStructure) -> Bool
/// Reserve every id the diagram will use, before the first alias is issued: the names of the
/// elements it draws, and the names its edges give elements it does not draw — a supertype
/// that ends on no drawn element, such as a conformance to `Codable` or a raw type, and a
/// hidden parent of a drawn nested type. Mermaid and
/// PlantUML give an edge's undeclared end a node of its own, so a suffix that took one of
/// those names would join two elements. A first declaration keeps its own name as its alias,
/// so a suffix must not take a name declared only later either: `struct Foo {}`,
/// `extension Foo {}`, `extension Foo0 {}` would otherwise declare `Foo0` twice.
///
/// `items` must be exactly the elements the diagram draws, and `prepared` every item it was
/// built from, drawn or not (`items` when nil): the type an extension extends and a hidden
/// parent's edge end are found among them (`DrawnEdgeEnds`). A hidden element's name that
/// nothing in the diagram uses must not shift an alias.
func reserveIdentifiers(drawing items: [SyntaxStructure], among prepared: [SyntaxStructure]? = nil)
/// The arrow for the supertype edges of an element named with `relationship`, unless the
/// supertype is a protocol the sources declare.
private func linkType(for relationship: String) -> String
/// Draws the `ext` edge from extension `item`, declared as `alias`, to the type it extends:
/// the drawn type its name means where it is written, the box `--merge-extensions` would merge
/// it into (#107). Matching its name against the types drawn instead gave `extension
/// Outer.Inner` no edge, and gave a second `extension Foo` one to the first when a nested
/// `Bar.Foo` was drawn (#72). An extension of a hidden type, or of one outside the diagram,
/// gets no edge.
private func addExtensionEdge(from item: SyntaxStructure, alias: String, relationship: String)
/// Draws an edge from each drawn nested type to its parent's alias. For a parent the diagram
/// does not draw, the edge ends where `reserveIdentifiers(drawing:among:)` found SVG ends it,
/// on a drawn stand-in or on the parent's qualified name, never on its short name, which
/// could be the id of a drawn, unrelated type (#67), nor on an id a drawn element declares.
func collectNestedTypeConnections(items: [SyntaxStructure])
/// The id the edge of `item` ends on when the diagram does not draw its parent, or nil when
/// it has no edge.
private func hiddenParentName(of item: SyntaxStructure) -> String?
```

```swift
    func uniqName(item: SyntaxStructure, relationship: String) -> String {
        guard let name = item.fullName else { return "" }
        var newName = name
        if uniqElementNames.contains(name) {
            // The counter is diagram-wide, so where no candidate is taken every alias is what
            // it always was; a taken candidate is skipped, never reused.
            repeat {
                newName = name + "\(index)"
                index += 1
            } while takenIdentifiers.contains(newName)
        } else {
            uniqElementNames.append(name)
            uniqElementAndTypes[name] = relationship
        }
        if item.kind == .extension {
            addExtensionEdge(from: item, alias: newName, relationship: relationship)
        }
        if declaresIdentifier(of: item) {
            takenIdentifiers.insert(newName)
        }
        uniqueNameForElement[item] = newName
        linkTypeForElement[item] = linkType(for: relationship)
        return newName
    }
```

## calibration/2

- repository: `SwiftUMLStudio, an older revision`, at `(text only: not available to read)`
- file: `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Model/DiagramContext.swift`, line 111
- owner: `DiagramContext` (class)
- owner's doc comment: Format-agnostic context accumulated while building a diagram from SyntaxStructures
- the function's doc comment: (none)
- same-file functions it calls: (none)
- same-file functions that call it: (none)
- the owner's other members in this repository (bodies left out):

```swift
// DiagramContext.swift: class DiagramContext
private(set) var configuration: Configuration
let format: DiagramFormat
/// The element-rendering options, without the hop through `configuration`.
///
/// Callers holding a context were reaching `context.configuration.elements.showGenerics` —
/// three levels of knowledge about how a context stores its settings, for a value the context
/// can hand over directly. `configuration` stays public for the callers that want the whole
/// thing (`skip(element:basedOn:)` takes it entire).
var elements: ElementOptions
var uniqueNameForElement: [SyntaxStructure: String] = [:]
var uniqElementNames: [String] = []
var uniqElementAndTypes: [String: String] = [:]
private(set) var connections: [String] = []
private(set) var extnConnections: [String] = []
private var linkTypeInheritance: String
private var linkTypeRealize: String
private var linkTypeDependency: String
private var linkTypeGeneric: String
init(configuration: Configuration = .default)
var index = 0
func addLinking(item: SyntaxStructure, parent: SyntaxStructure)
func skipLinking(element: SyntaxStructure, basedOn excludeElements: [String]?) -> Bool
func relationshipLabel(for name: String) -> String?
func relationshipStyle(for name: String) -> RelationshipStyle?
func collectNestedTypeConnections(items: [SyntaxStructure])
// elsewhere in the module: class SyntaxStructure, init(kind: ElementKind? = nil, name: String? = nil, …)
```

```swift
    func uniqName(item: SyntaxStructure, relationship: String) -> String {
        guard let name = item.fullName else { return "" }
        var newName = name
        let linkTypeKey = name + "LinkType"
        if uniqElementNames.contains(name) {
            newName += "\(index)"
            index += 1
            let hasMatchingParent = uniqueNameForElement.keys
                .first(where: { $0.name == name && $0.kind != .extension }) != nil
            if item.kind == ElementKind.extension, hasMatchingParent {
                extnConnections.append("\(name) <.. \(newName) : ext")
            }
        } else {
            uniqElementNames.append(name)
            uniqElementAndTypes[name] = relationship
            uniqElementAndTypes[linkTypeKey] = relationship == "inherits" ? "<|--" : "--"
        }
        uniqueNameForElement[item] = newName
        return newName
    }
```

## calibration/3

- repository: `SwiftUMLStudio`, at `/Users/josephcursio/xcode_projects/SwiftUMLStudio`
- file: `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Emitters/DiagramIdentifiers.swift`, line 31
- owner: `DiagramIdentifiers` (struct)
- owner's doc comment: Hands out one diagram identifier per distinct name.  The sanitizers that turn a name into an identifier — `DepsScript.mermaidId`, `ComponentScript.safeAlias` — map several characters to `_`, so two different names can sanitize alike: `Outer.Inner` and `Outer_Inner` both give `Outer_Inner`. An emitter that used the sanitized text directly declared both names under one identifier, and the renderer drew them as a single node carrying both sets of edges.  The first name to claim an identifier keeps it, so a diagram with no collision is unchanged; a later name that collides gets `_2`, `_3`, …. Names are claimed in the order the emitter asks, so an emitter that walks its model deterministically gets deterministic identifiers.
- the function's doc comment: The identifier for `key`, built from `text` on first use. For a node whose identity is not its text alone — a provided interface is keyed by its component and its own name, and must not share an identifier with a component whose name happens to sanitize the same way.
- same-file functions it calls: (none)
- same-file functions that call it: id
- the owner's other members in this repository (bodies left out):

```swift
// DiagramIdentifiers.swift: struct DiagramIdentifiers
private let sanitize: (String) -> String
private var byKey: [String: String] = [:]
private var taken: Set<String> = []
init(sanitize: @escaping (String) -> String)
/// The identifier for `name`, claiming one on first use.
mutating func id(for name: String) -> String
```

```swift
    mutating func id(forKey key: String, sanitizing text: String) -> String {
        if let existing = byKey[key] {
            return existing
        }
        let base = sanitize(text)
        var candidate = base
        var suffix = 2
        while taken.contains(candidate) {
            candidate = "\(base)_\(suffix)"
            suffix += 1
        }
        byKey[key] = candidate
        taken.insert(candidate)
        return candidate
    }
```

## calibration/4

- repository: `SwiftUMLStudio, an older revision`, at `(text only: not available to read)`
- file: `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Model/LayoutGraphBuilder.swift`, line 146
- owner: `LayoutGraphBuilder` (struct)
- owner's doc comment: (none)
- the function's doc comment: (none)
- same-file functions it calls: (none)
- same-file functions that call it: buildClassDiagram
- the owner's other members in this repository (bodies left out):

```swift
// LayoutGraphBuilder.swift: struct LayoutGraphBuilder
/// Build a layout graph from parsed syntax structures (class diagram).
static func buildClassDiagram(
private static func prepareItems(_ items: [SyntaxStructure], configuration: Configuration) -> [SyntaxStructure]
private static func buildNode(
private static func buildEdges(
private static func resolveAndFilterEdges(
/// Build a layout graph from a dependency graph model.
static func buildDependencyGraph(from model: DependencyGraphModel) -> LayoutGraph
private static func stereotypeName(for kind: ElementKind) -> String
private static func edgeStyleForInheritance(parentName: String, itemKind: ElementKind) -> EdgeStyle
private static func extractMembers(
private static func classifyMember(
private static func accessPrefix(for element: SyntaxStructure) -> String
```

```swift
    private static func uniqueId(for name: String, existing: inout [String: String]) -> String {
        if existing[name] == nil { return name }
        var counter = 1
        var candidate = "\(name)_\(counter)"
        while existing.values.contains(candidate) {
            counter += 1
            candidate = "\(name)_\(counter)"
        }
        return candidate
    }
```

## calibration/5

- repository: `Example`, at `(text only: not available to read)`
- file: `Sources/Example/Sequence+Unique.swift`, line 3
- owner: `Sequence` (extension)
- owner's doc comment: (none)
- the function's doc comment: The elements in their first-seen order, each once.
- same-file functions it calls: (none)
- same-file functions that call it: (none)
- the owner's other members in this repository (bodies left out):

```swift
// Sequence+Unique.swift: extension Sequence
```

```swift
    func uniqued() -> [Element] where Element: Hashable {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
```

## calibration/6

- repository: `Example`, at `(text only: not available to read)`
- file: `Sources/Example/Columns.swift`, line 4
- owner: `ColumnNamer` (enum)
- owner's doc comment: (none)
- the function's doc comment: The names, with a repeat renamed `name_2`, `name_3`, … so every column has its own.
- same-file functions it calls: (none)
- same-file functions that call it: (none)
- the owner's other members in this repository (bodies left out):

```swift
// Columns.swift: enum ColumnNamer
```

```swift
    static func disambiguated(_ names: [String]) -> [String] {
        var used = Set<String>()
        return names.map { name in
            var candidate = name
            var suffix = 2
            while used.contains(candidate) {
                candidate = "\(name)_\(suffix)"
                suffix += 1
            }
            used.insert(candidate)
            return candidate
        }
    }
```

## calibration/7

- repository: `Example`, at `(text only: not available to read)`
- file: `Sources/Example/Log.swift`, line 6
- owner: `RequestLog` (class)
- owner's doc comment: Prints each request with its sequence number.
- the function's doc comment: (none)
- same-file functions it calls: (none)
- same-file functions that call it: (none)
- the owner's other members in this repository (bodies left out):

```swift
// Log.swift: final class RequestLog
private var count = 0
init()
```

```swift
    func record(_ request: String) -> String {
        count += 1
        let line = "#\(count) \(request)"
        print(line)
        return line
    }
```

## calibration/8

- repository: `Example`, at `(text only: not available to read)`
- file: `Sources/Example/Workers.swift`, line 9
- owner: `WorkerPicker` (class)
- owner's doc comment: Spreads jobs over a fixed set of workers in turn.
- the function's doc comment: The worker the next job goes to.
- same-file functions it calls: (none)
- same-file functions that call it: (none)
- the owner's other members in this repository (bodies left out):

```swift
// Workers.swift: final class WorkerPicker
let workers: Int
private var next = 0
init(workers: Int)
```

```swift
    func nextWorker() -> String {
        defer { next = (next + 1) % workers }
        return "worker\(next)"
    }
```

## calibration/9

- repository: `Example`, at `(text only: not available to read)`
- file: `Sources/Example/Temporaries.swift`, line 5
- owner: `TemporaryNamer` (class)
- owner's doc comment: Fresh variable names for generated code; no two are ever the same.
- the function's doc comment: (none)
- same-file functions it calls: (none)
- same-file functions that call it: (none)
- the owner's other members in this repository (bodies left out):

```swift
// Temporaries.swift: final class TemporaryNamer
private var counter = 0
init()
```

```swift
    func freshName(_ prefix: String) -> String {
        counter += 1
        return "\(prefix)\(counter)"
    }
```
