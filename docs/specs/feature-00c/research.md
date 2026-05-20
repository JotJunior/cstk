# Research: Feature-00C — Phase 0

Documento Phase 0 do `/plan`. Resolve as duvidas tecnicas materiais
identificadas durante `/specify` + `/clarify` + `/checklist`. Decisoes
auditaveis registradas com **Decision / Rationale / Alternatives considered**.

---

## Decision 1: Reuso do runtime POSIX do agente-00c

**Decision**: Reaproveitar `global/skills/agente-00c-runtime/scripts/`
**inteiramente** via parametrizacao de PATH de estado, sem fork. Os 21 scripts
ja existentes (state-rw, state-lock, state-ondas, state-decisions,
state-validate, secrets-filter, sanitize, drift, circular, retro, cycles,
budget, bash-guard, path-guard, whitelist-validate, report, suggestions,
issue, spawn-tracker, bloqueios, pipeline) aceitam o diretorio de estado
como primeiro argumento OU via variavel `AGENTE_00C_STATE_DIR`.

Onde o agente-00c hoje opera em `<projeto-alvo>/.claude/agente-00c-state/`,
o feature-00c invoca os MESMOS scripts apontando para
`<projeto-alvo>/.claude/feature-00c-state/<short-name>/`.

Scripts que hardcodam path do estado serao auditados e parametrizados — a
parametrizacao e refactor pequeno, retrocompativel (default = path do 00c
para nao quebrar `/agente-00c`).

**Rationale**: 21 scripts POSIX testados e em producao via `/agente-00c`
representam meses de iteracao + bugfix (commit e457dfa para pre-flight,
5d38baa para isolamento PATH, etc). Duplicar implicaria divergencia de
comportamento entre `/agente-00c` e `/feature-00c` — exatamente o que
FR-010A proibe. Parametrizacao tem custo baixo (1 PR de refactor) e
beneficio alto (bug fixes propagam para os dois orquestradores).

**Alternatives considered**:

- **Fork dos scripts em runtime-feature-00c**: rejeitado por divergencia
  garantida ao longo do tempo. Constitution §V (profundidade > adocao)
  favorece refinamento compartilhado.
- **Novo runtime escrito do zero**: rejeitado por duplicar comportamento
  ja validado. Violaria SDD recursivo (Principio I) — esta feature
  existe justamente para reusar a maquinaria do 00c em escopo menor.
- **Wrapper bash que delega aos scripts do 00c**: rejeitado por adicionar
  indirecao sem ganho — parametrizar diretamente e mais simples.

**Implicacao de spec**: FR-008 (Skill tool) e FR-029 (heranca de seguranca)
sao satisfeitos via reuso direto, nao por reimplementacao.

---

## Decision 2: Agentes asker/answerer — novos arquivos com namespace dedicado

**Decision**: Criar `global/agents/feature-00c-clarify-asker.md` e
`global/agents/feature-00c-clarify-answerer.md` como **arquivos de agente
separados**, com system prompt parametrizado por escopo (feature vs projeto)
mas **logica de scoring identica** ao agente-00c. NAO usar composicao via
prompt compartilhado nem reuso direto dos agentes do 00c.

System prompt e mesmo modelo dos agentes do 00c, com:
- Escopo declarado: "voce opera no contexto de UMA feature dentro de um
  projeto ja com briefing + constitution ratificados"
- Lista de fontes de scoring: briefing + constitution + spec_corrente +
  decisoes_anteriores (o 00c usa briefing + constitution + stack-sugerida
  + decisoes_anteriores — feature-00c troca stack por spec_corrente)
- Comportamento de score 0..3 IDENTICO ao 00c

**Rationale**: 3 sinais empurram para arquivos separados:

1. **Discoverability**: usuarios que listam `global/agents/` veem dois
   agentes de feature distintos dos dois do 00c — namespace claro.
2. **Audit trail**: decisoes do answerer ficam atribuidas a
   `feature-00c-clarify-answerer`, nao a `agente-00c-clarify-answerer` —
   importante para o relatorio (campo `agente_responsavel`).
3. **Evolucao independente**: feature-00c pode precisar de heuristicas
   especificas (ex: priorizar `spec_corrente` sobre `briefing` quando
   conflitam — caso que nao ocorre no 00c porque o briefing ainda esta
   sendo construido). Arquivos separados permitem ajustar sem mexer no 00c.

O custo (duplicacao de ~2-3 paragrafos de instrucao) e baixo porque o
core (algoritmo de scoring 0..3) ja vive no system prompt e e curto.

**Alternatives considered**:

- **Reuso direto dos agentes do 00c** (mesma decisao mas escolha B do
  clarify): rejeitada pelos 3 sinais acima. Acoplamento desnecessario.
- **Prompt compartilhado parametrizado por scope** (escolha C do clarify):
  rejeitada por adicionar mecanismo (template engine ou injecao de
  parametros) sem ganho proporcional. Constitution §V (profundidade >
  adocao) favorece solucao simples e duplicacao consciente sobre
  mecanismo elegante.

**Implicacao de spec**: FR-009 — a "decisao tecnica fica para /plan" agora
esta resolvida aqui em Decision 2. A spec NAO precisa ser atualizada
(deferral consciente foi cumprido).

---

## Decision 3: Layout de arquivos no toolkit

**Decision**: Novos arquivos sob `global/`:

```
global/
├── agents/
│   ├── agente-00c-feature-orchestrator.md    [NOVO]
│   ├── feature-00c-clarify-asker.md          [NOVO]
│   └── feature-00c-clarify-answerer.md       [NOVO]
├── commands/
│   ├── feature-00c.md                        [NOVO]
│   ├── feature-00c-resume.md                 [NOVO]
│   └── feature-00c-abort.md                  [NOVO]
└── skills/
    └── agente-00c-runtime/
        └── scripts/
            ├── (21 scripts existentes — parametrizados)
            └── feature-00c-preflight.sh      [NOVO]
```

Total: **6 arquivos novos** + 21 scripts parametrizados (refactor
retrocompativel).

Estado do orquestrador no projeto-alvo:

```
<projeto-alvo>/.claude/
├── agente-00c-state/              [pre-existente, do /agente-00c]
└── feature-00c-state/
    └── <short-name>/              [namespace por feature]
        ├── state.json
        ├── state.json.sha256
        ├── .lock
        ├── feature-00c-report.md
        └── backups/
            └── wave-NNN.json
```

Suggestions sao compartilhadas no projeto-alvo (append-only):
`<projeto-alvo>/.claude/feature-00c-suggestions.md`.

**Rationale**: layout espelha exatamente o do agente-00c (mesmas 3
categorias: agents, commands, skills/runtime), facilitando navegacao
para quem ja conhece o 00c. O namespace `feature-00c-state/<short-name>/`
satisfaz FR-011 (paralelismo de features) + FR-028 (lock por short-name).

**Alternatives considered**:

- **Mesclar todos os arquivos sob `global/agents/agente-00c/feature/`**:
  rejeitada porque Claude Code descobre agents/commands em diretorios
  flat — subdiretorios complicariam discovery.
- **Estado dentro de `docs/specs/<short-name>/.feature-00c-state/`**:
  rejeitada por misturar artefatos SDD (spec, plan, tasks) com estado
  operacional do orquestrador. `.claude/` e o lugar canonico para
  estado de tooling.

---

## Decision 4: Pre-flight constitution-conflict — reuso via novo script

**Decision**: Adicionar `feature-00c-preflight.sh` em
`global/skills/agente-00c-runtime/scripts/` que invoca a logica existente
do enforcement de FR-010A (commit e457dfa). O script:

1. Recebe path da spec corrente + path da constitution
2. Le MUSTs da constitution (regex sobre `## Core Principles` + `### N.`
   + linhas com `MUST:`)
3. Para cada MUST, faz match contra requirements da spec
4. Se conflito detectado, gera diagnostico estruturado (JSON com `must`,
   `clausula_spec`, `linha`, `justificativa_conflito`) e retorna exit
   code 1
5. Se nenhum conflito, exit code 0

O orquestrador-feature invoca este script antes de transitar `clarify → plan`
e bloqueia se exit code != 0.

A logica de comparacao MUST↔spec reusa parser ja vigente no 00c (em
`pipeline.sh` linhas que implementam o enforcement de e457dfa) —
extracao para script dedicado e refactor pequeno.

**Rationale**: o enforcement ja existe e funciona (commit e457dfa
validado em CI). Extrair para script dedicado:
- Permite invocacao pelo feature-00c-orchestrator sem ler `pipeline.sh`
  inteiro
- Facilita testes isolados (1 script POSIX = 1 test_*.sh em
  `tests/run.sh`)
- Mantem a logica DRY entre os dois orquestradores (sat. FR-010A
  "implementacao paralela esta proibida")

**Alternatives considered**:

- **Copy-paste da logica de pipeline.sh para um novo script da feature**:
  rejeitada por divergencia garantida.
- **Importar `pipeline.sh` via `.` (source) e chamar funcao especifica**:
  considerada, mas pipeline.sh tem efeitos colaterais (escreve state) que
  nao queremos no pre-flight standalone.

---

## Decision 5: Cadeia de invocacao Resume ↔ Wakeup

**Decision**: A cadeia e:

```
[onda corrente termina]
   ↓
orquestrador-feature retorna intent: { schedule: true,
                                        delaySeconds: N,
                                        cmd: "/feature-00c-resume <short-name>" }
   ↓
slash command pai (/feature-00c ou /feature-00c-resume corrente)
invoca ScheduleWakeup(prompt=<intent.cmd>, delaySeconds=intent.delaySeconds)
   ↓
[wakeup dispara apos N segundos]
   ↓
/feature-00c-resume <short-name> roda:
  1. checa lock file (.lock); se ja blocked, aborta com diagnostico
  2. valida hash de state.json (FR-014)
  3. valida hash de briefing.sha256 + constitution.sha256 (FR-PRE-004)
  4. carrega state.json + delega ao agente-00c-feature-orchestrator
  ↓
orquestrador continua de proxima_instrucao
```

A premissa-chave: **sub-agentes nao podem invocar ScheduleWakeup com
prompt sobrevivente** (constraint do harness Claude Code). Por isso o
intent precisa subir ate o slash command pai, que ainda esta no contexto
"top-level" da sessao corrente.

Lock check antes de hash check: se outro processo ja tem o lock, nao faz
sentido validar hash (estado pode estar sendo escrito). Hash check entre
lock acquired e file load: garante integridade do que sera carregado.

**Rationale**: replica exatamente o padrao ja em producao no agente-00c
(`agente-00c-resume.md` + `agente-00c-orchestrator.md` §5.a). Lock +
hash check em ordem definida elimina race condition entre wakeup e
invocacao manual concorrente do operador.

**Alternatives considered**:

- **Resume valida hash ANTES do lock**: rejeitada porque permite ler
  state.json no meio de uma escrita concorrente (race).
- **Wakeup invoca orquestrador diretamente, pulando o slash command
  resume**: rejeitada porque viola constraint do harness (sub-agentes
  nao sobrevivem schedule).
- **Polling do lock em vez de fail-fast**: rejeitada por consumir tool
  calls sem progresso real. Se locked, encerra com diagnostico claro
  (operador re-invoca depois).

**Implicacao de spec**: CHK035 (sequencia exata resume vs wakeup)
resolvido aqui — nao precisa de update na spec, mas o detalhe vai no
contract `cli-invocation.md`.

---

## Decision 6: Filtro de secrets em backups por onda

**Decision**: O filtro de secrets (`secrets-filter.sh`) e aplicado em
DOIS pontos durante a gravacao de cada backup:

1. **Pre-processamento**: o conteudo de `state.json` e passado por
   `secrets-filter.sh --redact` ANTES de gerar o snapshot. O resultado
   filtrado e o que vai para `backups/wave-NNN.json` (com o campo
   `state_sha256_self` calculado sobre o conteudo filtrado).
2. **State operacional inalterado**: o `state.json` em si NAO e filtrado
   — o orquestrador precisa do conteudo original para decisoes futuras.
   Apenas o snapshot e redacted.

Padroes detectados pelo filtro (herdados de FR-030 do agente-00c):
- Tokens de >=20 chars `[a-zA-Z0-9_-]+`
- AWS keys `AKIA[A-Z0-9]{16,}`
- Bearer tokens em URLs `Bearer\s+[a-zA-Z0-9._-]+`
- Basic auth em URLs `https?://[^:]+:[^@]+@`
- Strings que aparecem em chaves do `.env` lido durante a execucao

Match positivo = substituir por `[REDACTED]`.

**Rationale**: dois caminhos divergentes para state vs backup mantem
auditoria viva (backups redacted = seguro para incluir em bug reports,
copiar para diff) sem perder operabilidade (state.json continua
funcional). Hash auto-registrado no backup (`state_sha256_self`)
permite detectar corrupcao retroativa mesmo apos filtragem.

**Alternatives considered**:

- **Filtrar tambem o state.json**: rejeitada porque quebraria a logica
  do orquestrador (referencias a tokens podem ser legitimas dentro do
  estado para tarefas que usam APIs autorizadas via whitelist).
- **Sem filtro em backups**: rejeitada conforme decisao do `/clarify`
  (CHK028 = privacy gap real).
- **Filtro opt-in via flag --redact-backups**: rejeitada por inverter o
  default seguro. Privacidade por default; opt-out se necessario via
  flag futura `--no-redact-backups` (NAO incluida no MVP).

**Implicacao de spec**: ja refletida em FR-029 §"Escopo do filtro de
secrets" — Decision 6 detalha implementacao.

---

## Decision 7: Coexistencia operacional com agente-00c

**Decision**: O check de coexistencia (FR-026) e implementado no
slash command `feature-00c.md` ANTES de delegar ao agente custom:

```sh
# pseudocodigo
state_00c="<projeto-alvo>/.claude/agente-00c-state/state.json"
if [ -f "$state_00c" ]; then
    status=$(jq -r '.status' "$state_00c" 2>/dev/null || echo "unknown")
    case "$status" in
        em_andamento|aguardando_humano)
            echo "ERROR: agente-00c esta ativo (status: $status)..." >&2
            exit 1
            ;;
    esac
fi
```

Notar: `jq` aqui e dep opcional (`agente-00c-runtime` ja registra `jq`
como dep opcional sob constitution amendment 1.1.0). Fallback: parser
POSIX (`grep '"status"' | sed`) se jq nao disponivel.

**Rationale**: check no slash command (nao no agente) evita gastar
tool call do agente em caso de rejeicao. Falha rapida = melhor UX.

**Alternatives considered**:

- **Check dentro do agente-00c-feature-orchestrator**: rejeitada por
  desperdicar tool calls em caso de rejeicao.
- **Lock cross-orchestrator**: considerada (um unico lock global em
  `.claude/orchestrator.lock`), rejeitada porque impediria coexistencia
  de features distintas via /feature-00c em paralelo. FR-028 (lock por
  short-name) ja resolve isso.

---

## Resumo: NEEDS CLARIFICATION resolvidos

| Item original | Resolvido por |
|---------------|---------------|
| FR-009 (asker/answerer composicao vs duplicacao) | Decision 2 |
| FR-015 thresholds (sem valor) | Spec §FR-015A + reuso de research.md Decision 2 do agente-00c |
| FR-010A (pre-flight implementacao) | Decision 4 |
| FR-018 (conteudo das 6 secoes) | Contracts/report-format.md (a ser gerado) |
| CHK035 (sequencia resume vs wakeup) | Decision 5 |
| Reuso de runtime | Decision 1 |
| Layout de arquivos | Decision 3 |
| Filtro de secrets em backups | Decision 6 |
| Coexistencia com 00c | Decision 7 |

**Phase 0 status**: COMPLETO. Zero `NEEDS CLARIFICATION` pendentes. Phase 1
(design) pode iniciar.
