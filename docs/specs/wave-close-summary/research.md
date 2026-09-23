# Research: Resumo Deterministico de Fechamento de Onda

Documento do Phase 0 do `/plan`. Nenhum `NEEDS CLARIFICATION` estrutural
(linguagem/runtime, stack, arquitetura, persistencia, ambiente-alvo, tier) foi
aberto: a feature herda integralmente a stack do runtime `agente-00c-runtime`
(POSIX sh + `jq` + backend `state.json`/`state.db`) e as 5 Clarifications da
spec ja fixaram fonte de metricas (Q1/Q2), filtro (Q3), escopo de texto (Q4) e
local do codigo (Q5). As decisoes abaixo sao de nivel operacional.

Convencao de marcacao (Principio VI): **[EXISTENTE]** = verificado no repo em
2026-09-22 (arquivo citado); **[PROPOSTA]** = design novo desta feature, a
validar na implementacao.

## Decision 1: Fonte unica = documento de estado materializado via `_state-read.sh`

**Decision**: o helper le TODOS os campos de um unico documento de estado,
materializado por `state_read_materialize` de `_state-read.sh` [EXISTENTE —
`plugins/cstk/skills/agente-00c-runtime/scripts/_state-read.sh`], consultado
com `jq`. Campos consumidos [EXISTENTE — observados no state.db desta propria
execucao via `state-rw.sh read`]:

- `.waves[]` → `id`, `started_at`, `finished_at`, `wallclock_seconds`,
  `tool_calls`, `termination_reason`, `executed_stages`, `otel_usage`
- `.decisions[].wave_id`
- `.human_blocks[].status` / `.human_blocks[].id` (`"aguardando"` = pendente —
  literal gravado por `bloqueios.sh`, linha ~294)
- `.tasks[].wave_id` / `.tasks[].outcome` (`pass|fail`)
- `.current_stage`, `.next_instruction`, `.execution.status`,
  `.execution.target_project_path`

**Rationale**: FR-006/FR-007 proibem instrumentacao nova; tudo ja e gravado por
`state-ondas.sh end` e `record-task`/`bloqueios.sh`. `_state-read.sh` e a
interface obrigatoria para leitores do runtime (a camada estatica de
`tests/test_state-parity-sweep.sh` reprova acesso direto ao arquivo de estado
fora da allowlist) e cobre os dois backends por construcao — o que tambem
satisfaz FR-014 (agente-00c e feature-00c usam o mesmo schema de estado).

**Alternatives considered**:
- Compor via `wave-usage-report.sh aggregate --json` + `model-routing-report.sh`
  + `bloqueios.sh count`: 3-4 processos e 3-4 materializacoes do mesmo estado
  por onda, sem ganho de informacao (nenhum dos campos exigidos pela spec vive
  so nesses agregadores). Rejeitado por custo e superficie de falha.
- Ler `state.json` direto com `jq`: quebra sob backend SQLite e reprova o
  parity-sweep. Rejeitado.

## Decision 2: Custo/consumo exclusivamente de `.waves[].otel_usage`

**Decision**: o indicador de custo (FR-007) le `total_tokens` e
`total_cost_usd` de `.waves[<alvo>].otel_usage` [EXISTENTE — coluna
`otel_usage` gravada por `state-ondas.sh end` (`_state-ondas-db.sh` ~l.283) a
partir de `otel-usage.sh`]. Nao consulta a `knowledge.db`.

**Rationale**: Clarification Q2 fixa OTel/`wave_model_usage` como unica fonte.
`wave_model_usage` e tabela DERIVADA da `knowledge.db`, ingerida a partir desse
mesmo `otel_usage` por `cstk recall --ingest`; ler a origem evita (a) acoplar o
runtime a `sqlite3` fora da camada de estado (confinamento de dep em
`cli/lib/recall.sh`), (b) depender do timing da ingestao (5.bis do pai roda
DEPOIS do resumo), (c) depender do binario `cstk` no PATH.

**Alternatives considered**: consultar `wave_model_usage` via `cstk recall` —
rejeitado pelos 3 motivos acima; nova medicao — proibida por FR-007.

## Decision 3: Regra "nao medido" por campo (FR-010, SC-002)

**Decision** [PROPOSTA]:

| Indicador | Medido quando | Senao |
|-----------|---------------|-------|
| Custo/tokens | `otel_usage` objeto nao-nulo E campo numerico nao-nulo | `nao medido` (inclui `otel_usage` ausente/null — OTel desligado ou porta presa) |
| Duracao | onda fechada E `wallclock_seconds` numerico | `nao medido` |
| Chamadas de ferramenta | `tool_calls > 0`; OU `tool_calls == 0` E `guard-hooks-status.sh tick-mode` = `hook` | `nao medido` (0 sem hook de contagem ativo e indistinguivel de "nao contado") |
| Tarefas | onda executou `execute-task` OU ha `.tasks[]` com `wave_id` da onda | `nao aplicavel` (nao e "nao medido": nao houve backlog na onda) |

Zero medido e impresso como `0`; ausencia e impressa com o literal `nao medido`
— textualmente distinto (US2 AS1/AS2). Em `--json`, ausencia = `null` +
`measured: false`, nunca `0` (paridade com `wave-usage-report.sh` null-vs-0).

**Rationale**: `tool_calls` nasce `0` em `state-ondas.sh start` e so cresce via
hook `posttooluse-tool-call-tick.sh` ou tick manual; o `guard-hooks-status.sh
tick-mode` [EXISTENTE] ja e o oraculo canonico de "o contador estava ativo".
Contagem positiva prova medicao (alguem tickou). Nao ha heuristica inventada.

**Alternatives considered**: imprimir `tool_calls` sempre — viola FR-010 no
caso "hook ausente" (sintoma documentado em `guard-hooks-status.sh`: "tool_calls
fica 0 em todas as ondas"). Tratar `0` sempre como "nao medido" — viola US2 AS2
quando o hook existe.

## Decision 4: Onda-alvo default = ultima entrada de `.waves[]`

**Decision** [PROPOSTA]: sem `--wave`, o alvo e o ultimo elemento de `.waves[]`
(o pai invoca APOS `reconcile-wave`, logo e a onda recem-fechada). Se essa onda
ainda estiver aberta (`termination_reason == null` — reconcile falhou), o resumo
sai assim mesmo, com motivo `onda ainda aberta` e duracao `nao medido`.
`.waves[]` vazio ou `--wave ID` inexistente = exit 3.

**Rationale**: cobre o edge case "primeira onda" sem presumir historico; nunca
agrega ondas anteriores.

## Decision 5: Zero texto livre de decisoes/bloqueios; `next_instruction` saneada

**Decision** [PROPOSTA]: de decisoes e bloqueios saem so contagens e `id`s
(FR-012/Q4). `next_instruction` (exigida por FR-009; nao e conteudo de decisao
nem bloqueio) passa, nesta ordem, por: remocao de caracteres de controle
(inclui ESC — previne injecao de sequencia de terminal), colapso de quebras de
linha em espaco, `secrets-filter.sh scrub` [EXISTENTE — le stdin, escreve
stdout] e truncamento em 200 caracteres com sufixo `...`.

**Rationale**: defesa em profundidade — `next_instruction` e texto escrito pelo
orquestrador e pode citar valor sensivel por engano (edge case da spec). Reusar
o filtro existente satisfaz Q3. Se `secrets-filter.sh` falhar, o campo sai como
`nao disponivel (filtro indisponivel)` — nunca cru (fail-closed no campo, nao no
resumo).

## Decision 6: Contrato best-effort e integracao nos 4 commands pai

**Decision** [PROPOSTA]: exit != 0 imprime EXATAMENTE 1 linha em stderr
(`wave-summary: <motivo>`) e nada em stdout. Sucesso: stdout = bloco, stderr
vazio. O pai captura com `2>&1`, e em falha substitui o bloco por
`Resumo da onda indisponivel: <motivo>` — sem `set -e` propagando, sem retry.
Posicao: imediatamente APOS o `reconcile-wave` (feature-00c.md §5,
feature-00c-resume.md §4, agente-00c.md §5.pre, agente-00c-resume.md §6.bis
[EXISTENTE — secoes verificadas]); o bloco capturado e APRESENTADO na mensagem
final do pai (feature-00c: fim do §5/§6; agente-00c.md §6 "Apresentacao do
resultado"; agente-00c-resume.md §9 "Apresentar resultado ao operador";
feature-00c-resume.md fim do §4.ter/§5).

**Rationale**: o subagente orquestrador nao escreve na conversa (so o pai);
rodar apos reconcile garante onda fechada; o helper so le estado (sub-segundo,
nenhuma rede, nenhum lock), logo nao atrasa o `ScheduleWakeup` (FR-011/SC-003).

**Alternatives considered**: orquestrador emitir o resumo no proprio sumario —
nao chega a conversa. Prosa inline em cada command — vetado por Q5/FR-014.

## Decision 7: Dependencia `jq` (Constitution II, amendment 1.3.0 item c)

**Decision**: o helper vive na camada de estado transacional e usa `jq` como os
demais leitores do runtime (`wave-usage-report.sh`, `budget.sh`) [EXISTENTE].
Como e consumidor DERIVADO best-effort (item (c) do carve-out 1.3.0), ausencia
de `jq`/`sqlite3` produz exit 1 com 1 linha de diagnostico e o PAI degrada para
o aviso de indisponibilidade — a obrigatoriedade nao se propaga para a
continuidade da execucao.

## Decision 8: Formato de saida

**Decision** [PROPOSTA]: default Markdown compacto (<= 14 linhas, rotulos em
pt-BR — mensagens podem ser em portugues); `--json` com chaves em ingles
(regra global de sintaxe) para testes e consumo por maquina. Saida
deterministica: mesma entrada ⇒ bytes identicos (sem timestamp de "agora").

## Decision 9: Mitigacoes do gate `owasp-security` sobre o plan (2026-09-22)

Achados (0 critical, 0 high) incorporados ao design [PROPOSTA]:

- **SEC-M1 (MEDIUM — LLM01/ASI09, injecao indireta no contexto do pai)**: o
  bloco reentra no contexto do LLM do command pai; `next_instruction` e texto
  escrito por outro LLM e pode carregar diretiva ("ignore...", "rode X").
  Mitigacao: (a) o helper imprime `next_instruction` dentro de inline code, com
  crases removidas do valor; (b) a prosa dos 4 commands declara o bloco como
  DADO para exibicao — o pai NUNCA executa, agenda ou decide com base no
  conteudo do resumo (schedule segue derivado do `Schedule intent`/
  `.execution.status`, como hoje).
- **SEC-L1 (LOW — LLM05)**: `executed_stages`, `current_stage`,
  `execution_status` e `id`s de bloqueio sao validados contra
  `^[A-Za-z0-9._-]{1,64}$`; valor fora do padrao (ex.: prosa legada em
  `waves.stages`, corrigida so a partir da v5.34.1) sai como
  `(valor invalido omitido)`, nunca cru.
- **SEC-L2 (LOW — LLM02)**: `secrets-filter.sh scrub` e best-effort (o proprio
  cabecalho avisa "passou pelo scrub != nao contem segredo"); risco residual
  aceito e limitado por: so 1 campo de texto livre, truncamento em 200 chars,
  zero texto de decisoes/bloqueios (FR-012).
- **SEC-L3 (LOW — A10/ASI08)**: stderr de ferramentas internas (`jq`,
  `state-rw.sh`, `tick-mode`, `scrub`) vai para `/dev/null`; a unica linha de
  stderr em falha e a mensagem propria do helper, sem eco de conteudo do estado
  — o pai concatena essa linha na conversa.
- **SEC-I1 (INFO)**: o tmp de materializacao (0600, fora do state-dir) e
  removido por `trap state_read_cleanup EXIT INT TERM` (padrao de
  `_state-read.sh`).
- **SEC-I2 (INFO)**: `.execution.target_project_path` so e repassado como
  argumento citado a `guard-hooks-status.sh tick-mode` — nunca `eval`.
