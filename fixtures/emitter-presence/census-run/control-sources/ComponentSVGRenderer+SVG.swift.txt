import Foundation

// MARK: - SVG output

extension ComponentSVGRenderer {

    /// Shared font-family attribute for every text element.
    private static var textFontFamily: String { "system-ui, -apple-system, sans-serif" }

    /// Render a positioned `ComponentLayout` as a standalone SVG document.
    /// Kept lightweight — Studio uses the native renderer; this SVG is the
    /// WebView fallback when the user picks .svg without launching Studio.
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

    // MARK: - SVG fragments

    static func svgHeader(width: Double, height: Double) -> String {
        let widthInt = Int(width.rounded(.up))
        let heightInt = Int(height.rounded(.up))
        return "<svg xmlns=\"http://www.w3.org/2000/svg\""
            + " width=\"\(widthInt)\" height=\"\(heightInt)\""
            + " viewBox=\"0 0 \(widthInt) \(heightInt)\">"
    }

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

    static func boxRect(
        originX: Double, originY: Double, width: Double, height: Double, fill: String
    ) -> String {
        "<rect x=\"\(format(originX))\" y=\"\(format(originY))\""
            + " width=\"\(format(width))\" height=\"\(format(height))\""
            + " fill=\"\(fill)\" stroke=\"#444\" stroke-width=\"1.2\" rx=\"4\"/>"
    }

    /// SVG `<text>` element attributes. `fontStyle` / `fontWeight` are optional;
    /// `nil` omits the attribute. Bundled into a struct so callers don't have to
    /// supply six positional arguments.
    struct TextStyle {
        let anchor: String
        let fontSize: Int
        let fontStyle: String?
        let fontWeight: String?
        let fill: String

        init(
            anchor: String,
            fontSize: Int,
            fontStyle: String? = nil,
            fontWeight: String? = nil,
            fill: String
        ) {
            self.anchor = anchor
            self.fontSize = fontSize
            self.fontStyle = fontStyle
            self.fontWeight = fontWeight
            self.fill = fill
        }
    }

    static func textElement(
        originX: Double, originY: Double, style: TextStyle, text: String
    ) -> String {
        var element = "<text x=\"\(format(originX))\" y=\"\(format(originY))\""
        element += " font-family=\"\(textFontFamily)\""
        element += " font-size=\"\(style.fontSize)\""
        if let fontStyle = style.fontStyle { element += " font-style=\"\(fontStyle)\"" }
        if let fontWeight = style.fontWeight { element += " font-weight=\"\(fontWeight)\"" }
        element += " fill=\"\(style.fill)\" text-anchor=\"\(style.anchor)\">"
        element += text.xmlEscaped
        element += "</text>"
        return element
    }

    // MARK: - Geometry / string helpers

    /// Returns the point on the rectangle border of `source` closest to
    /// `target`, used as the edge anchor.
    static func edgePoint(
        from source: PositionedComponent,
        towards target: PositionedComponent
    ) -> (Double, Double) {
        let deltaX = target.centerX - source.centerX
        let deltaY = target.centerY - source.centerY
        // Clamp slope to box aspect so we land on a top/bottom edge most of the time.
        let halfW = source.width / 2
        let halfH = source.height / 2
        guard deltaX != 0 || deltaY != 0 else {
            return (source.centerX, source.centerY)
        }
        let scaleX = halfW / max(abs(deltaX), 0.001)
        let scaleY = halfH / max(abs(deltaY), 0.001)
        let scale = min(scaleX, scaleY)
        return (source.centerX + deltaX * scale, source.centerY + deltaY * scale)
    }

    static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

}
