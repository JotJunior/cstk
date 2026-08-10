# Research: Captura de Uso do Plano via Statusline

Nenhum `NEEDS CLARIFICATION` remanescente na spec — as 5 respostas de
`clarify` (Q1/Q2/Q4 autonomas + Q3/Q5 via bloqueio humano) ja estao
integradas em `spec.md` §Clarifications e nos FRs correspondentes
(FR-008, FR-009, FR-010, FR-014). Este documento resolve as decisoes
tecnicas de **como** implementar, ainda nao cobertas pelos FRs (que
descrevem o **o que**).

## Decision 1 — Ponto de captura: novo script de entrada, fora do
sistema de hooks `PreToolUse`/`PostToolUse`

**Decision**: introduzir um script novo,
`plugins/cstk/skills/agente-00c-runtime/hooks/statusline-plan-usage.sh`,
dedicado a processar o payload da statusline. Vive no mesmo diretorio dos
demais hooks do runtime (`hooks/`) por convencao de local (scripts de
instrumentacao do `agente-00c-runtime`), mas **nao e um hook
`PreToolUse`/`PostToolUse`** — e configurado via o campo `statusLine.command`
do `settings.json` do harness, um mecanismo de configuracao distinto do
array `.hooks.PostToolUse[]` que `cli/lib/hooks.sh` ja gerencia
(evidencia: `grep -n statusLine` no repo inteiro retorna zero ocorrencias
antes desta feature — nao ha precedente de codigo a reusar, so o
GOTCHA documentado na memoria `reference_statusline_usage_payload.md`).

**Rationale**: `posttooluse-loose-usage.sh` (feature `loose-usage-capture`)
e o molde mais proximo — mesma disciplina (fail-open, exit sempre `0`,
throttle, sem bloquear a sessao) — mas o gatilho e diferente por natureza:
`PostToolUse` dispara apos uma tool call; `statusLine.command` dispara a
cada RENDER de UI (~2x/2min numa sessao minima, por observacao empirica),
e o payload chega no **stdin** do processo, nao em variavel de ambiente ou
argv. Reusar o array `hooks.PostToolUse` seria factualmente incorreto —
`statusLine` e uma chave irma de `hooks` no `settings.json`, nao um membro
dela.

**Alternatives considered**:
- Reusar `posttooluse-loose-usage.sh` como esta, adicionando deteccao de
  `rate_limits` no payload de `PostToolUse` — REJEITADA: o payload de
  `PostToolUse` (tool_name, tool_input, tool_response) nao contem
  `rate_limits`; o campo so existe no payload da statusline (memoria,
  linha 31). Fontes distintas, sem overlap.
- Poll ativo via `GET /api/oauth/usage` — REJEITADA pela spec (FR-006 MUST
  NOT depender de OAuth) e pelo Principio VI (fonte teria que ser
  simulada/suposta sem credencial disponivel neste ambiente de dev).

## Decision 2 — Pass-through obrigatorio do stdout da statusline

**Decision**: o script `statusline-plan-usage.sh` MUST imprimir em stdout
exatamente o mesmo texto que o comando de statusline anterior do operador
produziria, encaminhando a chamada para um comando "interno" configuravel
via variavel de ambiente `CSTK_STATUSLINE_INNER_COMMAND` (se definida) e
repassando o stdout dele **verbatim**; se a variavel nao estiver definida,
o script MUST imprimir apenas um fallback minimo de 1 linha (nao
inventado — construido so a partir de campos ja capturados desta mesma
sessao: `model.display_name` e, quando disponivel, o `used_percentage` de
`five_hour`) em vez de string vazia, para nao apagar a UI de quem nunca
configurou uma statusline customizada antes.

**Rationale**: nao e um requisito funcional explicito da spec (a spec so
cobre a captura, FR-001 a FR-014), mas e uma condicao de viabilidade de
instalacao: `statusLine.command` e uma chave **unica** no `settings.json`
— se este script simplesmente NAO reemitir a UI, qualquer operador que ja
tenha uma statusline customizada perde a visualizacao ao instalar esta
feature. Documentado aqui como decisao de design necessaria para um
rollout seguro, nao como fabricacao de requisito.

**Marcado `[PROPOSTA — a validar na implementacao]`**: o mecanismo exato
de wiring/instalacao (extensao de `cstk hooks install` para tambem
gerenciar `.statusLine.command`, ou um subcomando novo `cstk statusline
install`) fica para a fase `create-tasks` decompor; este research.md fixa
apenas a garantia comportamental (pass-through) que qualquer mecanismo de
instalacao escolhido precisa preservar.

## Decision 3 — `jq` como dependencia opcional confinada (reuso de carve-out
ja vigente, nao um novo)

**Decision**: `statusline-plan-usage.sh` usa `jq` para parsear o payload
JSON do stdin, com fallback fail-open: `jq` ausente ⇒ script encaminha o
pass-through (Decision 2) sem persistir nenhuma captura, exit `0`, nenhuma
mensagem em stdout/stderr que contamine a UI.

**Confinamento (condicao b do amendment 1.1.0)**: `jq` ja e dependencia
opcional confinada, mas **espalhada por precedente ja existente** (nao
introduzido por esta feature) em `cli/lib/recall.sh` (`recall_have_jq`,
linha 367) e `cli/lib/usage.sh` (12 ocorrencias, todas atras de
`recall_have_jq`). O carve-out original (`cstk-cli`, amendment 1.1.0) exige
"um unico arquivo identificavel" por invocacao do carve-out, e cada arquivo
novo desta feature (`statusline-plan-usage.sh`, `cli/lib/plan-usage.sh`)
continua essa mesma disciplina — cada um encapsula sua propria checagem
`command -v jq` e degrada individualmente. Precedente literal:
`cli/lib/usage.sh` (feature `loose-usage-capture`) fez exatamente esse
reuso sem reabrir o debate do carve-out.

**Alternatives considered**: parsear o JSON com `sed`/`awk` (POSIX puro,
sem `jq`) — REJEITADA: o payload tem aninhamento arbitrario
(`rate_limits.five_hour.used_percentage`) e o Principio II ja aceita o
carve-out de `jq` para exatamente este tipo de caso; reimplementar um
parser JSON ad-hoc em `awk` seria a "complexidade nao justificada" que o
Constitution Check re-check deve vetar.

## Decision 4 — Throttle: comparacao contra o ultimo registro, sem cache
auxiliar

**Decision**: o throttle de FR-010 (tolerancia de 2 casas decimais,
comparado contra o ULTIMO registro persistido do escopo — dec-008/dec-009)
e implementado com uma leitura SQL simples (`SELECT used_percentage,
resets_at FROM plan_usage WHERE scope = ? ORDER BY id DESC LIMIT 1`) antes
de cada INSERT, delegada a `cli/lib/recall.sh` (ver Decision 6) — nao
introduz nenhum arquivo de cache/estado auxiliar novo (paridade com o
padrao de UPSERT natural-key do `loose_usage`, mas aqui e comparacao
pre-INSERT porque `plan_usage` e append-only, nao upsert — ver
data-model.md).

**Rationale**: o volume de writes e baixissimo (~2 renders/2min por
sessao, e cada render so gera captura nova se `rate_limits` estiver
presente E o percentual mudar alem de 2 casas decimais) — uma query extra
por candidate-write nao e hot path (contraste com o throttle O(1) de
`posttooluse-tool-call-tick.sh`, que dispara a CADA tool call).

**Alternatives considered**: throttle em arquivo sidecar local (mesmo
padrao do `loose_usage`, `meta.tsv` com `updated_at`) — REJEITADA: o
`loose_usage` precisa de sidecar porque a fonte (`otel-usage.sh`) e um
scrape HTTP caro que precisa ser evitado no hot path do hook; aqui o dado
ja chega de graca no stdin a cada render, entao o unico custo real e o
INSERT condicional, e uma query SQL de leitura e mais simples/auditavel
que introduzir uma segunda camada de arquivo.

## Decision 5 — Nome da coluna de sessao: `session_id`, nao `session`

**Decision**: a tabela `plan_usage` usa a coluna `session_id` (nao
`session`, como em `executions`/`waves` — `cli/lib/recall.sh` linhas
512/533), conforme a resolucao literal do bloqueio `block-001`
(dec-013, respondida pelo operador).

**Rationale registrada explicitamente** (a spec/dec-013 nomeou os 3 campos
literalmente: `project`, `project_path`, `session_id`): o valor de origem
para esta coluna e o campo `session_id` do TOPO do proprio payload da
statusline (memoria, linha 19: `"session_id": "..."`) — copiado
verbatim do payload, sem sintese. Chamar a coluna de `session_id` (em vez
de normalizar para `session`, convencao de `executions`/`waves`) mantem o
nome auto-descritivo do campo-fonte e evita ambiguidade de mapeamento na
camada de ingestao (`statusline-plan-usage.sh` copia
`.session_id -> session_id` 1:1, sem renomear).

**Divergencia de convencao reconhecida, nao ignorada**: `executions`/
`waves` usam `session` porque e um identificador SINTETICO derivado
internamente pelo runtime `agente-00c`/`feature-00c` (nao um campo
copiado de um payload externo). `plan_usage` e o primeiro caso de tabela
que copia `session_id` diretamente de uma fonte externa — a divergencia de
nome e intencional e documentada aqui para nao ser confundida com
inconsistencia acidental numa revisao futura.

## Decision 6 — `sqlite3` permanece confinado a `cli/lib/recall.sh`

**Decision**: nem `statusline-plan-usage.sh` nem `cli/lib/plan-usage.sh`
invocam `sqlite3` diretamente. `statusline-plan-usage.sh` (POSIX sh, sem
acesso a helpers do CLI porque roda fora do processo `cstk`) grava a
captura via uma chamada de subprocesso ao proprio `cstk plan-usage
ingest --stdin` (novo subcomando interno, nao documentado como superficie
publica em `contracts/`, usado so pelo hook), que por sua vez delega a
`recall.sh` — mesma cadeia de confinamento que `posttooluse-loose-usage.sh`
usa indiretamente (sidecar TSV -> ingest-on-read do `cstk usage`), adaptada
porque aqui nao ha sidecar intermediario (Decision 4).

**Rationale**: preserva o invariante grep-avel ja documentado no plan.md
arquivado de `loose-usage-capture` (`grep -nE
'(^|[^-[:alnum:]_])sqlite3[[:space:]]+(-cmd[[:space:]]|--[[:space:]])'
cli/lib/*.sh` deve continuar retornando so `cli/lib/recall.sh`) —
condicao (b) do carve-out de dependencia obrigatoria da camada
transacional nao se aplica aqui (esta NAO e a camada `state.db` dos
orquestradores), entao `sqlite3` aqui segue como dependencia OPCIONAL
(fallback: sem `sqlite3`, a captura falha silenciosamente e o hook segue
fazendo so o pass-through) confinada a um unico arquivo, disciplina
identica ao `jq`.

## Decision 7 — `RECALL_SCHEMA_VERSION`: 13 -> 14, tabela nova aditiva

**Decision**: bump de `RECALL_SCHEMA_VERSION` (valor real medido nesta
onda: `13`, `cli/lib/recall.sh` linha 136) para `14`, adicionando
`CREATE TABLE IF NOT EXISTS plan_usage (...)` ao corpo de
`recall_schema_ddl` — sem `ALTER TABLE`, sem `DROP`, mesmo precedente
literal usado por `loose_usage` na migracao v12->v13.

**Rationale**: tabela nova nao exige migracao de coluna aditiva (ao
contrario do padrao `ALTER TABLE ... ADD COLUMN` usado quando uma tabela
EXISTENTE ganha campo novo) — `CREATE TABLE IF NOT EXISTS` cobre tanto
bases que ja tem v13 (ganham a tabela vazia na proxima escrita) quanto
bases anteriores (que passam pela cadeia de migracao ja existente sem
interferencia).

## Decision 8 — Testabilidade sem sessao interativa (FR-012)

**Decision**: a logica de parsing/throttle/persistencia de
`statusline-plan-usage.sh` e fatorada numa funcao POSIX isolavel
(`_splu_process_payload`), testada alimentando um payload fixture via
`printf '%s' "$FIXTURE" | statusline-plan-usage.sh` no harness de testes —
nunca dependendo de `claude --settings ./settings.json` real (GOTCHA da
memoria: "Statusline NAO dispara em `claude -p`").

**Rationale**: mesma tecnica ja usada por `test_posttooluse-loose-usage.sh`
(alimentar JSON fixture via stdin em vez de invocar o harness real) —
precedente direto no proprio repo, convencao de testes de hook ja
estabelecida.
