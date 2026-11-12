// #673's kill arm (`docs/plans/emitter-presence-census-scope.md` §1.3–§1.4). Three laws over SwiftUMLBridge's
// `ComponentScript.buildPlantUMLText` and `buildMermaidText`, each under two generators. Each test is named after
// its law and generator, so the runner can attribute a failure to one cell.
import Foundation
import PropertyBased
import PropertyLawKit
@testable import EmitterSubject
import Testing

let seed = Seed(stateA: 0x6730_0001, stateB: 0x6730_0002, stateC: 0x6730_0003, stateD: 0x6730_0004)
let kinds: [ComponentKind] = [.executable, .library, .test, .other]
let kind = Gen<ComponentKind?>.element(of: kinds).map { $0! }

// MARK: - Generators (§1.4)

/// The run's stub: `letterOrNumber.string(of: 0...8)` names, `array(of: 0...8)` everywhere, and dependency
/// endpoints drawn independently of the component names.
func naiveModel() -> Generator<ComponentModel, some SendableSequenceType> {
    let name = Gen<Character>.letterOrNumber.string(of: 0 ... 8)
    let component = zip(zip(name, kind), name.array(of: 0 ... 8)).map { head, interfaces in
        Component(name: head.0, kind: head.1, providedInterfaces: interfaces)
    }
    let dependency = zip(name, name).map { ComponentDependency(from: $0, to: $1) }
    return zip(component.array(of: 0 ... 8), dependency.array(of: 0 ... 8)).map {
        ComponentModel(components: $0, dependencies: $1)
    }
}

/// Two lowercase letters naming index `i`; unique per index, so no drawn name is a substring of another.
func code(_ index: Int) -> String {
    let letters = Array("abcdefghijklmnopqrstuvwxyz")
    return String([letters[(index / 26) % 26], letters[index % 26]])
}

/// #673's stub requirements: component names `C<code>_<4–8 letters>`, interface names `I<code>_<4–8 letters>`
/// (distinct per kind, none a substring of another, none in the boilerplate, all fixed points of `safeAlias`),
/// 1–4 components with 0–3 interfaces each, and 0–4 dependencies whose endpoints are drawn component names.
func disciplinedModel() -> Generator<ComponentModel, some SendableSequenceType> {
    let suffix = Gen<Character?>.element(of: Array("abcdefghijklmnopqrstuvwxyz")).map { $0! }.string(of: 4 ... 8)
    let rawComponent = zip(zip(suffix, kind), suffix.array(of: 0 ... 3))
    let rawDependency = zip(Gen.int(in: 0 ... 3), Gen.int(in: 0 ... 3))
    return zip(rawComponent.array(of: 1 ... 4), rawDependency.array(of: 0 ... 4)).map { raws, edges in
        var interfaceIndex = 0
        let components = raws.enumerated().map { index, raw in
            let interfaces = raw.1.map { tail -> String in
                defer { interfaceIndex += 1 }
                return "I\(code(interfaceIndex))_\(tail)"
            }
            return Component(name: "C\(code(index))_\(raw.0.0)", kind: raw.0.1, providedInterfaces: interfaces)
        }
        let dependencies = edges.map { edge in
            ComponentDependency(
                from: components[edge.0 % components.count].name, to: components[edge.1 % components.count].name
            )
        }
        return ComponentModel(components: components, dependencies: dependencies)
    }
}

// MARK: - Laws (§1.3)

let plantUML = ComponentScript.buildPlantUMLText
let mermaid = ComponentScript.buildMermaidText
let alias = ComponentScript.safeAlias

/// Determinism, the advisory the run gave both builders. The control.
func deterministic(_ model: ComponentModel) -> Bool {
    plantUML(model) == plantUML(model) && mermaid(model) == mermaid(model)
}

/// Bare presence: every name the loops visit occurs in the output. The empty name occurs in every string, but
/// Foundation's `contains("")` answers `false`, so it is spelled out; without it the original fails this law
/// under the naïve generator, which draws `""` (measured on the first run of this arm).
func barePresent(_ model: ComponentModel) -> Bool {
    let names = model.components.flatMap { [$0.name] + $0.providedInterfaces }
        + model.dependencies.flatMap { [$0.from, $0.to] }
    return [plantUML(model), mermaid(model)].allSatisfy { text in
        names.allSatisfy { $0.isEmpty || text.contains($0) }
    }
}

/// Template presence, #673's law: each obligation `R` reads from the original bodies (§2.4), with `safeAlias`
/// called as #673's sketch calls it. L48's run is cut at the `stereotype` interpolation (a segment obligation).
func templatePresent(_ model: ComponentModel) -> Bool {
    let plant = plantUML(model)
    let merm = mermaid(model)
    for component in model.components {
        guard plant.contains("component \"\(component.name)\" as \(alias(component.name)) ") else { return false }
        guard merm.contains("    subgraph \(alias(component.name))[\"\(component.name)\"]") else { return false }
        for interfaceName in component.providedInterfaces {
            guard plant.contains("  [\(interfaceName)]") else { return false }
            guard merm.contains("        \(alias("\(component.name)_\(interfaceName)"))[\"\(interfaceName)\"]")
            else { return false }
        }
    }
    for dependency in model.dependencies {
        guard plant.contains("\(alias(dependency.from)) ..> \(alias(dependency.to))") else { return false }
        guard merm.contains("    \(alias(dependency.from)) -.-> \(alias(dependency.to))") else { return false }
    }
    return true
}

func check(
    _ label: String, _ generator: Generator<ComponentModel, some SendableSequenceType>,
    _ property: @escaping @Sendable (ComponentModel) -> Bool
) async {
    let result = await SwiftPropertyBasedBackend().check(
        trials: 100, seed: seed, sample: { rng in generator.run(using: &rng) }, property: property
    )
    if case let .failed(_, _, input, _) = result { Issue.record("\(label) failed at \(input)") }
}

@Test func determinismNaive() async { await check("determinism/naive", naiveModel(), deterministic) }
@Test func determinismDisciplined() async { await check("determinism/disciplined", disciplinedModel(), deterministic) }
@Test func bareNaive() async { await check("bare/naive", naiveModel(), barePresent) }
@Test func bareDisciplined() async { await check("bare/disciplined", disciplinedModel(), barePresent) }
@Test func templateNaive() async { await check("template/naive", naiveModel(), templatePresent) }
@Test func templateDisciplined() async { await check("template/disciplined", disciplinedModel(), templatePresent) }

/// Reach, not a law: how many of 100 draws fill each loop. Always passes; the runner records the counts.
@Test func reach() {
    for (label, generator) in [("naive", AnyGen(naiveModel())), ("disciplined", AnyGen(disciplinedModel()))] {
        var rng = Xoshiro(seed: (seed.stateA, seed.stateB, seed.stateC, seed.stateD))
        let draws = (0 ..< 100).map { _ in generator.draw(&rng) }
        let components = draws.filter { !$0.components.isEmpty }.count
        let interfaces = draws.filter { $0.components.contains { !$0.providedInterfaces.isEmpty } }.count
        let dependencies = draws.filter { !$0.dependencies.isEmpty }.count
        let emptyName = draws.filter { $0.components.contains { $0.name.isEmpty } }.count
        print("REACH \(label) components=\(components) interfaces=\(interfaces) dependencies=\(dependencies) emptyName=\(emptyName)")
    }
}

/// Erases the generator's shrink type so `reach` can loop over both.
struct AnyGen {
    let draw: (inout Xoshiro) -> ComponentModel
    init(_ generator: Generator<ComponentModel, some SendableSequenceType>) {
        draw = { rng in generator.run(using: &rng) }
    }
}
