export const meta = {
  name: 'trigger-eval',
  description: 'Mede acuracia de disparo das skills do cstk: para cada query, um juiz ve SO as descriptions do catalogo e escolhe qual skill o Claude Code dispararia; compara com o ground-truth e devolve acuracia + matriz de confusao + misfires. Periodico (nao-CI). args = {catalog, queries} vindos de collect.sh.',
  phases: [{ title: 'Judge', model: 'sonnet' }],
}

// args = { catalog: [{name, description}], queries: [{query, expect, note?}] }
// Robusto: alguns transportes entregam `args` como STRING JSON em vez de objeto.
let A = args
if (typeof A === 'string') { try { A = JSON.parse(A) } catch (_) { A = {} } }
const catalog = (A && A.catalog) || []
const queries = (A && A.queries) || []
if (!catalog.length || !queries.length) {
  return {
    error: 'args precisa de {catalog:[...], queries:[...]} nao-vazios. Rode collect.sh e passe a saida como args.',
    _debug: { argsType: typeof args, parsedType: typeof A, keys: (A && typeof A === 'object') ? Object.keys(A) : null },
  }
}

const norm = (s) => String(s == null ? '' : s).trim().toLowerCase().replace(/[^a-z0-9-]/g, '')
const catalogText = catalog.map((c) => `- ${c.name}: ${c.description}`).join('\n')
const NAMES = new Set(catalog.map((c) => norm(c.name)))
// Anti-confabulacao: escolha fora do catalogo (ex.: juiz inventa um plugin que conhece do treino) vira
// "OUT:<x>" VISIVEL — conta como erro e nunca e aceita como skill real. Nao coerce para "none" (isso esconderia o sintoma).
const validChoice = (raw) => (norm(raw) === 'none' || NAMES.has(norm(raw))) ? raw : ('OUT:' + raw)

const SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['chosen', 'confidence', 'reason'],
  properties: {
    chosen: { type: 'string', description: 'slug exato da skill escolhida, ou "none"' },
    confidence: { type: 'number', description: 'confianca 0..1' },
    reason: { type: 'string', description: 'uma frase curta justificando' },
  },
}

const prompt = (q) => [
  'Voce SIMULA o seletor de skills do Claude Code.',
  'Abaixo o catalogo de skills no formato "slug: description" (a description e o gatilho oficial — diz o que faz e quando usar):',
  '',
  catalogText,
  '',
  `Mensagem do usuario: "${q}"`,
  '',
  'Baseando-se SOMENTE nas descriptions acima (ignore qualquer conhecimento previo que voce tenha das skills),',
  'decida qual UNICA skill o Claude Code dispararia para essa mensagem.',
  'Se NENHUMA description se aplica, responda exatamente "none".',
  'IMPORTANTE: o slug DEVE ser um dos listados no catalogo acima. NUNCA invente um nome fora do catalogo, mesmo que voce conheca outra skill/plugin do Claude Code de outro lugar; nesse caso responda "none".',
  'Responda com o slug exato (ex.: "specify", "bugfix", "analyze") ou "none".',
].join('\n')

const verdicts = await parallel(
  queries.map((q, i) => () =>
    agent(prompt(q.query), { label: `q${i}→${q.expect}`, phase: 'Judge', schema: SCHEMA, model: 'sonnet' })
      .then((v) => ({
        query: q.query,
        expect: q.expect,
        chosen: v ? validChoice(v.chosen) : 'ERROR',
        confidence: v ? v.confidence : null,
        reason: v ? v.reason : '',
      }))
      .catch(() => ({ query: q.query, expect: q.expect, chosen: 'ERROR', confidence: null, reason: 'agent error' }))
  )
)

const scored = verdicts.filter(Boolean).map((r) => ({ ...r, ok: norm(r.chosen) === norm(r.expect) }))
const wrong = scored.filter((r) => !r.ok)

// acuracia por skill esperada (recall por skill)
const byExpect = {}
for (const r of scored) {
  byExpect[r.expect] = byExpect[r.expect] || { n: 0, hit: 0 }
  byExpect[r.expect].n++
  if (r.ok) byExpect[r.expect].hit++
}

// pares de confusao "expect -> chosen" (so os erros)
const confusionPairs = {}
for (const r of wrong) {
  const k = `${r.expect} → ${norm(r.chosen) || 'EMPTY'}`
  confusionPairs[k] = (confusionPairs[k] || 0) + 1
}

const correct = scored.filter((r) => r.ok).length
return {
  total: scored.length,
  correct,
  accuracy: scored.length ? Number((correct / scored.length).toFixed(3)) : 0,
  byExpect,
  confusionPairs,
  misfires: wrong.map((r) => ({ query: r.query, expect: r.expect, chosen: r.chosen, confidence: r.confidence, reason: r.reason })),
}
