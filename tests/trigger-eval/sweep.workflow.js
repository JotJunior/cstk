export const meta = {
  name: 'trigger-eval-sweep',
  description: 'Sweep multi-modelo do trigger-eval: julga CADA query com N modelos (default sonnet vs haiku) e compara acuracia por modelo + divergencias. O sinal-ouro e "modelo fraco erra mas o forte acerta" = description fragil sob modelo menor. args = {catalog, queries, models?}.',
  phases: [{ title: 'Sweep' }],
}

let A = args
if (typeof A === 'string') { try { A = JSON.parse(A) } catch (_) { A = {} } }
const catalog = (A && A.catalog) || []
const queries = (A && A.queries) || []
const models = (A && Array.isArray(A.models) && A.models.length) ? A.models : ['sonnet', 'haiku']
if (!catalog.length || !queries.length) {
  return { error: 'args precisa de {catalog:[...], queries:[...], models?}', _debug: { argsType: typeof args, keys: (A && typeof A === 'object') ? Object.keys(A) : null } }
}

const norm = (s) => String(s == null ? '' : s).trim().toLowerCase().replace(/[^a-z0-9-]/g, '')
const catalogText = catalog.map((c) => `- ${c.name}: ${c.description}`).join('\n')
const NAMES = new Set(catalog.map((c) => norm(c.name)))
const validChoice = (raw) => (norm(raw) === 'none' || NAMES.has(norm(raw))) ? raw : ('OUT:' + raw)

const SCHEMA = {
  type: 'object', additionalProperties: false, required: ['chosen', 'confidence', 'reason'],
  properties: {
    chosen: { type: 'string', description: 'slug exato do catalogo, ou "none"' },
    confidence: { type: 'number' }, reason: { type: 'string' },
  },
}

const prompt = (q) => [
  'Voce SIMULA o seletor de skills do Claude Code.',
  'Catalogo (slug: description — a description e o gatilho oficial):', '', catalogText, '',
  `Mensagem do usuario: "${q}"`,
  'Baseando-se SOMENTE nas descriptions acima (ignore conhecimento previo das skills), qual UNICA skill dispararia?',
  'Se nenhuma se aplica, responda "none". O slug DEVE estar no catalogo; NUNCA invente um nome fora dele (mesmo que conheca outra skill/plugin) — nesse caso "none".',
  'Responda o slug exato ou "none".',
].join('\n')

const rows = await parallel(
  queries.map((q, i) => async () => {
    const verdicts = await parallel(
      models.map((m) => () =>
        agent(prompt(q.query), { label: `${m}:q${i}→${q.expect}`, phase: 'Sweep', schema: SCHEMA, model: m })
          .then((v) => ({ m, chosen: v ? validChoice(v.chosen) : 'ERROR', confidence: v ? v.confidence : null, reason: v ? v.reason : '' }))
          .catch(() => ({ m, chosen: 'ERROR', confidence: null, reason: 'agent error' }))
      )
    )
    const perModel = {}
    for (const r of verdicts) if (r) perModel[r.m] = { chosen: r.chosen, ok: norm(r.chosen) === norm(q.expect), confidence: r.confidence, reason: r.reason }
    return { query: q.query, expect: q.expect, perModel }
  })
)

// acuracia + matriz de confusao por modelo
const byModel = {}
for (const m of models) {
  const judged = rows.map((r) => r.perModel[m]).filter(Boolean)
  const correct = judged.filter((x) => x.ok).length
  const confusionPairs = {}
  for (const r of rows) {
    const x = r.perModel[m]
    if (x && !x.ok) {
      const k = `${r.expect} → ${norm(x.chosen) || 'EMPTY'}`
      confusionPairs[k] = (confusionPairs[k] || 0) + 1
    }
  }
  byModel[m] = { total: judged.length, correct, accuracy: judged.length ? Number((correct / judged.length).toFixed(3)) : 0, confusionPairs }
}

// divergencias: ref = models[0] (forte), alt = models[ultimo] (fraco)
const ref = models[0]
const alt = models[models.length - 1]
const pick = (r) => ({ query: r.query, expect: r.expect, [ref]: r.perModel[ref], [alt]: r.perModel[alt] })
const weak_misses_strong_hits = []
const strong_misses_weak_hits = []
const both_miss = []
if (ref !== alt) {
  for (const r of rows) {
    const a = r.perModel[ref]
    const b = r.perModel[alt]
    if (!a || !b) continue
    if (a.ok && !b.ok) weak_misses_strong_hits.push(pick(r))
    else if (!a.ok && b.ok) strong_misses_weak_hits.push(pick(r))
    else if (!a.ok && !b.ok) both_miss.push(pick(r))
  }
}

return {
  models,
  total: rows.length,
  byModel,
  divergence_ref_vs_alt: { ref, alt },
  weak_misses_strong_hits, // <- description fragil sob o modelo fraco (o sinal-ouro)
  strong_misses_weak_hits,
  both_miss,
}
