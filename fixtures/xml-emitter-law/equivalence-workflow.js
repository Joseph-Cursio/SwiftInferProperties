export const meta = {
  name: 'read-668-survivors',
  description: "Read each mutant that survived #668's two laws and the full suite, for equivalence (scope §5.6)",
  phases: [
    { title: 'Read', detail: 'one agent per batch of survivors: what each mutant changes in the output, and whether a law could see it' },
  ],
}

// docs/plans/xml-emitter-census-scope.md §5.6: every mutant that survived both laws and the full suite is read for
// equivalence. args: { export, batches }. `export` is the SwiftUMLStudio export at 9ad7631 the kill arm ran on;
// each batch lists mutants as the kill arm's report holds them (id, file, function, operator, line, offset,
// original, replacement), `file` relative to SwiftUMLBridge/Sources/SwiftUMLBridgeFramework.
const EXPORT = args && args.export
const BATCHES = (args && args.batches) || []

const ROW = {
  type: 'object',
  properties: {
    id: { type: 'string' },
    class: { type: 'string', enum: ['EQUIVALENT', 'GEOMETRY', 'STYLE', 'TEXT', 'STRUCTURE', 'UNREACHED'],
             description: 'EQUIVALENT: no input changes the output. GEOMETRY: only numbers in the output change (a coordinate, a size, a path point). STYLE: only a colour, a stroke or a dash pattern changes. TEXT: only the text content of an element changes. STRUCTURE: elements or attributes appear, vanish or move. UNREACHED: the changed code is never run by any input the renderer accepts.' },
    what_changes: { type: 'string', description: 'for one concrete input, the output before and after, in a phrase' },
    law1_could_see: { type: 'boolean', description: 'can any input make the mutated output malformed XML?' },
    law2_could_see: { type: 'boolean', description: 'can any input make the mutated output carry a same-document reference that names no id?' },
    reason: { type: 'string' },
  },
  required: ['id', 'class', 'what_changes', 'law1_could_see', 'law2_could_see', 'reason'],
}
const SCHEMA = { type: 'object', properties: { rows: { type: 'array', items: ROW } }, required: ['rows'] }

phase('Read')
const read = await parallel(BATCHES.map((batch, i) => () => {
  const mutants = batch.map(m => `- ${m.id}: ${m.file} ${m.function} line ${m.line}, ${m.operator}, offset ${m.offset}: \`${m.original}\` → \`${m.replacement}\``).join('\n')
  return agent(`You are reading mutants of SwiftUMLStudio's SVG renderers that survived two hand-written laws and the package's full test suite, to say what each changes. Law 1: the renderer's output is a well-formed XML document (XMLParser accepts it). Law 2: every url(#X), href="#X" and xlink:href="#X" in it names an id="X" in it.

The source is the export at ${EXPORT}/SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/<file>, at SwiftUMLStudio 9ad7631. Each mutant replaces the text \`original\` at the given character offset of its file with \`replacement\` (an operator mutation, or for remove-side-effects the removal of a call statement). Read each mutant in its function, and the functions and types it touches, and classify it. You may write scratch files only under ${EXPORT}/../survivor-reading/${i}/. Do not edit the export. Do not run the XMLEmitterLaw suites. Reading is enough; build and run only if a case cannot be settled by reading, and then only in a copy.

Mutants:
${mutants}

Return one record per mutant.`, { label: `read:${i + 1}`, phase: 'Read', schema: SCHEMA })
}))
log(`${read.filter(Boolean).length} of ${BATCHES.length} batches read`)
return { rows: read.flatMap(r => (r && r.rows) || []) }
