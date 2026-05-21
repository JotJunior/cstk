# Validation Run: 2026-05-06 — End-to-end Shell Simulation

**Tipo**: shell-simulation
**Versao do toolkit**: pre-3.4.0 (codigo na branch main, sem release tagueada)
**Operador**: jot (sessao Claude Code Opus 4.7)
**Sessao Claude Code**: agente Claude executou o shell-sim como parte da FASE 9
implementation (NAO e execucao real do `/agente-00c`)

## Setup

- Cada cenario cria seu proprio `state-dir` em `/tmp/agente-00c-shellsim.XXXXXX/scenario-N/state/`
- Cada cenario inicializa um `git init` em `proj/` para validar `state-ondas.sh git-commit`
- Whitelist usada no cenario 7: 2 entries (api.github.com toolkit + github.com toolkit)
- Stack-sugerida: omitida (todos os cenarios usam descricao curta + state default)

## Cenarios executados

Script: `scripts/quickstart-shell-sim.sh` (10 cenarios)

| Scenario | Resultado | Observacoes |
|----------|-----------|-------------|
| 1 — Happy path completo | **PASS** | state init + onda + decisao + `report.sh generate` + `validate` retornam 0 |
| 2 — Pause por bloqueio humano | **PASS** | `score=0` em decisao -> `bloqueios.sh register` -> `status=aguardando_humano` |
| 3 — Aborto por loop em etapa | **PASS** | 6º `cycles.sh tick` retorna exit 3 com mensagem `loop_em_etapa` |
| 4 — Retomada apos /clear | **PASS** | `sha256-verify` OK pos-init; corrupcao manual detectada com exit 1 |
| 5 — Aborto manual via /agente-00c-abort | **PASS** | end-of-onda + status `abortada` + schema continua valido |
| 6 — Bug em skill global vira issue | **PASS** | sugestao impeditiva + `issue.sh create --dry-run` produz template completo |
| 7 — URL fora da whitelist e bloqueada | **PASS** | `bash-guard.sh check-whitelist`: evil.example.com=exit1, toolkit=exit0 |
| 8 — Tentativa de spawnar tataraneto | **PASS** | 3º `enter` no `spawn-tracker.sh` retorna exit 3 SEM mutar estado |
| 9 — Movimento circular detectado | **PASS** | mesmo `problema_hash` 3x no buffer 6 -> exit 3 (movimento_circular) |
| 10 — Estado corrompido na retomada | **PASS** | schema_version invalido + profundidade > 3 ambos rejeitados por `state-validate.sh` |

**Resultado total: 10/10 PASS** (zero falhas, zero skips).

## Metricas coletadas

| Metrica | Valor | SC referenciado |
|---------|-------|-----------------|
| Tempo total de execucao | ~5 segundos (10 cenarios + git init em cada) | - |
| Cobertura de scripts da skill `agente-00c-runtime` | 11/14 scripts exercitados (todos exceto `state-lock.sh`, `path-guard.sh`, `sanitize.sh` cuja cobertura ja vem da suite `tests/`) | - |
| Falsos positivos | 0 | - |

## Success Criteria avaliados (parcial)

Apenas SCs que sao validaveis em shell-level (sem comportamento de LLM):

| SC | Atendido? | Evidencia |
|----|-----------|-----------|
| SC-001 — Relatorio com 6 secoes obrigatorias | **yes** | Cenario 1: `report.sh validate` exit 0 |
| SC-002 — 100% das execucoes geram relatorio (shell-level) | **yes** | Todos os 10 cenarios geram artefatos auditaveis sem erro |
| SC-007 — Validacao de schema na retomada bloqueia estado invalido | **yes** | Cenario 10: schema_version + profundidade > 3 ambos detectados |
| SC-008 — Whitelist enforcement bloqueia URLs nao listadas | **yes** | Cenario 7: evil.example.com bloqueado |

SCs que **NAO sao validaveis** em shell-level (exigem execucao real):

- **SC-003** — heuristica clarify decide >= 60% sem humano (depende do LLM clarify-answerer)
- **SC-004** — drift detection acerta 100% em adversarial (testado unitariamente, nao em runtime real)
- **SC-005** — relatorio gerado em < 60s (timing observado: < 1s, MAS sem carga real de state)
- **SC-006** — leitor reproduz mentalmente decisoes via relatorio (criterio binario humano)
- **SC-009** — issue aberta no toolkit em < 30s pos-deteccao (depende de gh + rede)
- **SC-010** — pos-3 execucoes reais, suite de skills evolui mensuravelmente (longitudinal)

## Observacoes qualitativas

### O que funcionou bem

- **Composicao de primitivas** — os 14 scripts da skill se compoem sem
  necessidade de glue code adicional alem do que esta no script de
  shell-sim. Isso valida o design "primitivas pequenas + orquestrador
  decide quando chamar cada uma".

- **Backups automaticos em state-history/** — cada `set/write/register`
  produz um backup; nenhum cenario perdeu state intermediario, mesmo
  com mutacoes em sequencia.

- **Idempotencia explicita** — ondas `start`/`end`, `bloqueios.sh
  respond` quando ja respondido, `spawn-tracker.sh leave` em min 1,
  todos comportam-se previsivelmente em chamadas duplicadas.

### O que **NAO** este shell-sim valida

- **Heuristica de score 0..3 do clarify-answerer** — depende do LLM
  ler briefing/constitution/stack e atribuir score real. Aqui usamos
  score=0 hardcoded para forçar o cenario 2.

- **Qualidade de perguntas do clarify-asker** — depende da skill
  clarify do toolkit + comportamento do LLM. Shell-sim apenas valida
  que o orquestrador sabe receber e processar a saida JSON.

- **Detecao de drift baseada em conteudo de decisoes** — a primitiva
  `drift.sh check` e validada (5 ondas sem aspecto = exit 3), mas em
  runtime real depende de o orquestrador realmente nao tocar aspectos
  vs registrar decisoes que mencionam aspectos.

- **Tempo wallclock realista** — todos os cenarios completam em < 1s
  cada. Em runtime real, uma onda tipica leva 30-90 minutos (tabela
  de calibracao em `agente-00c-orchestrator.md`).

### Surpresas e licoes

- **`spawn-tracker.sh enter` snapshot before/after** mostrou-se util:
  cenario 8 valida que o estado NAO muta quando spawn e negado.
  Sem essa garantia, defesa em profundidade seria parcial.

- **`circular.sh` com normalizacao + hash** detecta padrao mesmo com
  variacoes triviais (case, pontuacao). Cenario 9 usa "Test failing
  on null" 3x identico, mas a normalizacao garantiria deteccao mesmo
  com pequenas diferencas — testado unitariamente.

- **`issue.sh create --dry-run`** e provavelmente o subcomando mais
  util para desenvolvimento, evitando issues de teste em produçao no
  toolkit. Mantenha durante toda a vida do projeto.

## Anexos

- Script: `scripts/quickstart-shell-sim.sh`
- Tmpdir (temp, removido apos exec): `/tmp/agente-00c-shellsim.XXXXXX/`
- Para reproduzir: `scripts/quickstart-shell-sim.sh` (sem args = todos os 10)
- Para debug: `scripts/quickstart-shell-sim.sh --keep-tmp --scenario 8`

## Proximos validation runs esperados

- **end-to-end-real** com primeiro projeto-alvo (FASE 9.3) — validara
  SC-003, SC-005, SC-006, SC-009 que ficam fora deste shell-sim.
- **end-to-end-real** com segundo e terceiro projetos — gera dataset
  para SC-010 (longitudinal).
