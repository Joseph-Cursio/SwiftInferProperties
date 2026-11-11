import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

// #668's two laws, written by hand for the kill arm (`docs/plans/xml-emitter-census-scope.md` §5.2). This file is
// copied into an export of SwiftUMLStudio `9ad7631`'s `SwiftUMLBridgeFrameworkTests` target by
// `scripts/xml_emitter_kill_arm.py`, never into SwiftUMLStudio itself.
//
// Law 1: a renderer's output parses under `XMLParser`, on every input outside its guard. Only `renderSVG` has one:
// it returns `""` for a layout with no components, and that draw is counted as the sentinel and not checked. On any
// other draw, `""` is a failure like any other malformed output.
// Law 2: every `url(#X)`, `href="#X"` and `xlink:href="#X"` in it names an `id="X"` in it.
//
// Each property runs 1,000 trials from a SplitMix64 generator with a fixed seed and prints one summary line,
// `XML-EMITTER-LAW <property> trials=… sentinel=… reach=… failures=…`. `sentinel` counts the draws the guard rejects;
// `reach` counts the outputs that hold at least one reference. The generators are hand-written; a built template would compose `DerivationStrategist`'s.

/// SplitMix64: a fixed seed gives the same draws on every run, so the summary lines compare across runs.
struct XMLEmitterLawRandom {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1))
    }

    mutating func double(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + Double(next() >> 11) / Double(1 << 53) * (range.upperBound - range.lowerBound)
    }

    mutating func bool() -> Bool {
        next() & 1 == 1
    }

    mutating func pick<Element>(_ items: [Element]) -> Element {
        items[int(0...(items.count - 1))]
    }
}

/// The draws (§5.2). Names that must resolve come from one small pool; text the renderers escape comes half the time
/// from letters and half the time from characters XML gives a meaning to, or forbids.
enum XMLEmitterLawDraw {
    static let pool = ["a", "b", "c", ""]
    static let letters: [Character] = ["a", "b", "c", "d", "e"]
    static let significant: [Character] = ["a", "<", ">", "&", "\"", "'", "-", "]", " ", "\u{01}", "\u{FFFE}"]

    static func text(_ random: inout XMLEmitterLawRandom) -> String {
        let alphabet = random.bool() ? letters : significant
        return String((0..<random.int(0...6)).map { _ in random.pick(alphabet) })
    }

    static func optionalText(_ random: inout XMLEmitterLawRandom) -> String? {
        random.bool() ? text(&random) : nil
    }

    static func coordinate(_ random: inout XMLEmitterLawRandom) -> Double {
        random.double(-10_000...10_000)
    }

    static func size(_ random: inout XMLEmitterLawRandom) -> Double {
        random.double(0...2_000)
    }

    static func componentLayout(_ random: inout XMLEmitterLawRandom) -> ComponentLayout {
        let kinds: [ComponentKind] = [.executable, .library, .test, .other]
        let components = (0..<random.int(0...4)).map { _ in
            let name = random.pick(pool)
            return PositionedComponent(
                id: name, name: name, kind: random.pick(kinds),
                providedInterfaces: (0..<random.int(0...3)).map { _ in text(&random) },
                centerX: coordinate(&random), centerY: coordinate(&random),
                width: size(&random), height: size(&random)
            )
        }
        let dependencies = (0..<random.int(0...4)).map { _ in
            ComponentDependency(from: random.pick(pool), to: random.pick(pool))
        }
        return ComponentLayout(
            components: components, dependencies: dependencies,
            totalWidth: size(&random), totalHeight: size(&random)
        )
    }

    static func layoutGraph(_ random: inout XMLEmitterLawRandom) -> LayoutGraph {
        let stereotypes = ["class", "struct", "enum", "protocol", "actor", "extension", "macro"]
        let styles: [EdgeStyle] = [.inheritance, .realization, .dependency, .association, .composition]
        let nodes = (0..<random.int(0...3)).map { _ in
            var node = LayoutNode(
                id: random.pick(pool), label: text(&random),
                stereotype: random.bool() ? random.pick(stereotypes) : optionalText(&random),
                compartments: (0..<random.int(0...2)).map { _ in
                    NodeCompartment(title: optionalText(&random),
                                    items: (0..<random.int(0...3)).map { _ in text(&random) })
                }
            )
            node.posX = coordinate(&random)
            node.posY = coordinate(&random)
            node.width = size(&random)
            node.height = size(&random)
            return node
        }
        let edges = (0..<random.int(0...4)).map { _ in
            var edge = LayoutEdge(
                sourceId: random.pick(pool), targetId: random.pick(pool),
                label: optionalText(&random), style: random.pick(styles)
            )
            edge.points = (0..<random.int(0...4)).map { _ in
                LayoutPoint(posX: coordinate(&random), posY: coordinate(&random))
            }
            return edge
        }
        var graph = LayoutGraph(nodes: nodes, edges: edges)
        graph.clusters = (0..<random.int(0...2)).map { _ in
            var cluster = LayoutCluster(id: text(&random), label: text(&random))
            cluster.posX = coordinate(&random)
            cluster.posY = coordinate(&random)
            cluster.width = size(&random)
            cluster.height = size(&random)
            return cluster
        }
        graph.width = size(&random)
        graph.height = size(&random)
        return graph
    }

    static func activityLayout(_ random: inout XMLEmitterLawRandom) -> ActivityLayout {
        let kinds: [ActivityNodeKind] = [.start, .end, .action, .decision, .merge, .fork, .join, .loopStart,
                                         .loopEnd]
        let nodes = (0..<random.int(0...4)).map { identifier in
            PositionedActivityNode(
                id: identifier, kind: random.pick(kinds), label: text(&random),
                centerX: coordinate(&random), centerY: coordinate(&random),
                width: size(&random), height: size(&random),
                isAsync: random.bool(), isUnresolved: random.bool()
            )
        }
        let edges = (0..<random.int(0...5)).map { _ in
            ActivityEdge(fromId: random.int(0...4), toId: random.int(0...4), label: optionalText(&random))
        }
        return ActivityLayout(
            nodes: nodes, edges: edges, title: text(&random),
            totalWidth: size(&random), totalHeight: size(&random)
        )
    }

    static func sequenceLayout(_ random: inout XMLEmitterLawRandom) -> SequenceLayout {
        let columns: [Double] = [0, 100, 200]
        let participants = (0..<random.int(0...3)).map { _ in
            SequenceParticipant(
                name: text(&random), centerX: random.pick(columns), topY: coordinate(&random),
                bottomTopY: coordinate(&random)
            )
        }
        let messages = (0..<random.int(0...4)).map { identifier in
            SequenceMessage(
                id: identifier, label: text(&random), fromX: random.pick(columns), toX: random.pick(columns),
                posY: coordinate(&random), isAsync: random.bool(), isUnresolved: random.bool(),
                noteText: optionalText(&random)
            )
        }
        return SequenceLayout(
            participants: participants, messages: messages, title: text(&random),
            totalWidth: size(&random), totalHeight: size(&random),
            lifelineStartY: coordinate(&random), lifelineEndY: coordinate(&random)
        )
    }
}

/// The two laws' checks, over the output text alone.
enum XMLEmitterLawCheck {
    /// `nil` when `document` parses, or where and why `XMLParser` rejected it.
    static func parseError(_ document: String) -> String? {
        let parser = XMLParser(data: Data(document.utf8))
        guard !parser.parse() else { return nil }
        let reason = parser.parserError.map { String(describing: $0) } ?? "no error reported"
        return "line \(parser.lineNumber), column \(parser.columnNumber): \(reason)"
    }

    private static var idPattern: NSRegularExpression {
        try! NSRegularExpression(pattern: #"(?<=\s)id=["']([^"']*)["']"#)
    }

    private static var referencePattern: NSRegularExpression {
        try! NSRegularExpression(pattern: #"url\(#([^)]*)\)|href=["']#([^"']*)["']"#)
    }

    private static func captures(_ pattern: NSRegularExpression, in document: String) -> [String] {
        let range = NSRange(document.startIndex..., in: document)
        return pattern.matches(in: document, range: range).compactMap { match in
            (1..<match.numberOfRanges).lazy
                .compactMap { Range(match.range(at: $0), in: document) }
                .first
                .map { String(document[$0]) }
        }
    }

    static func references(_ document: String) -> [String] {
        captures(referencePattern, in: document)
    }

    /// The references in `document` that name no id it defines.
    static func dangling(_ document: String) -> [String] {
        let ids = Set(captures(idPattern, in: document))
        return references(document).filter { !ids.contains($0) }
    }
}

/// One property: draw, render, check, and print the summary line.
enum XMLEmitterLawRun {
    static let trials = 1_000

    static func property(
        _ name: String,
        seed: UInt64,
        draw: (inout XMLEmitterLawRandom) -> (input: String, output: String, guarded: Bool),
        failure: (String) -> String?
    ) {
        var random = XMLEmitterLawRandom(state: seed)
        var sentinel = 0, reach = 0, failures = 0
        var first: String?
        for trial in 0..<trials {
            let (input, output, guarded) = draw(&random)
            if guarded {
                sentinel += 1
                continue
            }
            if !XMLEmitterLawCheck.references(output).isEmpty {
                reach += 1
            }
            if let reason = failure(output) {
                failures += 1
                if first == nil {
                    first = "trial \(trial): \(reason)\ninput: \(input)\noutput:\n\(output)"
                }
            }
        }
        print("XML-EMITTER-LAW \(name) trials=\(trials) sentinel=\(sentinel) reach=\(reach) failures=\(failures)")
        #expect(failures == 0, "\(name): \(failures) of \(trials) trials fail; the first:\n\(first ?? "")")
    }

    static func law1(_ output: String) -> String? {
        XMLEmitterLawCheck.parseError(output)
    }

    static func law2(_ output: String) -> String? {
        let dangling = XMLEmitterLawCheck.dangling(output)
        return dangling.isEmpty ? nil : "references to undefined ids: \(dangling)"
    }

    /// `renderSVG`'s guard: a layout with no components gets `""`.
    static func component(_ random: inout XMLEmitterLawRandom) -> (input: String, output: String, guarded: Bool) {
        let layout = XMLEmitterLawDraw.componentLayout(&random)
        return (String(describing: layout), ComponentSVGRenderer.renderSVG(layout), layout.components.isEmpty)
    }

    static func graph(_ random: inout XMLEmitterLawRandom) -> (input: String, output: String, guarded: Bool) {
        let graph = XMLEmitterLawDraw.layoutGraph(&random)
        return (String(describing: graph), SVGRenderer.render(graph), false)
    }

    static func activity(_ random: inout XMLEmitterLawRandom) -> (input: String, output: String, guarded: Bool) {
        let layout = XMLEmitterLawDraw.activityLayout(&random)
        return (String(describing: layout), ActivitySVGRenderer.renderFromLayout(layout), false)
    }

    static func sequence(_ random: inout XMLEmitterLawRandom) -> (input: String, output: String, guarded: Bool) {
        let layout = XMLEmitterLawDraw.sequenceLayout(&random)
        return (String(describing: layout), SequenceSVGRenderer.renderFromLayout(layout), false)
    }
}

/// Law 1: the document parses.
@Suite struct XMLEmitterLaw1Tests {
    @Test("P-C: ComponentSVGRenderer.renderSVG's document parses")
    func componentParses() {
        XMLEmitterLawRun.property("P-C", seed: 0x668_0C01, draw: XMLEmitterLawRun.component,
                                  failure: XMLEmitterLawRun.law1)
    }

    @Test("P-S: SVGRenderer.render's document parses")
    func graphParses() {
        XMLEmitterLawRun.property("P-S", seed: 0x668_0501, draw: XMLEmitterLawRun.graph,
                                  failure: XMLEmitterLawRun.law1)
    }

    @Test("P-A: ActivitySVGRenderer.renderFromLayout's document parses")
    func activityParses() {
        XMLEmitterLawRun.property("P-A", seed: 0x668_0A01, draw: XMLEmitterLawRun.activity,
                                  failure: XMLEmitterLawRun.law1)
    }

    @Test("P-Q: SequenceSVGRenderer.renderFromLayout's document parses")
    func sequenceParses() {
        XMLEmitterLawRun.property("P-Q", seed: 0x668_0E01, draw: XMLEmitterLawRun.sequence,
                                  failure: XMLEmitterLawRun.law1)
    }
}

/// Law 2: every same-document reference resolves. The same draws as Law 1, from the same seeds.
@Suite struct XMLEmitterLaw2Tests {
    @Test("R-C: ComponentSVGRenderer.renderSVG's references resolve")
    func componentResolves() {
        XMLEmitterLawRun.property("R-C", seed: 0x668_0C01, draw: XMLEmitterLawRun.component,
                                  failure: XMLEmitterLawRun.law2)
    }

    @Test("R-S: SVGRenderer.render's references resolve")
    func graphResolves() {
        XMLEmitterLawRun.property("R-S", seed: 0x668_0501, draw: XMLEmitterLawRun.graph,
                                  failure: XMLEmitterLawRun.law2)
    }

    @Test("R-A: ActivitySVGRenderer.renderFromLayout's references resolve")
    func activityResolves() {
        XMLEmitterLawRun.property("R-A", seed: 0x668_0A01, draw: XMLEmitterLawRun.activity,
                                  failure: XMLEmitterLawRun.law2)
    }

    @Test("R-Q: SequenceSVGRenderer.renderFromLayout's references resolve")
    func sequenceResolves() {
        XMLEmitterLawRun.property("R-Q", seed: 0x668_0E01, draw: XMLEmitterLawRun.sequence,
                                  failure: XMLEmitterLawRun.law2)
    }
}
