# Research: model-selector

Documento produzido no Phase 0 do `/plan`. Resolve todos os
`NEEDS CLARIFICATION` remanescentes do Technical Context antes do design
do Phase 1. Decisoes ja cravadas em `/clarify` (dec-004 a dec-008) sao
citadas e nao re-litigadas — este documento foca em decisoes tecnicas
finas que `/clarify` deixou aberto.

---

## Decision 1: Parsing do catalogo `references/sinais.md` em POSIX puro

**Decision**: Parsear `references/sinais.md` via `awk` em modo
streaming, lendo apenas linhas que casam o padrao tabela-markdown
`^| <termo> | <faixa> | <peso> |`. Header e separator (`|---|`) sao
ignorados via filtro `NR>2 && /^\|/ && !/^\|[ -]*\|/`. Termo
normalizado para lowercase via `tolower($2)` antes da comparacao com
o input. Peso default = 1 quando coluna ausente.

**Rationale**: Constitution Principio II proibe `jq`/`ripgrep` no
classificador (FR-010a confina `jq` apenas em `scripts/report.sh`).
`awk` POSIX-padrao processa formato tabular markdown de forma
deterministica e auditavel. Streaming evita carregar arquivo inteiro
em memoria (catalogo pode crescer com customizacoes do operador
conforme FR-004). Lowercase normaliza variacoes do operador (`Rode` vs
`rode`) sem necessitar regex case-insensitive (que tem pegadinhas
POSIX vs GNU).

**Alternatives considered**:
- `grep -E + cut` — fragil em colunas com espacos no termo, exigiria
  delimitador custom.
- Arquivo formato `flat-text` (`termo|faixa|peso` sem markdown) —
  perde legibilidade humana (briefing favorece markdown como formato
  primario do toolkit) e duplica formatos com o restante das skills.
- JSON em vez de markdown — exigiria `jq` para parsing seguro, viola
  Principio II fora do escopo do carve-out FR-010a.

---

## Decision 2: Mecanismo de detecao de sinais no input

**Decision**: Tokenizar o input do usuario via `tr -s '[:space:][:punct:]'
'\n'` (split por whitespace + pontuacao em uma linha por token),
normalizar para lowercase via `tr 'A-Z' 'a-z'`, e para cada termo do
catalogo, testar match com `grep -Fxq` (fixed-string, exact-line,
quiet) contra a lista de tokens. Score por faixa = soma dos pesos dos
sinais matched. Faixa vencedora = maior score (com tie-break
conservador por FR-005).

**Rationale**: `grep -F` evita interpretacao regex (operador pode
adicionar termos com `.`, `*` em customizacoes — FR-004 — sem quebrar
o classificador). `-x` (exact line match) garante que `rode` no
catalogo nao casa com `rodeio` no input (false positive). `-q`
suprime output (apenas exit code conta). Tokenizar via `tr` e POSIX
puro e portavel entre macOS/Linux. Pontuacao removida antes do match
para que `"rode grep -c TODO"` produza tokens `rode`, `grep`, `c`,
`todo` (verbo e ferramenta detectados independentemente).

**Alternatives considered**:
- `awk` com `index($0, term)` — match substring causa false positives
  (`rode` matching dentro de `rodeio` ou `corrode`).
- Regex `\b<termo>\b` — `\b` nao e POSIX BRE/ERE padrao; comportamento
  varia entre GNU grep e BSD grep.
- Pre-compilar regex unica de alternancia (`(rode|liste|conte|...)`)
  — performance ganho marginal (catalogo MVP=15 sinais); perde
  auditabilidade (qual sinal especifico matched?).

---

## Decision 3: Mecanismo de parametrizacao do modelo no spawn de subagente

**Decision**: A skill `model-selector` **nao** propoe mecanismo de
spawn — ela emite apenas a *sugestao* em formato canonico (Decision 4).
O orquestrador que recebe a sugestao (agente-00c ou feature-00c) e
responsavel por traduzir a sugestao em parametro de spawn. O mecanismo
concreto (flag CLI, prompt-prefix, header) e **fora do escopo desta
feature** — pertence ao orquestrador.

**Rationale**: Principio IV (zero coleta remota + blast radius
confinado) + FR-006 (sugestao informativa, nunca prescritiva). Acoplar
a skill ao mecanismo de spawn violaria duas linhas:
1. Skill ficaria dependente do harness Claude Code (versao da tool
   Agent, formato dos parametros), contrariando estabilidade
   pretendida pelo rotulo abstrato (dec-005).
2. Skill teria que conhecer todos os orquestradores que a chamam
   (agente-00c, feature-00c, futuros), violando blast radius.
A skill expoe **contrato de saida** (Decision 4); orquestradores
adaptam. Documenta-se como Gotcha em `SKILL.md`: "skill nao spawna,
nao troca modelo, nao chama `/model` — apenas sugere".

**Alternatives considered**:
- Skill emite shell-command pronto (`agente-00c-spawn --model haiku
  ...`) — acopla a um orquestrador especifico, quebra blast radius.
- Skill aceita callback path — exigiria tool `Bash` no `allowed-tools`
  da skill, ampliando superficie sem necessidade (FR-006).
- Convencao de variavel de ambiente (`MODEL_SELECTOR_SUGGESTION`)
  exportada — adiciona estado oculto, viola "skill stateless por
  invocacao" (FR-015).

---

## Decision 4: Formato do output da skill

**Decision**: Output em **markdown estruturado** com 4 secoes fixas
(ordem deterministica para parsing facil pelo orquestrador):

```markdown
## Sugestao

**modelo**: <haiku|sonnet|opus|manter-atual>
**score**: <0|1|2>  (teto pratico = 2 conforme dec-006)
**alternativa**: <haiku|sonnet|opus|none>

## Sinais detectados

- <termo>: <faixa> (peso=<N>)
- ...

## Justificativa

<texto livre em 1-3 frases citando os sinais decisivos>

## Acao sugerida (operador humano)

`/model <modelo>` (se operador quiser trocar; nao executado pela skill)
```

**Rationale**:
- Markdown e o formato canonico do toolkit (briefing + Principio III).
- Secoes fixas permitem que `state-decisions.sh register` (chamado
  pelo orquestrador) extraia `escolha=modelo`, `score=score` e
  `justificativa=secao Justificativa` via `awk` simples — sem `jq`,
  conforme Principio II.
- Score como inteiro literal (0/1/2) evita ambiguidade de ponto
  decimal entre locales (`,` vs `.`).
- "Acao sugerida" e literal em sintaxe `/model <x>` para que o
  operador humano (User Story 2) possa **copiar e colar** sem
  reformatacao — preserva o contrato FR-006 (skill informativa, troca
  e do humano).
- Ausencia de campo `versao-concreta` reforca dec-005 (rotulo
  abstrato).

**Alternatives considered**:
- JSON output — exigiria `jq` no orquestrador para extrair (toleravel
  por FR-010a, mas a sugestao nao roda em `scripts/report.sh` — roda
  em chamada inline pelo orquestrador, onde `jq` esta vetado).
- YAML — nao e POSIX-amigavel para parsing via awk; nao padrao no
  toolkit.
- Texto plano sem secoes (`modelo=haiku score=2 ...`) — perde
  legibilidade humana; quebra Principio III (description-como-trigger
  e gotchas exigem fluencia em markdown).

---

## Decision 5: Parsing de `state.json` no script de relatorio (FR-012)

**Decision**: `scripts/report.sh` detecta presenca de `jq` via
`command -v jq >/dev/null 2>&1`. Se presente, usa `jq` para extrair
contadores. Se ausente, usa fallback POSIX puro: `grep`+`awk` lendo
linha-a-linha procurando padrao `"modelo_sugerido"\s*:\s*"(haiku|
sonnet|opus|manter-atual)"` e incrementando contadores por chave.
Ambos os caminhos produzem **mesma tabela markdown final**. Teste
automatizado obrigatorio em `tests/test_report_without_jq.sh`
desabilita `jq` via `PATH` modificado e valida output identico ao
caminho com `jq`.

**Rationale**: FR-010a carve-out 1.1.0 satisfaz as 3 condicoes:
(a) **fallback graceful documentado e testavel** — caminho POSIX puro
existe e e coberto por teste dedicado;
(b) **codigo `jq` confinado em UM arquivo** — apenas
`scripts/report.sh` cita `jq`, verificavel por `grep -rn '\bjq\b'
global/skills/model-selector/` retornando UM arquivo;
(c) **declaracao explicita** — FR-010a do `spec.md` documenta o uso,
o caminho confinado e o fallback.
A degradacao de UX no fallback e aceitavel: o operador sem `jq`
recebe relatorio identico, possivelmente alguns ms mais lento
(awk linha-a-linha vs jq); SC-003 mantem meta <500ms para 20
execucoes mesmo no fallback.

**Alternatives considered**:
- Sempre POSIX puro (sem `jq` opcional) — viola dec-008 que cravou o
  uso do carve-out; parsing JSON aninhado com `awk` puro e fragil
  para arrays de objetos (state.decisoes), aumentando risco de bug.
- `jq` obrigatorio — viola Principio II MUST e o carve-out 1.1.0
  exige fallback.
- Python para parsing — adiciona dep nao-POSIX (Principio II) e
  toolkit nao tem precedente de scripts Python.

---

## Decision 6: Localizacao da sugestao no `state.json` (FR-011)

**Decision**: Sugestoes acumuladas em
`metricas_acumuladas.model_selector` (objeto novo dentro do contador
existente). Estrutura:

```json
"metricas_acumuladas": {
  "model_selector": {
    "sugestoes_total": 5,
    "por_modelo_sugerido": {
      "haiku": 2,
      "sonnet": 1,
      "opus": 0,
      "manter-atual": 2
    },
    "por_resultado": {
      "aceitas": 3,
      "rejeitadas": 2,
      "no_op_ja_no_modelo": 0
    },
    "ultima_invocacao_iso": "2026-05-21T12:34:56Z"
  }
}
```

Cada Decisao individual continua sendo registrada em `state.decisoes`
via `state-decisions.sh register` (FR-007) com `contexto` citando
"sugestao do model-selector" e `referencias` apontando ao input
classificado. O objeto agregado em `metricas_acumuladas` e cache de
leitura rapida para o relatorio (FR-012) — derivavel de
`state.decisoes` se necessario.

**Rationale**: Reusa o schema existente do runtime
(`metricas_acumuladas` ja existe com `ondas_total`, `decisoes_total`,
etc — ver state.json desta propria execucao). Adicionar um filho
nomeado e zero-impacto na compatibilidade do schema (campos novos sao
opcionais). Mantem auditabilidade via `state.decisoes` (Principio I)
e legibilidade rapida via `metricas_acumuladas` (suporte ao SC-003).
Nome do filho (`model_selector`) casa com o short-name da feature.

**Alternatives considered**:
- Campo top-level novo (`state.sugestoes_model_selector`) —
  poluiria o schema raiz do state.json para uma feature opcional;
  qualquer feature futura faria o mesmo, fragmentando o schema.
- Apenas em `state.decisoes` (sem agregado) — relatorio teria que
  iterar todas as decisoes a cada chamada; risco de SC-003 (<500ms
  em 20 execucoes) ficar marginal em features longas com muitas
  decisoes.
- Arquivo proprio (`<state-dir>/model-selector-metrics.json`) —
  duplica mecanismo de lock/backup ja resolvido pelo runtime;
  fragmenta a fonte da verdade.

---

## Decision 7: Comportamento em input vazio / muito curto

**Decision**: Input com `<3 tokens nao vazios` apos tokenizacao e
classificado como **ambiguo** com sugestao `manter-atual` e score `0`
(zero confianca). Justificativa cita literalmente "input curto
demais para classificacao confiavel: <N> tokens uteis". Faixa-default
NUNCA e `haiku` — fail-safe favorece conservadorismo (FR-005,
edge case 1 da spec).

**Rationale**: Sub-3 tokens cobre casos como `""`, `"oi"`, `"fix bug"`
— todos sem sinal suficiente para classificacao. Limiar 3 e
empiricamente razoavel (verbo + objeto + qualificador minimo) e
documentavel como gotcha. Score 0 e literal "zero confianca" no
schema 0..3, alinhado com FR-EVI-001 (score baixo = pausa, score >=2
= decisao).

**Alternatives considered**:
- Limiar 5 tokens — descarta casos validos curtos como `"rode grep
  src/"` (3 tokens, classificavel para haiku).
- Limiar 1 token — `"refatore"` sozinho ja classifica para opus; mas
  inputs reais raramente sao 1 token, e classificar sem objeto perde
  contexto.
- Erro/abort no input vazio — viola FR-005 (favorecer conservador)
  e quebra robustez; sugestao "manter-atual" com score 0 e a
  resposta certa.

---

## Decision 8: Cobertura de teste minima e localizacao

**Decision**: Testes residem em
`tests/cstk/test_model_selector_*.sh` (mesmo padrao da suite
`shell-scripts-tests` em construcao). Cobertura minima MVP (FR-017):

| Teste | Cenario coberto | Sinal de SC |
|-------|-----------------|-------------|
| `test_model_selector_faixa_rasa.sh` | input "rode grep -c TODO src/" → haiku, score 2 | SC-001 |
| `test_model_selector_faixa_media.sh` | input "explique este modulo" → sonnet, score 2 | SC-001 |
| `test_model_selector_faixa_profunda.sh` | input "refatore para usar Repository pattern" → manter-atual, score 2 | SC-001, SC-006 |
| `test_model_selector_ambiguo.sh` | input "explique e refatore" → manter-atual (conservador) | FR-005 |
| `test_model_selector_input_vazio.sh` | input "" → manter-atual, score 0 | Decision 7 |
| `test_model_selector_zero_rede.sh` | `grep -rn 'curl\|wget\|http' global/skills/model-selector/` retorna vazio | SC-005 |
| `test_model_selector_skill_lines.sh` | `wc -l < SKILL.md` <200 | SC-004 |
| `test_report_without_jq.sh` | `scripts/report.sh` com `jq` mascarado produz output identico ao com `jq` | FR-010a (a) |
| `test_report_jq_confinement.sh` | `grep -rn '\bjq\b' global/skills/model-selector/` retorna apenas `scripts/report.sh` | FR-010a (b) |
| `test_report_performance.sh` | `time scripts/report.sh <fixture>` <500ms em 20 state.json mockados | SC-003 |

**Rationale**: Cobertura cobre cada SC mensuravel + cada FR critico
(005, 010a, 017). Testes shellscript seguem o padrao da suite ja
existente em `tests/` — facilita integracao com `tests/run.sh` quando
a suite `shell-scripts-tests` for finalizada. Cada teste e
**determinstico e local** (sem rede, sem fixtures externas — Principio
IV), aderente a Principio II (POSIX puro).

**Alternatives considered**:
- bats ou outro framework de shell — vetado pela constitution (L97).
- Testes em outra linguagem (Python pytest) — viola Principio II e
  toolkit nao tem precedente.
- Apenas 3 testes (1 por faixa) — cobertura insuficiente para
  FR-005 (sinais contraditorios), FR-010a (a)/(b) e SC-005 (zero
  rede), todos requisitos verificaveis empiricamente.

---

## Decision 9: Comportamento quando modelo sugerido nao disponivel no harness

**Decision**: A skill SEMPRE emite **dois rotulos** no output (Decision 4):
- `modelo` = a sugestao otimizada (ex: `haiku`)
- `alternativa` = o proximo tier-acima do mesmo "perfil de barateamento"
  (ex: `sonnet` se a sugestao primaria era `haiku`)

Tier-mapping fixo (hardcoded em `scripts/classify.sh`):
- sugestao `haiku` → alternativa `sonnet`
- sugestao `sonnet` → alternativa `opus`
- sugestao `opus` → alternativa `none` (ja no topo)
- sugestao `manter-atual` → alternativa `none` (no-op)

A skill **nao tenta detectar disponibilidade** do modelo no harness
(seria HTTP/IPC, violaria Principio IV). E responsabilidade do
orquestrador/operador: se o modelo primario nao esta disponivel,
ele usa o `alternativa` da sugestao.

**Rationale**: Edge case 3 da spec ("modelo sugerido nao disponivel
no harness") exige falha graceful. Detectar disponibilidade
runtime exigiria chamada externa (proibida por IV) ou estado
persistente (proibido por FR-015 stateless). Emitir dois rotulos
upfront resolve sem violacao. O custo e marginal (~10 bytes de
output extra). Documentavel como gotcha: "se modelo primario nao
disponivel, use o `alternativa`".

**Alternatives considered**:
- Emitir apenas modelo primario, deixar fallback implicito ao operador
  — perde auditabilidade (orquestrador nao sabe qual e o fallback
  canonico).
- Tabela configuravel de fallback em `references/tiers.md` — overkill
  para MVP de 15 sinais; tier-mapping de 4 entradas e estavel.
- Skill consulta API do harness para listar modelos disponiveis —
  proibido por Principio IV.

---

## Resumo das decisoes

| Topico | Resumo |
|--------|--------|
| 1. Parsing catalogo | `awk` POSIX em modo streaming sobre tabela markdown |
| 2. Detecao sinais | tokenizacao por `tr` + `grep -Fxq` (fixed-string exact-line) |
| 3. Spawn de subagente | **Nao e responsabilidade da skill** — orquestrador integra |
| 4. Output format | Markdown estruturado com 4 secoes fixas (rotulo abstrato dec-005) |
| 5. Parsing state.json | `jq` opcional no `scripts/report.sh` + fallback POSIX (FR-010a) |
| 6. Local no state.json | `metricas_acumuladas.model_selector` + `state.decisoes` (audit) |
| 7. Input curto/vazio | <3 tokens → `manter-atual` + score 0 (fail-safe) |
| 8. Testes | 10 testes shellscript em `tests/cstk/test_model_selector_*.sh` |
| 9. Modelo indisponivel | Output sempre traz `alternativa` (tier-mapping hardcoded) |

Zero `NEEDS CLARIFICATION` remanescentes. Phase 1 (design) liberado.
