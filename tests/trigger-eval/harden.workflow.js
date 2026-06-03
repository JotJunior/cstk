export const meta = {
  name: 'trigger-eval-harden',
  description: 'Endurece o seed de trigger-eval: gera queries adversariais por cluster de overlap (sem trigger-keywords), faz ground-check cetico (descarta mal-fundadas) e julga (juiz ve SO as descriptions). Devolve acuracia + misfires REAIS + keep-set defensavel para persistir. args = {catalog, clusters}.',
  phases: [
    { title: 'Generate', model: 'sonnet' },
    { title: 'Ground-check', model: 'sonnet' },
    { title: 'Judge', model: 'sonnet' },
  ],
}

let A = args
if (typeof A === 'string') { try { A = JSON.parse(A) } catch (_) { A = {} } }
const catalog = (A && A.catalog) || []
const clusters = (A && A.clusters) || []
if (!catalog.length || !clusters.length) {
  return { error: 'args precisa de {catalog:[...], clusters:[...]}', _debug: { argsType: typeof args, keys: A && typeof A === 'object' ? Object.keys(A) : null } }
}

const norm = (s) => String(s == null ? '' : s).trim().toLowerCase().replace(/[^a-z0-9-]/g, '')
const catalogText = catalog.map((c) => `- ${c.name}: ${c.description}`).join('\n')
const NAMES = new Set(catalog.map((c) => norm(c.name)))
// Anti-confabulacao: escolha do juiz fora do catalogo vira "OUT:<x>" visivel (conta como erro), nunca skill real.
const validChoice = (raw) => (norm(raw) === 'none' || NAMES.has(norm(raw))) ? raw : ('OUT:' + raw)

const GEN_SCHEMA = {
  type: 'object', additionalProperties: false, required: ['queries'],
  properties: {
    queries: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false, required: ['query', 'expect', 'flirts_with', 'rationale'],
        properties: {
          query: { type: 'string' }, expect: { type: 'string' },
          flirts_with: { type: 'string' }, rationale: { type: 'string' },
        },
      },
    },
  },
}
const CHECK_SCHEMA = {
  type: 'object', additionalProperties: false, required: ['verdict', 'why'],
  properties: { verdict: { type: 'string', enum: ['clear', 'ambiguous', 'wrong'] }, better: { type: 'string' }, why: { type: 'string' } },
}
const JUDGE_SCHEMA = {
  type: 'object', additionalProperties: false, required: ['chosen', 'confidence', 'reason'],
  properties: { chosen: { type: 'string' }, confidence: { type: 'number' }, reason: { type: 'string' } },
}

const genPrompt = (cl) => [
  'Voce gera queries ADVERSARIAIS para testar o disparo (triggering) de skills do Claude Code.',
  'Catalogo completo (slug: description):', '', catalogText, '',
  `Tarefa: gere ${cl.n} mensagens de usuario REALISTAS cuja skill correta seja UMA de: [${cl.focus.join(', ')}].`,
  (cl.confusers && cl.confusers.length) ? `Faca cada query FLERTAR com a fronteira de: [${cl.confusers.join(', ')}] — perto de confundir, mas com resposta correta ainda defensavel.` : '',
  cl.hint ? `Dica do cluster: ${cl.hint}` : '',
  'REGRAS CRITICAS:',
  '- NAO use as trigger-keywords literais da description da skill correta (nao copie "cross-check", "OWASP", "backlog", "dashboard de features" etc.). Expresse a INTENCAO em linguagem natural de usuario (pt-br, pode ser informal/baguncado).',
  '- Cada query deve ter UMA resposta defensavel no campo expect. Se a resposta correta for "nenhuma skill se aplica", use expect="none".',
  '- Realista, como um dev pediria de verdade — nao um gotcha artificial.',
  'Devolva para cada uma: query, expect (slug exato ou "none"), flirts_with (a skill que quase dispara), rationale (1 frase: por que expect e defensavelmente a certa).',
].filter(Boolean).join('\n')

const checkPrompt = (cand) => [
  'Voce e um revisor CETICO de evals de disparo de skill. Seu trabalho e barrar queries mal-fundadas.',
  'Catalogo (slug: description):', '', catalogText, '',
  `Query: "${cand.query}"`,
  `Resposta proposta (expect): "${cand.expect}"`,
  'Lendo SOMENTE as descriptions, um leitor cuidadoso escolheria INEQUIVOCAMENTE a resposta proposta?',
  '- verdict="clear": expect e claramente a unica melhor opcao.',
  '- verdict="ambiguous": 2 ou mais skills cabem de verdade (entao a query nao serve para medir description).',
  '- verdict="wrong": outra skill e claramente melhor (informe qual em "better").',
  'Seja rigoroso: na duvida entre clear e ambiguous, escolha ambiguous.',
].join('\n')

const judgePrompt = (q) => [
  'Voce SIMULA o seletor de skills do Claude Code.',
  'Catalogo (slug: description):', '', catalogText, '',
  `Mensagem do usuario: "${q}"`,
  'Baseando-se SOMENTE nas descriptions (ignore conhecimento previo das skills), qual UNICA skill dispararia?',
  'O slug DEVE estar no catalogo acima. NUNCA invente um nome fora do catalogo (mesmo que conheca outra skill/plugin); nesse caso responda "none".',
  'Se nenhuma description se aplica, responda "none". Responda o slug exato ou "none".',
].join('\n')

const perCluster = await parallel(
  clusters.map((cl) => async () => {
    const gen = await agent(genPrompt(cl), { label: `gen:${cl.focus.join('/')}`, phase: 'Generate', schema: GEN_SCHEMA, model: 'sonnet' }).catch(() => null)
    if (!gen || !Array.isArray(gen.queries)) return []
    return await parallel(
      gen.queries.map((cand) => async () => {
        const chk = await agent(checkPrompt(cand), { label: `chk:${cand.expect}`, phase: 'Ground-check', schema: CHECK_SCHEMA, model: 'sonnet' }).catch(() => null)
        const grounding = chk ? chk.verdict : 'error'
        const base = {
          cluster: cl.focus.join('/'), query: cand.query, expect: cand.expect,
          flirts_with: cand.flirts_with, grounding, check_why: chk ? chk.why : '', better: chk ? chk.better : '',
        }
        if (grounding !== 'clear') return { ...base, skipped: true }
        const j = await agent(judgePrompt(cand.query), { label: `judge:${cand.expect}`, phase: 'Judge', schema: JUDGE_SCHEMA, model: 'sonnet' }).catch(() => null)
        const chosen = j ? validChoice(j.chosen) : 'ERROR'
        return { ...base, chosen, ok: norm(chosen) === norm(cand.expect), confidence: j ? j.confidence : null, reason: j ? j.reason : '' }
      })
    )
  })
)

const all = perCluster.filter(Boolean).flat().filter(Boolean)
const judged = all.filter((r) => !r.skipped)
const skipped = all.filter((r) => r.skipped)
const correct = judged.filter((r) => r.ok)
const misfires = judged.filter((r) => !r.ok)

const confusionPairs = {}
for (const r of misfires) {
  const k = `${r.expect} → ${norm(r.chosen) || 'EMPTY'}`
  confusionPairs[k] = (confusionPairs[k] || 0) + 1
}

return {
  generated: all.length,
  judged: judged.length,
  skipped_misgrounded: skipped.length,
  accuracy: judged.length ? Number((correct.length / judged.length).toFixed(3)) : 0,
  confusionPairs,
  misfires: misfires.map((r) => ({ cluster: r.cluster, query: r.query, expect: r.expect, chosen: r.chosen, confidence: r.confidence, flirts_with: r.flirts_with, reason: r.reason })),
  keep: judged.map((r) => ({ query: r.query, expect: r.expect, ok: r.ok, cluster: r.cluster })),
  dropped: skipped.map((r) => ({ query: r.query, expect: r.expect, grounding: r.grounding, better: r.better, why: r.check_why })),
}
