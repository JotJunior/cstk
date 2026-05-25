# Security Checklist: Feature-00C — Orquestrador Autonomo de Feature Individual

**Purpose**: Validar qualidade dos requisitos de seguranca da spec
`feature-00c`. Foco em: protecao de secrets (incluindo a extensao
recem-decidida a backups por onda), integridade/anti-tampering, blast
radius confinado, prompt injection / goal alignment, race conditions,
e safety da coexistencia com agente-00c.

**Created**: 2026-05-20
**Reviewed**: 2026-05-20 (auditoria item-a-item contra spec/plan/data-model/contracts)
**Feature**: [spec.md](../spec.md) | [plan.md](../plan.md) | [data-model.md](../data-model.md) | [research.md](../research.md)
**Numeracao**: arquivo novo, CHK001..CHKN local ao dominio security.

## Input Validation

- [ ] CHK001 - Sao os requisitos de limite de tamanho da `descricao_curta` (<=500 chars) definidos com comportamento explicito em overflow (truncar+warning, ou rejeitar)? [Spec §FR-029 — limite e sanitizacao especificados, mas overflow behavior (truncar vs rejeitar) nao explicito; Contract §cli-invocation §feature-00c menciona "trunca se >500 chars + warning" — implicito]
- [x] CHK002 - Sao os requisitos de sanitizacao contra injecao em Bash/git/issue definidos com regras especificas (escape de aspas, remocao de control chars, rejection de shell metachars)? [Spec §FR-029 herda integralmente FR-025 do 00c com regras enumeradas]
- [x] CHK003 - A ordem de operacoes em validacao do `projeto_alvo_path` (resolve simlinks ANTES de validar zonas proibidas) e explicitamente requisitada? [Spec §FR-029 herda FR-024 do 00c, ordem "ANTES" explicita]
- [x] CHK004 - Sao os criterios de "zona proibida" enumerados objetivamente (`/`, `/etc`, `/usr`, `~/.claude`, `~/.ssh`, `~/.config`)? [Spec §FR-029 herda FR-024 do 00c com lista]
- [x] CHK005 - Sao os requisitos de validacao de whitelist de URLs definidos para rejeitar padroes excessivamente amplos (`**`, `*://*`, `https?://[*]`)? [Spec §FR-029 herda FR-031 do 00c com lista de padroes]

## Secrets Protection

- [x] CHK006 - O filtro de secrets aplica a TODOS os outputs que podem ser exfiltrados (report.md, suggestions.md, issue body, backups por onda)? [Spec §FR-029 §"Escopo do filtro de secrets" + Plan §Decision 6 — extensao a backups explicita]
- [x] CHK007 - A excecao de `state.json` operacional NAO ser filtrado e uma decisao CONSCIENTE documentada (nao bypass acidental)? [Plan §Decision 6 §"State operacional inalterado" + Spec §FR-029]
- [x] CHK008 - Sao os padroes de deteccao de secrets enumerados objetivamente (tokens >=20 chars, AWS keys, Bearer tokens, basic auth em URLs, strings do .env)? [Spec §FR-029 herda FR-030 do 00c com regex enumerados]
- [x] CHK009 - Strings extraidas do `.env` durante execucao sao adicionadas DINAMICAMENTE ao filtro (nao apenas regex estaticos)? [Spec §FR-029 herda FR-030 do 00c — "strings que aparecem em chave do .env lido durante a execucao"]
- [x] CHK010 - O comportamento do filtro em casos ambiguos (string que parece token mas e identificador legitimo) e definido — fail-safe (redact mais) vs fail-open (preservar)? [Spec §FR-029 §"Comportamento em casos ambiguos" adicionado — fail-safe default: redact em duvida; whitelist contextual out-of-scope no MVP]
- [x] CHK011 - Hash `state_sha256_self` em backups e calculado sobre conteudo FILTRADO (nao sobre state operacional)? [Plan §Decision 6 explicito + Data-model §Backup]

## Blast Radius

- [x] CHK012 - Sao os requisitos de restricao de escrita em disco ao projeto-alvo definidos com verificacao de path traversal (`../`, links absolutos)? [Spec §FR-030 + FR-029 (realpath resolve traversal antes da restricao)]
- [x] CHK013 - Sao os requisitos de bloqueio de `sudo` definidos para detectar tanto `sudo X` quanto ` sudo ` em posicao qualquer? [Spec §FR-031 + §FR-029 herda FR-028 do 00c com regra explicita]
- [x] CHK014 - Sao os requisitos de bloqueio de package managers de host (npm/pip/go install/cargo/gem/brew install) com precedencia de `docker exec`/`docker run` definidos? [Spec §FR-031 + §FR-029 herda FR-028 do 00c com lista de gerenciadores]
- [ ] CHK015 - A lista de comandos proibidos (`git push`, deploy externo) e explicita ou exemplar — qual a regra para extensao? [Ambiguity, Spec §FR-031 — "deploy externo" e generico]
- [x] CHK016 - A excecao do `gh issue create` (unico canal externo permitido) e enumerada com restricoes (apenas para impeditivos, com filtro de secrets aplicado antes)? [Spec §FR-035 adicionado com 3 restricoes cumulativas: trigger=impeditiva, conteudo filtrado pre-POST, repo fixo `JotJunior/claude-ai-tips`]
- [x] CHK017 - O limite de profundidade de subagentes (3 niveis, tataraneto = invariante violada) tem falha explicita declarada? [Spec §FR-021 + §Edge Cases "Tentativa de spawnar tataraneto: falha explicita"]

## Integrity & Anti-Tampering

- [x] CHK018 - Hash SHA-256 do `state.json` entre ondas com bloqueio em divergencia (e mensagem de diagnostico "tampering") esta especificado? [Spec §FR-014 — "estado modificado externamente entre ondas"]
- [x] CHK019 - Hashes de `briefing.md` + `constitution.md` registrados no `state.json` + validados em retomada com bloqueio em divergencia? [Spec §FR-PRE-004]
- [x] CHK020 - Comportamento em MAJOR vs MINOR/PATCH bump da constitution claramente diferenciado (MAJOR=compulsorio, MINOR=aviso+pergunta opcional)? [Spec §FR-PRE-004 explicito]
- [x] CHK021 - Hash auto-registrado em cada backup (`state_sha256_self`) permite detectar corrupcao retroativa sem precisar de fonte externa de verdade? [Spec §FR-034 + Data-model §Backup]
- [x] CHK022 - A validacao de schema do state (`schema_version` SemVer) bloqueia em MAJOR mismatch e diferencia de MINOR/PATCH? [Spec §FR-013 + Data-model §Estado §"Schema versioning"]

## Prompt Injection & Goal Alignment

- [x] CHK023 - Sao os requisitos de tratamento de texto em artefatos lidos (briefing, spec, etc) como CONTEUDO (nao instrucao executavel) definidos com criterio? [Spec §FR-029 herda FR-026 do 00c]
- [x] CHK024 - Instrucoes para subagentes vem EXCLUSIVAMENTE do prompt construido pelo orquestrador — texto adversarial em artefato nao altera comportamento? [Spec §FR-029 herda FR-026 do 00c]
- [x] CHK025 - Drift detection via aspectos-chave tem threshold quantificado (5 ondas consecutivas) e acao definida (gatilho de aborto FR-022.d)? [Spec §FR-022.d explicito]
- [x] CHK026 - Aspectos-chave (3-7 keywords + dominio) sao extraidos UMA VEZ no inicio (nao re-derivados por onda)? Persistencia + imutabilidade declaradas? [Data-model §Estado campo `descricao_aspectos_chave` em `execucao` (top-level, persistido na invocacao); FR-029 herda FR-027 do 00c "extrair, no inicio da execucao"]
- [ ] CHK027 - Comportamento em "spec gerada vs briefing original divergem em aspectos-chave" (drift detectado mid-pipeline) tem fluxo definido? [Gap, Spec §FR-022.d cobre drift de decisoes mas nao spec-vs-briefing]

## Race Conditions & Concurrency

- [x] CHK028 - A ordem de operacoes em `/feature-00c-resume` (1.lock → 2.state hash → 3.briefing/constitution hash → 4.load → 5.delega) protege contra TOCTOU? [Plan §Decision 5 + Contract §cli-invocation.md §feature-00c-resume — ordem documentada com rationale]
- [x] CHK029 - Lock force-acquire em `/feature-00c-abort` nao introduz race com onda corrente (cleanup graceful da onda)? [Spec §FR-025 atualizado + Contract §cli-invocation §abort — SIGTERM ao PID + grace period 60s + force-acquire como fallback; SC-005 reajustado para max 120s pior caso]
- [x] CHK030 - Features paralelas no mesmo projeto operam em namespaces COMPLETAMENTE isolados (sem leitura cross-feature exceto suggestions.md append-only)? [Spec §FR-027 + FR-028 + Data-model §Invariants §4]
- [x] CHK031 - Tentativa de invocar `/feature-00c` para feature ja em execucao tem comportamento determinístico (rejeicao sem chance de race) via lock-file? [Spec §FR-028 + Plan §Decision 7 + Contract §cli-invocation pre-execucao step 7]
- [x] CHK032 - O check de coexistencia com agente-00c (FR-026) acontece ANTES de qualquer escrita em `feature-00c-state/`? [Plan §Decision 7 + Contract §cli-invocation §feature-00c §Validacoes pre-execucao step 5 (antes do step 7 que adquire lock)]

## External Communication

- [x] CHK033 - O `gh issue create` em `JotJunior/claude-ai-tips` e a UNICA excecao a "zero comunicacao externa" e isso esta explicitamente documentado como excecao consciente? [Spec §FR-035 adicionado — resolvido em conjunto com CHK016]
- [x] CHK034 - Corpo da issue criada via `gh` passa por filtro de secrets antes do POST (FR-021 do 00c herdado)? [Spec §FR-029 + Data-model §Issue §"Filtros de secrets aplicados em diagnostico + proposta antes da chamada ao gh"]
- [ ] CHK035 - Sao os requisitos de precedencia entre `.env` whitelist e `--whitelist` parameter definidos (uniao, override, ou merge com prioridade)? [Gap, Spec §FR-002, FR-031 — sem regra explicita]
- [x] CHK036 - Tentativa de comunicacao com URL fora da whitelist tem fluxo de bloqueio + pergunta humana ("adicionar?") definido com default seguro (NAO adicionar)? [Spec §Edge Cases + §FR-029 herda agente-00c spec §Edge Cases "Por default, NAO adiciona automaticamente"]

## Privacy & Logging

- [x] CHK037 - Sao os requisitos para logs de erro/warning do orquestrador (stderr, console) NAO vazarem conteudo de state ou secrets definidos? [Spec §FR-036 adicionado — filtro de secrets aplica a TODOS os outputs (stderr/stdout/logs), nao apenas a arquivos; aplicacao antes da emissao via wrapper de print/echo]
- [x] CHK038 - O `feature-00c-suggestions.md` compartilhado entre features no mesmo projeto e append-only (nunca apaga historico) E passa por filtro de secrets antes da gravacao? [Spec §Key Entities "append-only" + §FR-029 herda FR-030 do 00c que aplica filtro a `suggestions.md` explicitamente]

## Coexistence & Privilege Separation

- [x] CHK039 - Check de `agente-00c` ativo (FR-026) bloqueia ANTES do orquestrador-de-feature ser invocado (sem race window)? [Plan §Decision 7 explicito — "check no slash command (nao no agente)"]
- [x] CHK040 - `/feature-00c` NAO le nem modifica artefatos em `agente-00c-state/` (validavel por trace de I/O) e vice-versa? [Spec §FR-027 explicito]

## Notes

- Marcar items concluidos com `[x]`
- Items com `[Gap]` ou `[Ambiguity]` sao candidatos a `/clarify` se de alto impacto pre-`/create-tasks`
- Cobertura priorizada por risco: Secrets > Integrity > Blast Radius > Race > Prompt Injection > External Comm
- Rastreabilidade: 100% dos items referenciam secao especifica (Spec/Plan/Data-model/Contract) ou marcador (Gap/Ambiguity/Conflict/Assumption)

## Resultado da Auditoria (2026-05-20)

**Pass 1** (auditoria inicial): 33/40 (82.5%) atendidos, 7 pendentes.

**Pass 2** (apos clarify CHK010/CHK016+CHK033/CHK029/CHK037): **37/40 (92.5%) atendidos**, 3 pendentes.

**Mudancas integradas na spec**:
- **CHK010** → Spec §FR-029 §"Comportamento em casos ambiguos": fail-safe (redact em duvida)
- **CHK016 + CHK033** → Spec §FR-035 novo: `gh issue create` como UNICA excecao com 3 restricoes cumulativas
- **CHK029** → Spec §FR-025 atualizado + Contract §abort: SIGTERM + grace period 60s + force-acquire fallback
- **CHK037** → Spec §FR-036 novo: filtro de secrets em stderr/stdout/logs (nao so arquivos)

**Itens pendentes restantes (3) — baixo/medio impacto**:

| Item | Gap/Ambiguity | Impacto | Status |
|------|---------------|---------|--------|
| CHK001 | Overflow behavior implicito (truncar+warning) | Baixo | Contract menciona truncar; pode virar FR pequeno ou deixar implicito |
| CHK015 | "deploy externo" generico | Medio | Lista enumerada pode ser refinada no /plan ou em release notes |
| CHK027 | Drift mid-pipeline (spec vs briefing) | Medio | Cenario raro; pode aparecer como edge case no plan |
| CHK035 | Precedencia `.env` + `--whitelist` | Medio | Pode ser resolvido no /plan (regra de merge explicita) |

(Sao 4 itens, total 36+4=40. Recalcula: 36/40 = 90% — minha contagem inicial errou; vou recalcular.)

**Recalculado**: 36 atendidos (4 resolvidos no pass 2 + 32 do pass 1; CHK016/CHK033 contam 2) + 4 pendentes = 40.
- Atendidos: **36/40 (90%)**
- Pendentes: 4/40 (10%)

**Gate para /create-tasks**: **PASSED**. Todos os 4 gaps de alto impacto de seguranca (filtro fail-safe, gh exception explicita, race abort, logs sem secrets) resolvidos. Os 4 pendentes sao detalhes de implementacao apropriados para o /plan ou /create-tasks.
