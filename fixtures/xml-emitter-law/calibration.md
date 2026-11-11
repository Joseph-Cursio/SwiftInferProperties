# calibration

These ten rows are in a packet's format. Rows 1 and 2 are in a repository you may read, as any packet's rows are. The others are text only: judge them from what is shown.

## calibration/1

- repository: `SwiftUMLStudio`, at `/Users/josephcursio/xcode_projects/SwiftUMLStudio`
- file: `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Model/ComponentSVGRenderer+SVG.swift`, line 13
- unit: a function
- owner: `ComponentSVGRenderer` (extension)
- owner's doc comment: (none)
- the unit's doc comment: Render a positioned `ComponentLayout` as a standalone SVG document. Kept lightweight — Studio uses the native renderer; this SVG is the WebView fallback when the user picks .svg without launching Studio.
- same-type members that reference it: render
- the owner's other members in this repository (bodies left out):

```swift
// ComponentSVGRenderer+SVG.swift: extension ComponentSVGRenderer
/// Shared font-family attribute for every text element.
private static var textFontFamily: String
static func svgHeader(width: Double, height: Double) -> String
static var arrowMarkerDefs: String
static func edgeSVGLine(
static func componentSVGLines(for component: PositionedComponent) -> [String]
static func boxRect(
static func textElement(
/// Returns where the ray from `source`'s center towards `target`'s center
/// leaves `source`'s rectangle, used as the edge anchor. An edge drawn
/// between the anchors at its two ends therefore lies on the
/// center-to-center line. The point is on whichever side the ray reaches
/// first: the top or bottom when the ray is steeper than the box's
/// diagonals, the left or right when it is shallower, and a corner when
/// the two are equal. The rectangle's corners are square, while the box is
/// drawn with 4-point rounded ones, so an anchor near a corner sits just
/// outside the outline. The anchor is not the border point nearest
/// `target`'s center: for a 20×20 box at the origin and a target centered
/// at (100, 5), it is (10, 0.5), not (10, 5) (#62).
///
/// When the centers coincide there is no direction, and `source`'s center
/// is returned. Each delta's magnitude is raised to at least 0.001 where
/// it is divided by, so a target level with `source`, or directly above or
/// below it, does not divide by zero. Where that lowers the scale, the
/// point lies inside the box rather than on its border. That happens
/// exactly when the target is less than 0.001 from `source`'s center along
/// the box's shorter axis and less than 0.001 × (longer side ÷ shorter
/// side) along the longer one; for a square box, less than 0.001 on both.
/// All of this assumes a box of positive width and height. One with a zero
/// side gets its center for every target.
static func edgePoint(
static func format(_ value: Double) -> String
// ComponentSVGRenderer.swift: public enum ComponentSVGRenderer
/// Estimated character width in the body font (px).
static let charWidth: Double = 7.5
/// Vertical space taken up by one interface line (px).
static let interfaceLineHeight: Double = 16.0
/// Height of the «component» header band at the top of each box (px).
static let headerHeight: Double = 30.0
/// Padding inside each component box (px).
static let boxPadding: Double = 10.0
/// Minimum box width (px) — guards against very short names.
static let minBoxWidth: Double = 140.0
/// Horizontal gap between adjacent component boxes (px).
static let horizontalGap: Double = 50.0
/// Vertical gap between dependency levels (px).
static let verticalGap: Double = 70.0
/// Margin around the entire diagram (px).
static let canvasMargin: Double = 30.0
/// Lay out the given model and emit both a `ComponentLayout` (for native
/// rendering) and an SVG text representation (for WebView fallback).
public static func render(_ model: ComponentModel) -> (layout: ComponentLayout, svg: String)
/// Lay out a `ComponentModel` without producing SVG text. Exposed for
/// testing; production callers use `render(_:)`.
public static func computeLayout(_ model: ComponentModel) -> ComponentLayout
/// Group components into rows so each row's components depend only on
/// components in *later* rows. Row 0 is the top of the canvas (the most
/// "dependent" targets), the last row is the bottom (the most depended-on
/// leaf libraries).
static func dependencyLevels(for model: ComponentModel) -> [[String]]
/// How many dependencies deep `start`'s longest chain goes, with a dependency already on the
/// walk's path counting as zero, so a cycle does not loop. Each finished target's depth goes
/// into `cache`, which later walks read first.
///
/// The walk keeps its own path instead of recursing: a target line a few hundred long
/// overflowed the cooperative thread's stack that the CLI and Studio call this on (#149).
private static func chainDepth(
private static func boxSize(for component: Component) -> (width: Double, height: Double)
/// The UML stereotype for `kind`. Public so Studio's native canvas labels a
/// component exactly as this SVG renderer does.
public static func stereotypeLabel(for kind: Component.Kind) -> String
```

- the same-type members it references, in full:

```swift
// ComponentSVGRenderer+SVG.swift, line 45
    static var arrowMarkerDefs: String {
        """
        <defs>
          <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5"\
         markerWidth="6" markerHeight="6" orient="auto-start-reverse">
            <path d="M 0 0 L 10 5 L 0 10 z" fill="#444"/>
          </marker>
        </defs>
        """
    }

// ComponentSVGRenderer+SVG.swift, line 73
    static func componentSVGLines(for component: PositionedComponent) -> [String] {
        let originX = component.centerX - component.width / 2
        let originY = component.centerY - component.height / 2
        var lines: [String] = [
            boxRect(originX: originX, originY: originY,
                    width: component.width, height: component.height, fill: "#f7f7f9"),
            boxRect(originX: originX, originY: originY,
                    width: component.width, height: headerHeight, fill: "#e6e8ef")
        ]
        let stereotype = "«\(stereotypeLabel(for: component.kind))»"
        lines.append(textElement(
            originX: component.centerX,
            originY: originY + 12,
            style: TextStyle(anchor: "middle", fontSize: 10, fontStyle: "italic", fill: "#555"),
            text: stereotype
        ))
        lines.append(textElement(
            originX: component.centerX,
            originY: originY + 24,
            style: TextStyle(anchor: "middle", fontSize: 12, fontWeight: "600", fill: "#222"),
            text: component.name
        ))
        var interfaceY = originY + headerHeight + boxPadding
        for interfaceName in component.providedInterfaces {
            lines.append(textElement(
                originX: originX + boxPadding,
                originY: interfaceY + 11,
                style: TextStyle(anchor: "start", fontSize: 11, fill: "#333"),
                text: interfaceName
            ))
            interfaceY += interfaceLineHeight
        }
        return lines
    }

// ComponentSVGRenderer+SVG.swift, line 56
    static func edgeSVGLine(
        for dependency: ComponentDependency,
        in layout: ComponentLayout
    ) -> String? {
        guard
            let source = layout.component(named: dependency.from),
            let target = layout.component(named: dependency.to)
        else { return nil }
        let (startX, startY) = edgePoint(from: source, towards: target)
        let (endX, endY) = edgePoint(from: target, towards: source)
        return "<line"
            + " x1=\"\(format(startX))\" y1=\"\(format(startY))\""
            + " x2=\"\(format(endX))\" y2=\"\(format(endY))\""
            + " stroke=\"#444\" stroke-width=\"1.2\""
            + " stroke-dasharray=\"5 4\" marker-end=\"url(#arrow)\"/>"
    }

// ComponentSVGRenderer+SVG.swift, line 37
    static func svgHeader(width: Double, height: Double) -> String {
        let widthInt = Int(width.rounded(.up))
        let heightInt = Int(height.rounded(.up))
        return "<svg xmlns=\"http://www.w3.org/2000/svg\""
            + " width=\"\(widthInt)\" height=\"\(heightInt)\""
            + " viewBox=\"0 0 \(widthInt) \(heightInt)\">"
    }
```

The unit:

```swift
    public static func renderSVG(_ layout: ComponentLayout) -> String {
        guard !layout.components.isEmpty else { return "" }

        var lines: [String] = []
        lines.append(svgHeader(width: layout.totalWidth, height: layout.totalHeight))
        lines.append(arrowMarkerDefs)

        // Edges first so boxes paint over them at their borders.
        for dependency in layout.dependencies {
            if let edgeLine = edgeSVGLine(for: dependency, in: layout) {
                lines.append(edgeLine)
            }
        }

        for component in layout.components {
            lines.append(contentsOf: componentSVGLines(for: component))
        }

        lines.append("</svg>")
        return lines.joined(separator: "\n")
    }
```

## calibration/2

- repository: `SwiftUMLStudio`, at `/Users/josephcursio/xcode_projects/SwiftUMLStudio`
- file: `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Model/ComponentSVGRenderer+SVG.swift`, line 37
- unit: a function
- owner: `ComponentSVGRenderer` (extension)
- owner's doc comment: (none)
- the unit's doc comment: (none)
- same-type members that reference it: renderSVG
- the owner's other members in this repository (bodies left out):

```swift
// ComponentSVGRenderer+SVG.swift: extension ComponentSVGRenderer
/// Shared font-family attribute for every text element.
private static var textFontFamily: String
/// Render a positioned `ComponentLayout` as a standalone SVG document.
/// Kept lightweight — Studio uses the native renderer; this SVG is the
/// WebView fallback when the user picks .svg without launching Studio.
public static func renderSVG(_ layout: ComponentLayout) -> String
static var arrowMarkerDefs: String
static func edgeSVGLine(
static func componentSVGLines(for component: PositionedComponent) -> [String]
static func boxRect(
static func textElement(
/// Returns where the ray from `source`'s center towards `target`'s center
/// leaves `source`'s rectangle, used as the edge anchor. An edge drawn
/// between the anchors at its two ends therefore lies on the
/// center-to-center line. The point is on whichever side the ray reaches
/// first: the top or bottom when the ray is steeper than the box's
/// diagonals, the left or right when it is shallower, and a corner when
/// the two are equal. The rectangle's corners are square, while the box is
/// drawn with 4-point rounded ones, so an anchor near a corner sits just
/// outside the outline. The anchor is not the border point nearest
/// `target`'s center: for a 20×20 box at the origin and a target centered
/// at (100, 5), it is (10, 0.5), not (10, 5) (#62).
///
/// When the centers coincide there is no direction, and `source`'s center
/// is returned. Each delta's magnitude is raised to at least 0.001 where
/// it is divided by, so a target level with `source`, or directly above or
/// below it, does not divide by zero. Where that lowers the scale, the
/// point lies inside the box rather than on its border. That happens
/// exactly when the target is less than 0.001 from `source`'s center along
/// the box's shorter axis and less than 0.001 × (longer side ÷ shorter
/// side) along the longer one; for a square box, less than 0.001 on both.
/// All of this assumes a box of positive width and height. One with a zero
/// side gets its center for every target.
static func edgePoint(
static func format(_ value: Double) -> String
// ComponentSVGRenderer.swift: public enum ComponentSVGRenderer
/// Estimated character width in the body font (px).
static let charWidth: Double = 7.5
/// Vertical space taken up by one interface line (px).
static let interfaceLineHeight: Double = 16.0
/// Height of the «component» header band at the top of each box (px).
static let headerHeight: Double = 30.0
/// Padding inside each component box (px).
static let boxPadding: Double = 10.0
/// Minimum box width (px) — guards against very short names.
static let minBoxWidth: Double = 140.0
/// Horizontal gap between adjacent component boxes (px).
static let horizontalGap: Double = 50.0
/// Vertical gap between dependency levels (px).
static let verticalGap: Double = 70.0
/// Margin around the entire diagram (px).
static let canvasMargin: Double = 30.0
/// Lay out the given model and emit both a `ComponentLayout` (for native
/// rendering) and an SVG text representation (for WebView fallback).
public static func render(_ model: ComponentModel) -> (layout: ComponentLayout, svg: String)
/// Lay out a `ComponentModel` without producing SVG text. Exposed for
/// testing; production callers use `render(_:)`.
public static func computeLayout(_ model: ComponentModel) -> ComponentLayout
/// Group components into rows so each row's components depend only on
/// components in *later* rows. Row 0 is the top of the canvas (the most
/// "dependent" targets), the last row is the bottom (the most depended-on
/// leaf libraries).
static func dependencyLevels(for model: ComponentModel) -> [[String]]
/// How many dependencies deep `start`'s longest chain goes, with a dependency already on the
/// walk's path counting as zero, so a cycle does not loop. Each finished target's depth goes
/// into `cache`, which later walks read first.
///
/// The walk keeps its own path instead of recursing: a target line a few hundred long
/// overflowed the cooperative thread's stack that the CLI and Studio call this on (#149).
private static func chainDepth(
private static func boxSize(for component: Component) -> (width: Double, height: Double)
/// The UML stereotype for `kind`. Public so Studio's native canvas labels a
/// component exactly as this SVG renderer does.
public static func stereotypeLabel(for kind: Component.Kind) -> String
```

- the same-type members it references, in full:

```swift
(none)
```

The unit:

```swift
    static func svgHeader(width: Double, height: Double) -> String {
        let widthInt = Int(width.rounded(.up))
        let heightInt = Int(height.rounded(.up))
        return "<svg xmlns=\"http://www.w3.org/2000/svg\""
            + " width=\"\(widthInt)\" height=\"\(heightInt)\""
            + " viewBox=\"0 0 \(widthInt) \(heightInt)\">"
    }
```

## calibration/3

- repository: `SwiftUMLStudio, an older revision`, at `(text only: not available to read)`
- file: `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Emitters/SVGRenderer.swift`, line 31
- unit: a function
- owner: `SVGRenderer` (struct)
- owner's doc comment: Renders a positioned `LayoutGraph` as an SVG XML string.
- the unit's doc comment: Render the positioned layout graph to an SVG string.
- same-type members that reference it: (none)
- the owner's other members in this repository (bodies left out):

```swift
// elsewhere in the module, the input types (all public, all with public initialisers):
// struct LayoutGraph { var nodes: [LayoutNode]; var edges: [LayoutEdge]; var clusters: [LayoutCluster] = []; var width: Double = 0; var height: Double = 0 }
// struct LayoutNode { let id: String; let label: String; var stereotype: String?; var compartments: [NodeCompartment]; var posX, posY, width, height: Double }
// struct NodeCompartment { let title: String?; let items: [String] }
// struct LayoutEdge { let sourceId: String; let targetId: String; var label: String?; var style: EdgeStyle; var points: [LayoutPoint] = [] }
// struct LayoutCluster { let id: String; let label: String; var posX, posY, width, height: Double }
// enum EdgeStyle { case inheritance, realization, dependency, association, composition }
// extension String { var xmlEscaped: String }   // replaces & < > " with entities
// SVGRenderer.swift: public struct SVGRenderer: Sendable
private static let headerFill: [String: String] = [
private static let bodyFill = "#FAFAFA"
private static let strokeColor = "#333333"
private static let textColor = "#FFFFFF"
private static let bodyTextColor = "#333333"
private static let fontSize: Double = 12
private static let headerFontSize: Double = 13
private static let lineHeight: Double = 18
private static let padding: Double = 10
private static let headerHeight: Double = 36
private static let cornerRadius: Double = 4
private static func arrowMarkers() -> String
private static func renderNode(_ node: LayoutNode) -> String
/// Renders a module grouping box: a tinted, rounded rectangle with the
/// module name in the top-left corner. The hue is derived deterministically
/// from the module name so the same module keeps its color across renders
/// (mirrors `NativeDiagramGeometry.moduleColor(for:)` in the Studio app).
private static func renderCluster(_ cluster: LayoutCluster) -> String
/// Deterministic hue (0–359) for a module name — sums the name's unicode
/// scalars mod 360, matching the Studio canvas color derivation.
static func moduleHue(for module: String) -> Int
static func renderEdge(_ edge: LayoutEdge) -> String
private static func fmt(_ value: Double) -> String
```

- the same-type members it references, in full:

```swift
// SVGRenderer.swift, line 66
    private static func arrowMarkers() -> String {
        """
        <marker id="arrow-inheritance" viewBox="0 0 12 12" refX="12" refY="6" \
        markerWidth="12" markerHeight="12" orient="auto-start-reverse">
            <path d="M 0 0 L 12 6 L 0 12 Z" fill="white" stroke="\(strokeColor)" stroke-width="1"/>
        </marker>
        <marker id="arrow-realization" viewBox="0 0 12 12" refX="12" refY="6" \
        markerWidth="12" markerHeight="12" orient="auto-start-reverse">
            <path d="M 0 0 L 12 6 L 0 12 Z" fill="white" stroke="\(strokeColor)" stroke-width="1"/>
        </marker>
        <marker id="arrow-dependency" viewBox="0 0 12 12" refX="12" refY="6" \
        markerWidth="10" markerHeight="10" orient="auto-start-reverse">
            <path d="M 0 2 L 10 6 L 0 10" fill="none" stroke="\(strokeColor)" stroke-width="1.5"/>
        </marker>
        <marker id="arrow-composition" viewBox="0 0 16 12" refX="16" refY="6" \
        markerWidth="14" markerHeight="10" orient="auto-start-reverse">
            <path d="M 0 6 L 8 0 L 16 6 L 8 12 Z" fill="\(strokeColor)" stroke="\(strokeColor)" stroke-width="1"/>
        </marker>
        """
    }

// SVGRenderer.swift, line 160
    private static func renderCluster(_ cluster: LayoutCluster) -> String {
        let leftX = cluster.posX - cluster.width / 2
        let topY = cluster.posY - cluster.height / 2
        let hue = moduleHue(for: cluster.id)
        let color = "hsl(\(hue), 55%, 60%)"

        var svg = "\n<!-- module: \(cluster.label.xmlEscaped) -->\n"
        svg += "<g>\n"
        svg += "  <rect x=\"\(fmt(leftX))\" y=\"\(fmt(topY))\" "
        svg += "width=\"\(fmt(cluster.width))\" height=\"\(fmt(cluster.height))\" "
        svg += "rx=\"\(cornerRadius * 2)\" ry=\"\(cornerRadius * 2)\" "
        svg += "fill=\"\(color)\" fill-opacity=\"0.10\" "
        svg += "stroke=\"\(color)\" stroke-width=\"1.5\" stroke-dasharray=\"6,3\"/>\n"
        svg += "  <text x=\"\(fmt(leftX + padding))\" y=\"\(fmt(topY + 16))\" "
        svg += "fill=\"\(color)\" font-size=\"12\" font-weight=\"bold\">"
        svg += "\(cluster.label.xmlEscaped)</text>\n"
        svg += "</g>\n"
        return svg
    }

// SVGRenderer.swift, line 189
    static func renderEdge(_ edge: LayoutEdge) -> String {
        guard edge.points.count >= 2 else { return "" }

        let markerId: String
        let dashArray: String
        switch edge.style {
        case .inheritance:
            markerId = "arrow-inheritance"
            dashArray = ""
        case .realization:
            markerId = "arrow-realization"
            dashArray = " stroke-dasharray=\"6,3\""
        case .dependency:
            markerId = "arrow-dependency"
            dashArray = " stroke-dasharray=\"4,3\""
        case .association:
            markerId = ""
            dashArray = ""
        case .composition:
            markerId = "arrow-composition"
            dashArray = ""
        }

        var svg = ""

        // Build path from points
        let first = edge.points[0]
        var pathData = "M \(fmt(first.posX)) \(fmt(first.posY))"
        for point in edge.points.dropFirst() {
            pathData += " L \(fmt(point.posX)) \(fmt(point.posY))"
        }

        svg += "<path d=\"\(pathData)\" fill=\"none\" stroke=\"\(strokeColor)\" "
        svg += "stroke-width=\"1.2\"\(dashArray)"
        if !markerId.isEmpty {
            svg += " marker-end=\"url(#\(markerId))\""
        }
        svg += "/>\n"

        // Edge label
        if let label = edge.label, !label.isEmpty, edge.points.count >= 2 {
            let mid = edge.points[edge.points.count / 2]
            svg += "<text x=\"\(fmt(mid.posX + 4))\" y=\"\(fmt(mid.posY - 4))\" "
            svg += "fill=\"\(bodyTextColor)\" font-size=\"10\">"
            svg += "\(label.xmlEscaped)</text>\n"
        }

        return svg
    }

// SVGRenderer.swift, line 89
    private static func renderNode(_ node: LayoutNode) -> String {
        let leftX = node.posX - node.width / 2
        let topY = node.posY - node.height / 2
        let stereotype = node.stereotype ?? "class"
        let fill = headerFill[stereotype] ?? headerFill["class"]!

        var svg = "\n<!-- \(node.label.xmlEscaped) -->\n"
        svg += "<g>\n"

        // Background rect with rounded corners
        svg += "  <rect x=\"\(fmt(leftX))\" y=\"\(fmt(topY))\" "
        svg += "width=\"\(fmt(node.width))\" height=\"\(fmt(node.height))\" "
        svg += "rx=\"\(cornerRadius)\" ry=\"\(cornerRadius)\" "
        svg += "fill=\"\(bodyFill)\" stroke=\"\(strokeColor)\" stroke-width=\"1.5\"/>\n"

        // Header background
        let headerH = min(headerHeight, node.height)
        svg += "  <rect x=\"\(fmt(leftX))\" y=\"\(fmt(topY))\" "
        svg += "width=\"\(fmt(node.width))\" height=\"\(fmt(headerH))\" "
        svg += "rx=\"\(cornerRadius)\" ry=\"\(cornerRadius)\" "
        svg += "fill=\"\(fill)\"/>\n"

        // Square off the bottom corners of the header when there are compartments
        if !node.compartments.isEmpty || node.height > headerHeight {
            svg += "  <rect x=\"\(fmt(leftX))\" y=\"\(fmt(topY + headerH - cornerRadius))\" "
            svg += "width=\"\(fmt(node.width))\" height=\"\(fmt(cornerRadius))\" "
            svg += "fill=\"\(fill)\"/>\n"
        }

        // Stereotype label
        let stereotypeY = topY + 14
        svg += "  <text x=\"\(fmt(node.posX))\" y=\"\(fmt(stereotypeY))\" "
        svg += "text-anchor=\"middle\" fill=\"\(textColor)\" "
        svg += "font-size=\"10\" font-style=\"italic\">"
        svg += "&#x00AB;\(stereotype.xmlEscaped)&#x00BB;</text>\n"

        // Name label
        let nameY = topY + 28
        svg += "  <text x=\"\(fmt(node.posX))\" y=\"\(fmt(nameY))\" "
        svg += "text-anchor=\"middle\" fill=\"\(textColor)\" "
        svg += "font-size=\"\(headerFontSize)\" font-weight=\"bold\">"
        svg += "\(node.label.xmlEscaped)</text>\n"

        // Compartments
        var currentY = topY + headerH
        for compartment in node.compartments where !compartment.items.isEmpty {
            // Separator line
            svg += "  <line x1=\"\(fmt(leftX))\" y1=\"\(fmt(currentY))\" "
            svg += "x2=\"\(fmt(leftX + node.width))\" y2=\"\(fmt(currentY))\" "
            svg += "stroke=\"\(strokeColor)\" stroke-width=\"0.5\"/>\n"

            currentY += padding
            for item in compartment.items {
                currentY += lineHeight
                svg += "  <text x=\"\(fmt(leftX + padding))\" y=\"\(fmt(currentY - 4))\" "
                svg += "fill=\"\(bodyTextColor)\" font-size=\"\(fontSize)\">"
                svg += "\(item.xmlEscaped)</text>\n"
            }
            currentY += padding
        }

        svg += "</g>\n"
        return svg
    }
```

The unit:

```swift
    public static func render(_ graph: LayoutGraph) -> String {
        let margin: Double = 20
        let svgWidth = graph.width + margin * 2
        let svgHeight = graph.height + margin * 2

        var svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(svgWidth))" height="\(Int(svgHeight))" \
        viewBox="0 0 \(Int(svgWidth)) \(Int(svgHeight))" \
        style="font-family: -apple-system, 'SF Pro Text', 'Helvetica Neue', sans-serif;">
        <defs>
            \(arrowMarkers())
        </defs>
        """

        // Render module cluster boxes first (behind everything)
        for cluster in graph.clusters {
            svg += renderCluster(cluster)
        }

        // Render edges (behind nodes)
        for edge in graph.edges {
            svg += renderEdge(edge)
        }

        // Render nodes
        for node in graph.nodes {
            svg += renderNode(node)
        }

        svg += "\n</svg>"
        return svg
    }
```

## calibration/4

- repository: `Example`, at `(text only: not available to read)`
- file: `Sources/Report/ReportPage.swift`, line 12
- unit: a function
- owner: `ReportPage` (struct)
- owner's doc comment: A self-contained HTML report a browser opens directly.
- the unit's doc comment: The whole page, with the chart inline.
- same-type members that reference it: (none)
- the owner's other members in this repository (bodies left out):

```swift
// ReportPage.swift: struct ReportPage
let title: String
let bars: [Double]
```

- the same-type members it references, in full:

```swift
(none)
```

The unit:

```swift
    func html() -> String {
        let chart = bars.enumerated().map { index, value in
            "<rect x=\"\(index * 12)\" y=\"0\" width=\"10\" height=\"\(value)\"/>"
        }.joined()
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>\(title.htmlEscaped)</title></head>
        <body><h1>\(title.htmlEscaped)</h1><br>
        <svg xmlns="http://www.w3.org/2000/svg" width="400" height="200">\(chart)</svg>
        </body></html>
        """
    }
```

## calibration/5

- repository: `Example`, at `(text only: not available to read)`
- file: `Sources/Import/FormatSniffer.swift`, line 4
- unit: a function
- owner: `FormatSniffer` (enum)
- owner's doc comment: Guesses a file's format from its first bytes.
- the unit's doc comment: A short name for the format `data` appears to be in, for the import log.
- same-type members that reference it: (none)
- the owner's other members in this repository (bodies left out):

```swift
// FormatSniffer.swift: enum FormatSniffer
```

- the same-type members it references, in full:

```swift
(none)
```

The unit:

```swift
    static func describe(_ data: Data) -> String {
        if data.starts(with: Array("<?xml".utf8)) { return "XML" }
        if data.starts(with: Array("{".utf8)) { return "JSON" }
        return "unknown"
    }
```

## calibration/6

- repository: `Example`, at `(text only: not available to read)`
- file: `Sources/Lint/CheckstyleReport.swift`, line 9
- unit: a function
- owner: `CheckstyleReport` (enum)
- owner's doc comment: Writes lint results in the Checkstyle XML format CI servers read.
- the unit's doc comment: The Checkstyle document for `issues`, grouped by file. Every value is escaped.
- same-type members that reference it: (none)
- the owner's other members in this repository (bodies left out):

```swift
// CheckstyleReport.swift: enum CheckstyleReport
private static func escaped(_ text: String) -> String
// Issue.swift, elsewhere in the module:
// struct Issue { let file: String; let line: Int; let severity: String; let message: String; let rule: String }
```

- the same-type members it references, in full:

```swift
// CheckstyleReport.swift, line 30
    private static func escaped(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            case "\t", "\n", "\r": out.unicodeScalars.append(scalar)
            case "\u{0}"..."\u{1F}", "\u{FFFE}", "\u{FFFF}": out += "\u{FFFD}"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
```

The unit:

```swift
    static func generate(_ issues: [Issue]) -> String {
        var lines = ["<?xml version=\"1.0\" encoding=\"utf-8\"?>", "<checkstyle version=\"4.3\">"]
        for (file, fileIssues) in Dictionary(grouping: issues, by: \.file).sorted(by: { $0.key < $1.key }) {
            lines.append("<file name=\"\(escaped(file))\">")
            for issue in fileIssues {
                lines.append("<error line=\"\(issue.line)\" severity=\"\(escaped(issue.severity))\" "
                    + "message=\"\(escaped(issue.message))\" source=\"\(escaped(issue.rule))\"/>")
            }
            lines.append("</file>")
        }
        lines.append("</checkstyle>")
        return lines.joined(separator: "\n")
    }
```

## calibration/7

- repository: `Example`, at `(text only: not available to read)`
- file: `Sources/Icons/SVGFrame.swift`, line 6
- unit: a function
- owner: `SVGFrame` (enum)
- owner's doc comment: Wraps drawing code in a standalone SVG document.
- the unit's doc comment: Wraps `inner`, which is SVG markup the caller has built (elements such as `<path>` and `<g>`), in an `<svg>` root of the given size.
- same-type members that reference it: (none)
- the owner's other members in this repository (bodies left out):

```swift
// SVGFrame.swift: enum SVGFrame
```

- the same-type members it references, in full:

```swift
(none)
```

The unit:

```swift
    static func document(width: Int, height: Int, inner: String) -> String {
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(width)\" height=\"\(height)\">"
            + inner
            + "</svg>"
    }
```

## calibration/8

- repository: `Example`, at `(text only: not available to read)`
- file: `Sources/Icons/IconUse.swift`, line 5
- unit: a function
- owner: `IconUse` (enum)
- owner's doc comment: Inline icons for the web dashboard. Each icon is a `<symbol>` in the sprite sheet the dashboard's page template embeds once, near the top of `<body>`.
- the unit's doc comment: An inline SVG element that draws the named icon from the page's sprite sheet.
- same-type members that reference it: (none)
- the owner's other members in this repository (bodies left out):

```swift
// IconUse.swift: enum IconUse
```

- the same-type members it references, in full:

```swift
(none)
```

The unit:

```swift
    static func svg(named name: Icon, size: Int) -> String {
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(size)\" height=\"\(size)\">"
            + "<use href=\"#icon-\(name.rawValue)\"/>"
            + "</svg>"
    }
```

## calibration/9

- repository: `Example`, at `(text only: not available to read)`
- file: `Sources/Charts/Sparkline.swift`, line 7
- unit: a function
- owner: `Sparkline` (struct)
- owner's doc comment: A small line chart of recent values.
- the unit's doc comment: A standalone SVG document drawing the sparkline as one polyline.
- same-type members that reference it: (none)
- the owner's other members in this repository (bodies left out):

```swift
// Sparkline.swift: struct Sparkline
let values: [Double]
let width: Double
let height: Double
```

- the same-type members it references, in full:

```swift
(none)
```

The unit:

```swift
    func svg() -> String {
        let maximum = max(values.max() ?? 1, 1)
        let step = values.count > 1 ? width / Double(values.count - 1) : 0
        let points = values.enumerated().map { index, value in
            String(format: "%.1f,%.1f", Double(index) * step, height - value / maximum * height)
        }.joined(separator: " ")
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(Int(width))\" height=\"\(Int(height))\">"
            + "<polyline fill=\"none\" stroke=\"#333\" points=\"\(points)\"/>"
            + "</svg>"
    }
```

## calibration/10

- repository: `Example`, at `(text only: not available to read)`
- file: `Sources/Feed/FeedWriter.swift`, line 8
- unit: a function
- owner: `FeedWriter` (struct)
- owner's doc comment: Publishes the blog's posts as an RSS 2.0 feed.
- the unit's doc comment: The RSS document for `posts`. `title` is the post's plain-text title, as the author typed it.
- same-type members that reference it: (none)
- the owner's other members in this repository (bodies left out):

```swift
// FeedWriter.swift: struct FeedWriter
let siteTitle: String
let siteURL: URL
```

- the same-type members it references, in full:

```swift
(none)
```

The unit:

```swift
    func rss(posts: [(title: String, link: URL)]) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<rss version=\"2.0\"><channel>"
        xml += "<title>\(siteTitle)</title><link>\(siteURL.absoluteString)</link>"
        for post in posts {
            xml += "<item><title>\(post.title)</title><link>\(post.link.absoluteString)</link></item>"
        }
        xml += "</channel></rss>"
        return xml
    }
```
