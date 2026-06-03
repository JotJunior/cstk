export const meta = {
  name: 'trigger-eval-ab',
  description: 'A/B causal de UMA description: julga cada query com o catalogo usando a description ANTIGA vs a NOVA de um slug (resto do catalogo identico), por modelo. Mede fixed (antigo erra/novo acerta), regressed (antigo acerta/novo erra), bothOk, bothBad. args = {catalog (com a desc NOVA), targetSlug, descOld, queries, models?}.',
  phases: [{ title: 'A/B' }],
}

let A = args
if (typeof A === 'string') { try { A = JSON.parse(A) } catch (_) { A = {} } }
const catalogNew = (A && A.catalog) || []
const targetSlug = (A && A.targetSlug) || 'plan'
const descOld = A && A.descOld
const queries = (A && A.queries) || []
const models = (A && Array.isArray(A.models) && A.models.length) ? A.models : ['sonnet', 'haiku']
if (!catalogNew.length || !queries.length || !descOld) {
  return { error: 'args precisa de {catalog, targetSlug, descOld, queries, models?}', _debug: { argsType: typeof args, keys: (A && typeof A === 'object') ? Object.keys(A) : null } }
}

const norm = (s) => String(s == null ? '' : s).trim().toLowerCase().replace(/[^a-z0-9-]/g, '')
const NAMES = new Set(catalogNew.map((c) => norm(c.name)))
const validChoice = (raw) => (norm(raw) === 'none' || NAMES.has(norm(raw))) ? raw : ('OUT:' + raw)
const catalogOld = catalogNew.map((c) => norm(c.name) === norm(targetSlug) ? { ...c, description: descOld } : c)
const textOf = (cat) => cat.map((c) => `- ${c.name}: ${c.description}`).join('\n')
const textOld = textOf(catalogOld)
const textNew = textOf(catalogNew)

const SCHEMA = {
  type: 'object', additionalProperties: false, required: ['chosen', 'confidence', 'reason'],
  properties: { chosen: { type: 'string' }, confidence: { type: 'number' }, reason: { type: 'string' } },
}
const prompt = (catText, q) => [
  'Voce SIMULA o seletor de skills do Claude Code.',
  'Catalogo (slug: description):', '', catText, '',
  `Mensagem do usuario: "${q}"`,
  'Baseando-se SOMENTE nas descriptions acima (ignore conhecimento previo das skills), qual UNICA skill dispararia?',
  'Se nenhuma se aplica, "none". O slug DEVE estar no catalogo; NUNCA invente nome fora dele — nesse caso "none".',
  'Responda o slug exato ou "none".',
].join('\n')

const rows = await parallel(
  queries.map((q, i) => async () => {
    const verds = await parallel(
      models.map((m) => async () => {
        const [vo, vn] = await Promise.all([
          agent(prompt(textOld, q.query), { label: `${m}/old:q${i}→${q.expect}`, phase: 'A/B', schema: SCHEMA, model: m }).catch(() => null),
          agent(prompt(textNew, q.query), { label: `${m}/new:q${i}→${q.expect}`, phase: 'A/B', schema: SCHEMA, model: m }).catch(() => null),
        ])
        const co = vo ? validChoice(vo.chosen) : 'ERROR'
        const cn = vn ? validChoice(vn.chosen) : 'ERROR'
        return { m, old: { chosen: co, ok: norm(co) === norm(q.expect) }, new: { chosen: cn, ok: norm(cn) === norm(q.expect) } }
      })
    )
    const perModel = {}
    for (const v of verds) if (v) perModel[v.m] = v
    return { query: q.query, expect: q.expect, perModel }
  })
)

const byModel = {}
for (const m of models) {
  const fixed = []
  const regressed = []
  let bothOk = 0
  let bothBad = 0
  for (const r of rows) {
    const c = r.perModel[m]
    if (!c) continue
    if (!c.old.ok && c.new.ok) fixed.push({ query: r.query, expect: r.expect, old: c.old.chosen, new: c.new.chosen })
    else if (c.old.ok && !c.new.ok) regressed.push({ query: r.query, expect: r.expect, old: c.old.chosen, new: c.new.chosen })
    else if (c.old.ok && c.new.ok) bothOk++
    else bothBad++
  }
  const accOld = rows.filter((r) => r.perModel[m] && r.perModel[m].old.ok).length
  const accNew = rows.filter((r) => r.perModel[m] && r.perModel[m].new.ok).length
  byModel[m] = { total: rows.length, accOld, accNew, fixed, regressed, bothOk, bothBad }
}

return { models, targetSlug, total: rows.length, byModel }
