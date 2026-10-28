export const meta = {
  name: 'judge-669-census',
  description: 'Blind hand-check of #669 census rows: calibration, then judges A and B per packet, C on disagreements',
  phases: [
    { title: 'Calibrate', detail: 'two judges on the nine calibration rows; stop on any miss' },
    { title: 'Judge', detail: 'judges A and B, independently, on each of 13 packets' },
    { title: 'Settle', detail: 'judge C on every row A and B disagree on' },
  ],
}

// As run, J named the judging directory in the session's scratch directory (brief/judge-brief.md,
// brief/calibration.md, packets/packet-NN.md); set it to your own.
const J = '<judging>'
const BRIEF = `${J}/brief/judge-brief.md`
const PACKETS = Array.from({ length: 13 }, (_, i) => `packet-${String(i + 1).padStart(2, '0')}`)
const VERDICTS = ['UNIQUIFIER', 'MEMOIZING', 'BATCH', 'LOOKUP', 'NOT-UNIQUIFIER', 'UNDETERMINED']
const OWING = ['UNIQUIFIER', 'MEMOIZING']

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
          setup: { type: ['boolean', 'null'] },
          body_disagrees: { type: ['boolean', 'null'] },
          witness: { type: 'string' },
          sentinel: { type: 'string' },
          reason: { type: 'string' },
        },
        required: ['label', 'verdict', 'expressible', 'setup', 'body_disagrees', 'witness', 'sentinel', 'reason'],
      },
    },
  },
  required: ['records'],
}

const RULES = `You are a blind judge in a measurement. First read the judging brief at ${BRIEF} in full; it defines the verdicts and the three flags, and its rules bind you.

Rules, in these words: you may read only your packet and, for context, source files under the row's own repository path (the "at" path each row gives). Never open, list or search a \`docs\`, \`scripts\` or \`fixtures\` directory of the SwiftInferProperties repository (a row from that repository is read through its own file only), any \`.json\` file, any other packet or any other judge's output, and never search for a function's name outside the row's own repository. Do not open anything under ${J} except your packet and the brief. Judge each row on its own; do not guess what anyone expects and do not count. Before answering expressible or setup for a UNIQUIFIER or MEMOIZING row, read the row's whole file (when the repository is readable) and the owner's members shown.

Return one record per row (every label exactly once) through the structured output: label, verdict, expressible, setup, body_disagrees (null for all three unless the verdict is UNIQUIFIER or MEMOIZING), witness (the call sequence when body_disagrees is true, else ""), sentinel ("" if none), and a one-sentence reason.`

const EXPECTED = {
  'calibration/1': { verdict: 'UNIQUIFIER', expressible: false, setup: true },
  'calibration/2': { verdict: 'UNIQUIFIER', expressible: true, body_disagrees: true },
  'calibration/3': { verdict: 'MEMOIZING', expressible: true, setup: false, body_disagrees: false },
  'calibration/4': { verdict: 'LOOKUP' },
  'calibration/5': { verdict: 'NOT-UNIQUIFIER' },
  'calibration/6': { verdict: 'BATCH' },
  'calibration/7': { verdict: 'NOT-UNIQUIFIER' },
  'calibration/8': { verdict: 'NOT-UNIQUIFIER' },
  'calibration/9': { verdict: 'UNIQUIFIER', expressible: true, body_disagrees: true },
}

function misses(records) {
  const byLabel = Object.fromEntries((records || []).map(r => [r.label, r]))
  return Object.entries(EXPECTED).filter(([label, expected]) =>
    !byLabel[label] || Object.entries(expected).some(([field, value]) => byLabel[label][field] !== value)).map(([l]) => l)
}

function usable(r) {
  if (!r || !VERDICTS.includes(r.verdict)) return false
  return !OWING.includes(r.verdict) || ['expressible', 'setup', 'body_disagrees'].every(f => typeof r[f] === 'boolean')
}
function agree(a, b) {
  return usable(a) && usable(b) && a.verdict === b.verdict &&
    (!OWING.includes(a.verdict) || (a.expressible === b.expressible && a.setup === b.setup))
}

phase('Calibrate')
const calibration = await parallel(['A', 'B'].map(judge => () =>
  agent(`${RULES}\n\nYour packet is the calibration file ${J}/brief/calibration.md (its nine rows are labelled calibration/1 … calibration/9). Rows 1 and 3 name a repository you may read; the others are text only.`,
    { label: `calibrate:${judge}`, phase: 'Calibrate', schema: RECORDS })))
const calibrationMisses = calibration.map(result => misses(result && result.records))
log(`calibration misses: A ${JSON.stringify(calibrationMisses[0])}, B ${JSON.stringify(calibrationMisses[1])}`)
if (calibrationMisses.some(m => m.length)) {
  return { stopped: 'calibration', calibration, calibrationMisses }
}

const judged = await pipeline(
  PACKETS,
  packet => parallel(['A', 'B'].map(judge => () =>
    agent(`${RULES}\n\nYour packet is ${J}/packets/${packet}.md. Its rows are labelled ${packet}/1, ${packet}/2, ….`,
      { label: `${packet}:${judge}`, phase: 'Judge', schema: RECORDS }))),
  async (pair, packet) => {
    const [a, b] = pair.map(result => Object.fromEntries(((result && result.records) || []).map(r => [r.label, r])))
    const labels = [...new Set([...Object.keys(a), ...Object.keys(b)])].sort()
    const split = labels.filter(label => !agree(a[label], b[label]))
    let c = {}
    if (split.length) {
      const result = await agent(`${RULES}\n\nYour packet is ${J}/packets/${packet}.md. Judge ONLY these rows: ${split.join(', ')}. Return a record for each of them and no others.`,
        { label: `${packet}:C`, phase: 'Settle', schema: RECORDS })
      c = Object.fromEntries(((result && result.records) || []).map(r => [r.label, r]))
    }
    return { packet, A: a, B: b, C: c, split }
  },
)
const splits = judged.filter(Boolean).reduce((n, p) => n + p.split.length, 0)
log(`${judged.filter(Boolean).length} packets judged; ${splits} rows went to judge C`)
return { calibration, calibrationMisses, judged }
