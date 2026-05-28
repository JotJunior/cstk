# Research: agente-00c model-routing

Documento produzido no Phase 0 do `/plan`. Resolve unknowns do
Technical Context antes do design. Como `clarify` ja foi executado
(onda-002, dec-002..dec-007), TODAS as 4 DIAs originais + 1 edge case
(FR-013 truncagem) foram resolvidas na propria spec. Esta pesquisa
foca em decisoes de implementacao remanescentes que emergem do design
do plan — sem unknowns tecnicos novos.

## Decision 1: Localizacao do helper de invocacao da skill

**Decision**: criar UM helper POSIX novo em
`~/.claude/skills/agente-00c-runtime/scripts/model-routing.sh`
(fonte: `global/skills/agente-00c-runtime/scripts/model-routing.sh`),
expondo subcomandos:

- `invoke --subagent-type T --etapa E [--input-text S]` — roda a
  skill via shell direto (`sh
  ~/.claude/skills/model-selector/scripts/classify.sh "<input>"`),
  parseia saida, retorna JSON canonico em stdout.
- `template --subagent-type T` — emite o input textual deterministico
  para o `subagent_type` solicitado (resolve FR-002).
- `idempotent-check --state-dir DIR --onda-id ID --subagent-type T`
  — retorna exit 0 + decisao-id existente se ja registrada; exit 1
  se inedita (resolve FR-012).

**Rationale**: confinar a logica de parseamento + template + idempotencia
em UM arquivo identificavel respeita o Principio II §carve-out
condicao (b) — toda dep nova (mesmo opcional) deve ficar em um arquivo
unico identificavel via grep pelo nome. Distribuir a logica entre
`agente-00c-orchestrator.md` e `agente-00c-feature-orchestrator.md`
duplicaria codigo + criaria drift entre os 2 hosts.

**Alternatives considered**:

- (A) **Inline no markdown dos agents**: duplicaria ~30 linhas de
  parseamento entre 2 agents — drift garantido em mudancas de contrato
  da skill.
- (B) **Sub-script por orquestrador** (`scripts/model-routing-agente.sh`
  + `scripts/model-routing-feature.sh`): mesmo problema de duplicacao;
  templates por `subagent_type` ficariam fragmentados.
- (C) **Estender `state-decisions.sh` com subcommand `register-model`**:
  acopla parseamento de skill externa ao script canonico de decisoes
  — quebra coesao (state-decisions deveria nao saber sobre skills
  especificas).

## Decision 2: Formato do template de input por subagent_type

**Decision**: catalogo deterministico inline em
`model-routing.sh` como heredoc por `subagent_type`. Formato:

```
<perfil>. <entradas esperadas>. <saida esperada>.
```

Exemplos:

- `clarify-asker`: `enumerative scan of spec for ambiguities producing
  up to 5 questions. inputs: spec text, briefing summary, constitution
  principles. output: JSON list of questions referencing FR/edge case
  ids.`
- `clarify-answerer`: `reflective resolution of ambiguity questions
  against briefing and constitution producing scored answers. inputs:
  question batch + briefing + constitution + spec + prior decisions.
  output: JSON list of answers with score and pause-humano flag.`

**Rationale**: a skill `model-selector` ja consome string textual ate
4096 chars e classifica via catalogo de sinais em `references/sinais.md`.
Templates curtos (~200 chars) ficam bem abaixo do limite de 4096, sem
disparar FR-013 (truncagem). Catalogo inline elimina dependencia de
arquivo extra (Principio II — zero dep externa para o runtime).

**Alternatives considered**:

- (A) **Arquivo JSON externo** (`references/subagent-templates.json`):
  exige parseamento jq — adiciona dep `jq` ao caminho critico de
  spawn (slow + nao-POSIX puro).
- (B) **Heredoc por arquivo .txt** (um por `subagent_type` em
  `references/templates/`): mais arquivos para manter; nao reduz
  acoplamento (ainda precisa case statement no shell para escolher).

## Decision 3: Parser de output da skill model-selector

**Decision**: usar `awk` POSIX puro para extrair os 3 campos canonicos
(`modelo`, `score`, `alternativa`) + bloco `## Sinais detectados`.
Pattern de extracao:

```sh
modelo=$(awk -F': ' '/^\*\*modelo\*\*:/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' "$out")
score=$(awk -F': ' '/^\*\*score\*\*:/ {print $2; exit}' "$out")
alternativa=$(awk -F': ' '/^\*\*alternativa\*\*:/ {print $2; exit}' "$out")
sinais=$(awk '/^## Sinais detectados$/{flag=1; next} /^## /{flag=0} flag && /^- /' "$out")
```

**Rationale**: o contrato da skill (FR-001..FR-007 da
`contracts/skill-io.md`) declara secoes em ordem fixa e markers
literais (`**modelo**:`, `**score**:`, `**alternativa**:`).
`awk` POSIX cobre 100% do parseamento sem `jq`, sem regex Perl, sem
bash-isms. Falha silenciosa por output mal-formado vira detectavel
via teste `[ -z "$modelo" ]` que dispara fallback (FR-008).

**Alternatives considered**:

- (A) **`grep -oP`**: depende de PCRE — nao-POSIX. Ja vetado pelo
  Principio II.
- (B) **`sed`**: viavel mas mais verboso para extracao multi-linha
  do bloco "Sinais detectados". awk vence em clareza.
- (C) **Python**: viola completamente Principio II.

## Decision 4: Idempotency check via jq sobre .decisoes[]

**Decision**: a busca confirmada em dec-004 e implementada como query
jq simples:

```sh
existing=$(jq -r --arg ctx_prefix "Selecao de modelo para subagente $subagent_type" \
                  --arg onda "$onda_id" \
  '.decisoes[]
   | select(.contexto | startswith($ctx_prefix))
   | select(.onda_id == $onda)
   | .id' "$state_json" | head -n 1)
```

Se `$existing` nao-vazio, helper retorna exit 0 com `decisao_id`
existente em stdout — orquestrador pula a invocacao da skill e
prossegue para `spawn-tracker.sh enter`.

**Rationale**: `jq` ja e dep declarada do `agente-00c-runtime` (vide
`state-decisions.sh` que o usa internamente). Reusar evita introduzir
nova dep. O matcher `startswith` permite que `contexto` carregue
informacao extra apos `Selecao de modelo para subagente <type>` sem
quebrar a busca — robusto a evolucao do formato.

**Alternatives considered**:

- (A) **Adicionar campo `.ondas[N].model_selections[]`**: rejeitado
  em clarify dec-006 e dec-004 — viola Principio III (formato canonico
  do state-schema). Source-of-truth unica em `.decisoes[]` evita drift
  apos edicao manual pos-mortem.
- (B) **Hash do contexto+onda em arquivo separado** (.cache de
  invocacoes): introduz superficie de inconsistencia com state.json,
  e exige limpeza no reset.

## Decision 5: Posicionamento exato no fluxo pre-spawn

**Decision**: sequencia obrigatoria por spawn, documentada em FR-010 +
FR-011:

```
1. spawn-tracker.sh check --max-depth 3 --state-dir DIR
   (exit 0 = ha depth; exit 1 = abortar; sem invocacao da skill)
2. model-routing.sh idempotent-check ... DIR
   (se ja existe, pula 3-5)
3. model-routing.sh invoke --subagent-type T --etapa E
   (gera input via template + roda classify.sh + parseia)
4. state-decisions.sh register --score N --evidencia "<sinais>"
   (5 campos + score; N derivado do mapeamento FR-005)
5. state-ondas.sh record-skill --skill model-selector --decisao-id DEC
6. spawn-tracker.sh increment (entra no nivel do subagente)
7. tool Agent invoca o subagente
```

**Rationale**: o "check antes" (passo 1) evita gasto de tool call em
spawn que vai abortar. O "increment depois" (passo 6) garante que o
Bash da skill (executado em passo 3) rode no nivel do orquestrador,
nao no nivel do subagente prestes a nascer — Principio IV de
contencao de blast radius (skill nao deve aparecer como invocada de
subagente nao-existente).

**Alternatives considered**:

- (A) **Inverter ordem (skill antes do spawn-tracker)**: gasta tool
  call em spawn impossivel; viola Principio V (profundidade sobre
  adocao — nao desperdicar invocacao).
- (B) **Spawn-tracker.sh increment ANTES da skill**: skill rodaria
  "contabilizada" como acao do subagente — alem de quebrar audit
  trail, derruba o invariante depth=3.

## Decision 6: Mapeamento de score 0..2 → 0..3 e trava de evidencia

**Decision**: tabela de mapeamento (confirmada em dec-003):

| Skill score | Runtime score | Justificativa-fonte |
|-------------|---------------|---------------------|
| 0 | 0 | nenhum sinal matched — sugestao especulativa |
| 1 | 2 | >=1 sinal matched — decisao com suporte de contexto |
| 2 | 3 | >=2 sinais matched — decisao com evidencia empirica |

Para score=3, a `--evidencia >=20 chars` exigida por
`state-decisions.sh` (trava CHK064) e satisfeita pelo bloco
`## Sinais detectados` da skill, citado literalmente na justificativa
(FR-006). Exemplo:

```
--justificativa "Sinais matched (>=20 chars): - rode: rasa (peso=1)
- grep: rasa (peso=1). Faixa rasa vence; modelo sugerido = haiku."
```

**Rationale**: a trava de score=3 do runtime existe para prevenir
"decisoes orgulhosas" sem base empirica. A skill model-selector ja
exige >=2 sinais para score=2 — esses sinais SAO a evidencia empirica.
Mapeamento direto preserva semantica das duas escalas sem violar trava.

**Alternatives considered**:

- (A) **Sempre score=2** (independente do score da skill): perde
  informacao da heuristica; auditor nao consegue distinguir sugestoes
  fortes de fracas.
- (B) **Score 0..2 → 0..3 com 1→1**: score 1 do runtime e zona morta
  semantica (nao e pause nem decisao com base) — confusao em
  review-task.

## Decision 7: Granularidade — 1 invocacao por spawn vs por fase

**Decision**: 1 invocacao por spawn (confirmada em dec-005).

**Rationale**: clarify spawna 2 subagentes em sequencia
(asker + answerer) com perfis distintos. O asker e enumerativo
(deterministico estrutural — varre spec listando ambiguidades), o
answerer e reflexivo (raciocinio sobre constitution + briefing). A
skill model-selector tokeniza essas descricoes e detecta sinais
diferentes (`enumerative` vs `reflective`, `output JSON list` vs
`scored answers`). Compartilhar a sugestao quebraria Principio V
(profundidade sobre adocao) — abrir mao de granularidade auditavel
em troca de "1 tool call a menos" e pessimo trade-off.

**Alternatives considered**:

- 1 invocacao por fase, cache em variavel: viola Principio V; perde
  rastreabilidade fine-grained.

## Decision 8: Agregacao para review-task — derivacao real-time

**Decision**: review-task agrega via jq direto sobre `.decisoes[]`
(confirmado em dec-006). Query base na secao do relatorio:

```sh
jq -r '[.decisoes[]
        | select(.contexto | test("^Selecao de modelo para subagente "))
        | {subagent: (.contexto | capture("subagente (?<s>[^ ]+)") | .s),
           etapa, escolha, score, timestamp}]
       | group_by(.subagent)' state.json
```

**Rationale**: source-of-truth unica em `.decisoes[]` elimina risco
de drift apos edicao manual em pos-mortem. Volume tipico
(<100 decisoes/feature) torna performance nao-issue — query roda em
<50ms tipicamente.

**Alternatives considered**:

- Campo derivado em `.ondas[N].model_selections[]`: rejeitado em
  dec-006 por mesma razao (drift risk).

## Decision 9: Truncagem de input >4096 chars

**Decision**: esquema confirmado em dec-007: **2000 chars iniciais +
marcador literal `...[truncated]...` (16 chars) + 2000 chars finais**
(total = 4016, dentro do limite de 4096 com margem para UTF-8
multi-byte de ate ~80 bytes).

Helper:

```sh
truncate_input() {
  input="$1"
  len=$(printf '%s' "$input" | wc -c)
  if [ "$len" -le 4096 ]; then
    printf '%s' "$input"
    return 0
  fi
  prefix=$(printf '%s' "$input" | head -c 2000)
  suffix=$(printf '%s' "$input" | tail -c 2000)
  printf '%s...[truncated]...%s' "$prefix" "$suffix"
}
```

`justificativa` da Decisao MUST mencionar truncagem (FR-013):
`"... input truncado (2000+marker+2000); semantica de borda preservada."`

**Rationale**: preserva extremos semanticos. Perfil de subagente
(inicio do template) e saida esperada (final) sao as 2 secoes mais
discriminantes para classificacao via catalogo de sinais — meio do
texto tipicamente carrega contexto redundante.

**Alternatives considered**:

- Truncagem so do final (4080 chars + marcador): perde saida esperada,
  que e onde verbos `produzindo`, `retorna`, `emite` aparecem — sinais
  fortes do catalogo.
- Hash + summary (resumir antes de mandar): introduz invocacao de
  modelo adicional; quebra determinismo e POSIX-puro.

## Decision 10: Templates de subagent_type e extensibilidade futura

**Decision**: catalogo inicial de templates cobre EXATAMENTE os 4
subagent_types em uso hoje na fase clarify dos 2 orquestradores:

- `agente-00c-clarify-asker`
- `agente-00c-clarify-answerer`
- `feature-00c-clarify-asker`
- `feature-00c-clarify-answerer`

Templates de `clarify-asker` em ambos orquestradores sao IDENTICOS
(perfil + entradas/saida coincidem). Idem para `clarify-answerer`.
Logo, helper usa apenas 2 templates internos chaveados pelo sufixo
(`-asker` vs `-answerer`), evitando duplicacao.

**Rationale**: aplicar a novos pontos de delegacao (futuras fases que
spawnam) e mudanca incremental trivial documentada em FR-016 —
adicionar novo `case` no helper. Esta feature define o padrao; nao
sobre-engenheira para subagent_types que ainda nao existem.

**Alternatives considered**:

- 4 templates separados (1 por subagent_type): duplica template do
  asker entre agente-00c e feature-00c sem ganho de granularidade
  detectavel pela skill.

## Decision 11: Tool call accounting — contagem real vs SC-002

**Ref**: SC-002, CHK048, F4.6 da feature, FR-003, FR-004, FR-012,
plan.md §Performance Goals.

**Question**: SC-002 declara "ate 3 tool calls extras por spawn (1
Skill + 1 register Decisao + 1 record-skill)". A contagem real do
harness do Claude Code casa com esse numero?

**Decision**: MANTER SC-002 = 3, com a regra de concatenacao
abaixo. O numero 3 e atingivel SE e SOMENTE SE o orquestrador
seguir o protocolo de concatenacao Bash documentado a seguir.

### Contagem nominal (sem concatenacao)

A sequencia canonica de §5.e.bis tem 4 chamadas a ferramentas do
harness por spawn:

| # | Chamada | Tool do harness | Conta como? |
|---|---------|-----------------|--------------|
| 3 | `model-routing.sh idempotent-check` | Bash | 1 tool call |
| 4 | `model-routing.sh invoke` | Skill (via tool Skill) | 1 tool call |
| 5 | `state-decisions.sh register` | Bash | 1 tool call |
| 6 | `state-ondas.sh record-skill` | Bash | 1 tool call |

Naive = **4 tool calls**, NAO 3. Diferencial vs SC-002: o
`idempotent-check` (passo 3) e a chamada extra que SC-002 nao
contabilizou explicitamente.

### Como SC-002 ainda e satisfatorio (3 tool calls)

**Regra de concatenacao**: passos 5 e 6 (register + record-skill)
DEVEM ser concatenados em UM unico bloco Bash via `&&` no
orquestrador. Isso colapsa duas chamadas Bash em uma — o harness
conta tool-calls por invocacao da tool, nao por comando shell
dentro do bloco. Exemplo canonico:

```bash
# CORRETO — 1 tool call do harness:
DEC_ID=$("$RUNTIME_SCRIPTS"/state-decisions.sh register \
           --state-dir "$SD" --agente "$AGENT_ID" \
           --etapa clarify --contexto "..." --opcoes '[...]' \
           --escolha "$MODELO" --score "$SCORE" \
           --justificativa "$SINAIS" --evidencia "$SINAIS") \
  && "$RUNTIME_SCRIPTS"/state-ondas.sh record-skill \
       --state-dir "$SD" --onda-id "$ONDA_ID" \
       --skill model-selector --decisao-id "$DEC_ID"
```

```bash
# ERRADO — 2 tool calls (viola SC-002):
DEC_ID=$("$RUNTIME_SCRIPTS"/state-decisions.sh register ...)
# tool call separado:
"$RUNTIME_SCRIPTS"/state-ondas.sh record-skill --decisao-id "$DEC_ID"
```

Com concatenacao, a contagem cai:

| # | Chamada | Tool do harness | Conta como? |
|---|---------|-----------------|--------------|
| 3 | `idempotent-check` | Bash | 1 tool call |
| 4 | `invoke` | Skill | 1 tool call |
| 5+6 | `register && record-skill` | Bash | 1 tool call |

Total = **3 tool calls** — SC-002 satisfeito.

### Caso especial: idempotent-check HIT (decisao ja existe)

Quando `idempotent-check` retorna exit 0 (Decisao ja existe na
onda — caso comum de retomada via `/agente-00c-resume`), passos
4-6 sao pulados. Contagem = **1 tool call** (apenas o
idempotent-check). Esse e o caminho otimo; SC-002 e respeitado
trivialmente.

### Linha-base empirica

A contagem precisa ser confirmada em execucao real via
`state.json.metricas_acumuladas.tool_calls_total` antes e depois
de 1 spawn. Esse instrumento ainda NAO esta implementado nos
orquestradores (gap conhecido — task de follow-up). Subtarefa
4.6.3 fica documentada como TODO de release-notes ou issue
follow-up, sem bloquear FASE 4. Plano:

1. Pos-merge de FASE 7 (docs+release), abrir issue
   `tool-call-accounting-instrumentation` no toolkit
   (JotJunior/cstk) referenciando esta secao.
2. A issue propoe adicionar `tool-call-tick` ao runtime
   (incrementa `state.json.metricas_acumuladas.tool_calls_total`
   sob convencao manual ou hook do harness, conforme suporte do
   Claude Code).
3. Apos instrumentacao, rodar fixture E2E + validar SC-002 em
   execucao real. Atualizar esta secao com numeros medidos.

**Status atual**: SC-002 e satisfatoria por construcao (regra de
concatenacao acima); medicao empirica fica como follow-up
nao-bloqueante. A regra de concatenacao DEVE constar no
agente-00c-orchestrator.md §5.e.bis (passo 5+6) — adicionar como
TODO em F7 caso ainda nao esteja explicito.

**Alternatives considered**:

- Aceitar SC-002 = 4: viola o quality-gate da spec sem necessidade;
  a concatenacao via `&&` e Bash POSIX padrao e nao adiciona
  complexidade.
- Instrumentar agora (sub-tarefa 4.6.3 implementacional):
  requereria hook do harness ou tool wrapper, fora de escopo
  do MVP. Deferir para follow-up explicito.
- Combinar idempotent-check + invoke no mesmo Bash (`&&`): nao
  funciona — `invoke` e tool Skill, nao Bash; tool boundary
  diferente, harness conta como 2 tool calls independente de
  concatenacao shell.
