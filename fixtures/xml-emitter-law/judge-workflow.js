export const meta = {
  name: 'judge-668-census',
  description: 'Blind hand-check of #668 census rows: calibration, then judges A and B per packet, C on disagreements',
  phases: [
    { title: 'Calibrate', detail: 'two judges on the ten calibration rows; stop on any miss' },
    { title: 'Judge', detail: 'judges A and B, independently, on each packet' },
    { title: 'Settle', detail: 'judge C on every row A and B disagree on' },
  ],
}

// Set args.judging to the judging directory (brief/judge-brief.md, brief/calibration.md, packets/packet-NN.md) and
// args.sizes to each packet's row count, in order: the sizes.json `xml_emitter_census.py packets` writes beside the
// packet directory.
const J = args && args.judging
const SIZES = (args && args.sizes) || []
const PACKETS = SIZES.map((_, i) => `packet-${String(i + 1).padStart(2, '0')}`)
const BRIEF = `${J}/brief/judge-brief.md`
const VERDICTS = ['DOCUMENT', 'FRAGMENT', 'HTML', 'NOT-EMITTER', 'UNDETERMINED']
const LAW2 = ['OWES', 'VACUOUS', 'EXTERNAL', 'NOT-SVG']

const RECORDS = {
  type: 'object',
  properties: {
    records: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          label: { type: 'string' },
          verdict: { type: 'string', enum: VERDICTS },
          expressible: { type: ['boolean', 'null'] },
          ambient: { type: ['boolean', 'null'] },
          sentinel: { type: 'string' },
          law2: { type: ['string', 'null'], enum: [...LAW2, null] },
          body_disagrees: { type: ['boolean', 'null'] },
          refs_dangle: { type: ['boolean', 'null'] },
          witness: { type: 'string' },
          reason: { type: 'string' },
        },
        required: ['label', 'verdict', 'expressible', 'ambient', 'sentinel', 'law2', 'body_disagrees', 'refs_dangle',
                   'witness', 'reason'],
      },
    },
  },
  required: ['records'],
}

const RULES = `You are a blind judge in a measurement. First read the judging brief at ${BRIEF} in full; it defines the verdicts and the flags, and its rules bind you.

Rules, in these words: you may read only your packet and, for context, source files under the row's own repository path (the "at" path each row gives). Never open, list or search a \`docs\`, \`scripts\` or \`fixtures\` directory of the SwiftInferProperties repository (a row from that repository is read through its own file only), any \`.json\` file, any other packet or any other judge's output, and never search for a unit's name outside the row's own repository. Do not open anything under ${J} except your packet and the brief. Judge each row on its own; do not guess what anyone expects and do not count. Before answering expressible, ambient, law2, body_disagrees or refs_dangle for a DOCUMENT row, read the row's whole file (when the repository is readable) and every same-type member it references.

Return one record per row (every label exactly once) through the structured output: label, verdict, expressible, ambient, sentinel ("none" if there is none), law2, body_disagrees, refs_dangle (null for expressible, ambient, law2, body_disagrees and refs_dangle unless the verdict is DOCUMENT; refs_dangle false unless law2 is OWES), witness (the input and the malformed or dangling text when a flag is true, else ""), and a one-sentence reason.`

const EXPECTED = {
  'calibration/1': { verdict: 'DOCUMENT', expressible: true, law2: 'OWES', body_disagrees: false, refs_dangle: false },
  'calibration/2': { verdict: 'FRAGMENT' },
  'calibration/3': { verdict: 'DOCUMENT', expressible: true, body_disagrees: true },
  'calibration/4': { verdict: 'HTML' },
  'calibration/5': { verdict: 'NOT-EMITTER' },
  'calibration/6': { verdict: 'DOCUMENT', expressible: true, law2: 'NOT-SVG', body_disagrees: false },
  'calibration/7': { verdict: 'DOCUMENT', expressible: false },
  'calibration/8': { verdict: 'DOCUMENT', law2: 'EXTERNAL' },
  'calibration/9': { verdict: 'DOCUMENT', law2: 'VACUOUS' },
  'calibration/10': { verdict: 'DOCUMENT', expressible: true, body_disagrees: true },
}

function counts(records) {
  const n = {}
  for (const r of records || []) n[r.label] = (n[r.label] || 0) + 1
  return n
}

// xml_emitter_census.calibrate's rule: a label missing, repeated, not usable, or missing a field's expected value is
// a miss.
function misses(records) {
  const n = counts(records)
  const byLabel = Object.fromEntries((records || []).map(r => [r.label, r]))
  return Object.entries(EXPECTED).filter(([label, expected]) =>
    n[label] !== 1 || !usable(byLabel[label]) ||
    Object.entries(expected).some(([field, value]) => byLabel[label][field] !== value)).map(([l]) => l)
}

// Whether `records` name each of `labels` exactly once and nothing else.
function complete(records, labels) {
  const n = counts(records)
  return labels.every(l => n[l] === 1) && Object.keys(n).every(l => labels.includes(l))
}

// §4.3: a judge whose records do not name each of its labels exactly once is asked again, once, as a fresh agent,
// and the second answer stands either way. The raw records are returned, never a map, so that `join` sees a repeat.
async function judge(prompt, opts, labels) {
  const first = await agent(prompt, opts)
  if (complete(first && first.records, labels)) return { records: first.records, retried: false }
  log(`${opts.label}: records do not name each label once; asking a fresh judge again`)
  const second = await agent(prompt, { ...opts, label: `${opts.label}:again` })
  return { records: (second && second.records) || [], retried: true }
}

function byLabel(records) {
  return Object.fromEntries(records.map(r => [r.label, r]))
}

function usable(r) {
  if (!r || !VERDICTS.includes(r.verdict)) return false
  return r.verdict !== 'DOCUMENT' ||
    (['expressible', 'ambient', 'body_disagrees', 'refs_dangle'].every(f => typeof r[f] === 'boolean') && LAW2.includes(r.law2))
}
function agree(a, b) {
  return usable(a) && usable(b) && a.verdict === b.verdict &&
    (a.verdict !== 'DOCUMENT' || (a.expressible === b.expressible && a.law2 === b.law2))
}

phase('Calibrate')
// §4.2: a calibration agent that returns nothing (an error, not an answer) is asked again, once; the second answer
// stands either way.
const CALIBRATE = `${RULES}\n\nYour packet is the calibration file ${J}/brief/calibration.md (its ten rows are labelled calibration/1 … calibration/10). For rows 1 and 2 you may read, in the repository they name, only the row's own file and the files that declare the members and types it references; read nothing else there. Rows 3 to 10 are text only: read nothing beyond the calibration file for them.`
const calibration = await parallel(['A', 'B'].map(name => async () => {
  const first = await agent(CALIBRATE, { label: `calibrate:${name}`, phase: 'Calibrate', schema: RECORDS })
  if (first) return first
  log(`calibrate:${name} returned nothing; asking a fresh judge again`)
  return agent(CALIBRATE, { label: `calibrate:${name}:again`, phase: 'Calibrate', schema: RECORDS })
}))
const calibrationMisses = calibration.map(result => misses(result && result.records))
log(`calibration misses: A ${JSON.stringify(calibrationMisses[0])}, B ${JSON.stringify(calibrationMisses[1])}`)
if (calibrationMisses.some(m => m.length)) {
  return { stopped: 'calibration', calibration, calibrationMisses }
}

const judged = await pipeline(
  PACKETS,
  (packet, _, index) => {
    const labels = Array.from({ length: SIZES[index] }, (_, i) => `${packet}/${i + 1}`)
    return parallel(['A', 'B'].map(name => () =>
      judge(`${RULES}\n\nYour packet is ${J}/packets/${packet}.md. Its rows are labelled ${packet}/1, ${packet}/2, ….`,
        { label: `${packet}:${name}`, phase: 'Judge', schema: RECORDS }, labels)))
  },
  async (pair, packet) => {
    const [a, b] = pair.map(result => (result && result.records) || [])
    const [mapA, mapB] = [byLabel(a), byLabel(b)]
    const labels = [...new Set([...Object.keys(mapA), ...Object.keys(mapB)])].sort()
    const split = labels.filter(label => !agree(mapA[label], mapB[label]))
    let c = { records: [], retried: false }
    if (split.length) {
      c = await judge(`${RULES}\n\nYour packet is ${J}/packets/${packet}.md. Judge ONLY these rows: ${split.join(', ')}. Return a record for each of them and no others.`,
        { label: `${packet}:C`, phase: 'Settle', schema: RECORDS }, split)
    }
    const retried = [pair[0], pair[1], c].map((r, i) => (r && r.retried ? ['A', 'B', 'C'][i] : null)).filter(Boolean)
    return { packet, split, records: { A: a, B: b, C: c.records }, retried }
  },
)
const splits = judged.filter(Boolean).reduce((n, p) => n + p.split.length, 0)
log(`${judged.filter(Boolean).length} packets judged; ${splits} rows went to judge C`)
return { calibration, calibrationMisses, judged }
