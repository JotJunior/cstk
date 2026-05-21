# Tasks: Agente-00C Artifact Cache

**Feature**: `agente-00c-artifact-cache`
**Spec**: [`spec.md`](./spec.md)
**Plan**: [`plan.md`](./plan.md)
**Created**: 2026-05-20
**Status**: Refinado pos-clarify (Session 2026-05-21) — T0.1 concluida.

> Criticidade: `[C]` = Critical (bloqueia release), `[A]` = Alto
> (defeito perceptivel ao usuario), `[M]` = Medio (qualidade /
> manutencao).

---

## Resumo quantitativo

| Fase | Tarefas | Tempo estimado |
|------|---------|----------------|
| Fase 0 — Clarify + Plan refinado | 1 (operacional) | 1 onda |
| Fase 1 — Primitiva + schema | 6 | 3-4 ondas |
| Fase 2 — Skills modificadas | 5 | 2-3 ondas |
| Fase 3 — Orquestrador + relatorio | 4 | 2 ondas |
| Fase 4 — Integracao + release | 4 | 2 ondas |
| **Total** | **20** | **~10-12 ondas** |

---

## Escopo coberto

- Nova primitiva `state-cache.sh` com 6 subcomandos.
- Schema bump em `state.json` (MINOR) + validacoes.
- Protocolo de leitura aditivo em 4 skills (specify, clarify,
  plan, execute-task).
- Integracao com agente-00c-orchestrator + feature-orchestrator.
- Secao nova no relatorio final.
- Testes unitarios e de regressao (>= 15 cenarios).

## Escopo excluido

- Cache de spec/plan/tasks (fora de escopo da spec).
- Cache cross-execucao em `~/.claude/cache/` (fora de escopo).
- Migrador automatico de state.json legado (campos opcionais).
- Configuracao per-skill (apenas global).
- Plug-in de medicao precisa de tokens via API Anthropic (heuristica chars/4).

---

## Fase 0 — Clarify + Plan refinado ✅ CONCLUIDA

### T0.1 [C] ✅ Resolver Open Questions Q1-Q5 da spec via `/clarify`

**Concluida em**: 2026-05-21 (Session de clarify).
**Decisoes registradas** (ver `spec.md` §Clarifications + `plan.md` §Research):
- Q1 → Heuristica extractiva deterministica (sem LLM).
- Q2 → Threshold fixo 3000 chars, override opcional.
- Q3 → Cache apenas da "constitution ativa" (1 campo).
- Q4 → Confiar no backup-de-onda quando hash bate.
- Q5 → Heuristica `chars * tokens_per_char_ratio` (default 0.25).

**Saida verificada**: spec.md §Clarifications populada com 5 bullets;
plan.md sem `[NEEDS CLARIFY]` restantes; FR-CACHE-005 substituido com
algoritmo deterministico.

**Desbloqueia**: T1.1, T1.2 podem iniciar.

---

## Fase 1 — Primitiva + schema ✅ CONCLUIDA (parcial — FR-CACHE-017A deferido p/ Fase 3)

### T1.1 [C] ✅ Implementar `state-cache.sh` subcomando `ensure`

**Path**: `global/skills/agente-00c-runtime/scripts/state-cache.sh`
**Spec ref**: FR-CACHE-004, FR-CACHE-005, FR-CACHE-006, FR-CACHE-007.
**Detalhes**:
- Receber `--state-dir`, `--artifact`, `--source-path`.
- Calcular `source_sha256` via `sha256sum` (linux) / `shasum -a 256` (macos).
- Decidir `estrategia`: se `source_chars < passthrough_threshold` → "passthrough"; senao "resumo".
- Para "resumo": invocar heuristica extractiva (T1.2). Sem LLM call (FR-CACHE-005, decidido em T0.1).
- Aplicar `secrets-filter.sh scrub` ao resumo.
- Atualizar state.json via `state-rw.sh set` (atomico).
- Registrar `Decisao` informativa via `state-decisions.sh register`.
**Testes**: cenarios em T1.5.

### T1.2 [C] ✅ Implementar gerador de resumo (heuristica extractiva v1)

**Path**: funcao interna em `state-cache.sh` OU script separado em
`scripts/_summarize.sh`.
**Detalhes**:
- Input: texto markdown + max-chars.
- Output: markdown reduzido (preserva `## Heading`, drops body
  prolixo, mantem 1a linha de cada heading).
- Determinista (mesma entrada = mesma saida).
**Bloqueio**: nenhum — T0.1 concluida (heuristica decidida).

### T1.3 [C] ✅ Implementar subcomandos `get-resumo`, `check-drift`, `invalidate`

**Spec ref**: FR-CACHE-008, FR-CACHE-009, FR-CACHE-010, FR-CACHE-015.
**Detalhes**:
- `get-resumo`: le `state.json`, valida `estrategia == "resumo"`, double-check sha256.
- `check-drift`: compara sha256 registrado vs disco. Distingue MAJOR (version primeiro digito mudou OU >50% chars diff) de MINOR/PATCH.
- `invalidate`: zera campo de cache, registra Decisao com justificativa fornecida via `--razao`.

### T1.4 [A] ✅ Implementar subcomandos `metrics-bump` e `status`

**Spec ref**: FR-CACHE-012.
**Detalhes**:
- `metrics-bump`: incrementa contador em `metricas.cache.*` (atomico).
- `status`: imprime JSON com estado completo do cache (debug/audit).

### T1.5 [C] ✅ Suite de testes `tests/test_state-cache.sh`

**Spec ref**: SC-005 (>= 15 cenarios).
**Entregue**: 23 cenarios em `tests/test_state-cache.sh` + 6 cenarios em
`tests/test__hash.sh` (cobre o wrapper de hash cross-platform). Total
de 29 cenarios novos cobrindo: passthrough, resumo, drift MINOR/MAJOR,
TOCTOU double-check, source ausente, source apagado, invalidate,
metrics-bump (hit/miss-drift/tipo-invalido), status (vazio + populado),
cache vazio, artifact invalido, sem subcomando, hash determinismo, hex
64 chars.

Cenario `scenario_ensure_registra_decisao_auditavel` ficou como **best-effort**
(invalidate registra Decisao se state-decisions.sh disponivel; smoke test
inline). Sera reforcado em Fase 3 quando orquestrador invoca primitiva.

### T1.6 [A] ⚠️ Estender `state-validate.sh` — FR-CACHE-017 ✅, FR-CACHE-017A ❌ DEFERIDO

**Path**: `global/skills/agente-00c-runtime/scripts/state-validate.sh`
**Entregue (FR-CACHE-017)**: 5 invariantes validadas quando campos
`briefing_cache`/`constitution_cache` presentes — sha256 (64 hex),
estrategia (enum), resumo_chars<=source_chars, gerado_em (ISO-8601),
gerado_na_onda (>=1 e <=ondas_total+1). +8 cenarios em
`tests/test_state-validate.sh` cobrindo cache valido, sha256 invalido,
estrategia invalida, resumo>source, gerado_em invalido, gerado_na_onda=0,
cache ausente (caso legado valido), validacao independente de
constitution_cache.

**Deferido (FR-CACHE-017A)**: validacao de schema_version vs runtime
fica para Fase 3 (T3.1) onde o schema sera bumpado de "1.0.0" para
"1.1.0" coordenadamente com a integracao no orquestrador. Adicionar
agora sem o bump nao detecta nada (campos sao opcionais, state.json
"1.0.0" com cache nulo eh valido).

### T1.7 [A] ✅ Wrapper `_hash.sh` cross-platform (FR-CACHE-016A)

**Path**: `global/skills/agente-00c-runtime/scripts/_hash.sh`
**Entregue**: `_hash_sha256_file` + `_hash_sha256_stdin` detectam OS via
`uname -s` e despacham para `sha256sum` (Linux) ou `shasum -a 256`
(Darwin). Outros SOs → exit 2 com mensagem. 6 cenarios em
`tests/test__hash.sh` cobrindo arquivo existente (hash conhecido),
path vazio, path inexistente, stdin, formato 64-hex, determinismo.

**Pendente**: CI matrix linux+macos no GitHub Actions. Sera adicionado
em Fase 4 (T4.1) junto com o test E2E. Por ora, suite roda em macos
local + ubuntu via release workflow existente.

### T1.7 [A] Wrapper `_cache_sha256()` cross-platform (FR-CACHE-016A)

**Path**: `global/skills/agente-00c-runtime/scripts/_state-dir.sh`
ou novo `_hash.sh`.
**Spec ref**: FR-CACHE-016A.
**Detalhes**:
- Detectar OS via `uname -s`: `Linux` → `sha256sum`; `Darwin` →
  `shasum -a 256`.
- Outros SOs ficam fora de escopo v1 (retornar exit !=0 com
  mensagem clara).
- Output: 64 chars hex via `awk '{print $1}'`.
**Tests**: `tests/test_hash-wrapper.sh` (NOVO):
- `scenario_linux_sha256sum_funciona` (skipped em macos)
- `scenario_macos_shasum_funciona` (skipped em linux)
- `scenario_input_identico_hash_identico` (smoke test).
**CI matrix**: GitHub Actions roda em `ubuntu-latest` + `macos-latest`
em paralelo (`.github/workflows/release.yml` ou novo workflow).

---

## Fase 2 — Skills modificadas ✅ CONCLUIDA

### T2.1 [C] ✅ Adicionar bloco em `specify/SKILL.md`
### T2.2 [C] ✅ Idem para `clarify/SKILL.md`
### T2.3 [C] ✅ Idem para `plan/SKILL.md` (com nota sobre dependencia hard)
### T2.4 [C] ✅ Idem para `execute-task/SKILL.md`

**Spec ref**: FR-CACHE-008.
**Entregue**: bloco `## Leitura de artefatos foundational (briefing + constitution)`
inserido em todas as 4 SKILL.md afetadas (specify, clarify, plan, execute-task)
imediatamente apos `## Argumentos`/`## Tarefa Solicitada` e antes do
`## FLUXO DE EXECUCAO`. Cada bloco documenta:

1. Como detectar agente-00c/feature-00c ativo (env var ou state.json file)
2. Como consumir cache via `state-cache.sh get-resumo` (exit 0/1/2 semantica)
3. Como reportar metricas via `state-cache.sh metrics-bump`
4. Fallback standalone quando agente nao esta ativo

Bloco do `plan` inclui nota adicional sobre dependencia hard em
`docs/constitution.md` (gate de violacoes na ETAPA 2). Bloco do
`execute-task` eh mais conciso (skill nao le briefing/constitution
diretamente em todas as etapas, so quando tarefa especifica precisa).

### T2.5 [C] ✅ Suite de validacao estrutural de SKILL.md

**Spec ref**: FR-CACHE-014, FR-CACHE-008A, SC-002.
**Entregue**: `tests/test_skills-cache-protocol.sh` (7 cenarios).

Decisao tecnica: "diff=0 do output do LLM" (texto literal de T2.5) eh
nao-testavel em CI sem chamada ao LLM. Substituido por **testes
estruturais** que validam invariantes verificaveis offline:

1. `yaml_frontmatter_valido_em_4_skills` — `---` aberto/fechado +
   campo `name:` presente em cada SKILL.md.
2. `bloco_cache_presente_em_4_skills` — heading exato esta presente.
3. `bloco_cache_antes_de_fluxo_em_4_skills` — bloco vem ANTES do
   `## FLUXO DE EXECUCAO` (insercao correta).
4. `bloco_cache_depois_de_argumentos_em_4_skills` — bloco vem DEPOIS
   de `## Argumentos` (insercao correta).
5. `bloco_cache_referencia_primitiva_em_4_skills` — bloco menciona
   `state-cache.sh get-resumo` + `metrics-bump`.
6. `bloco_cache_tem_ref_fr_em_4_skills` — bloco referencia FR-CACHE-008/014
   para rastreabilidade.
7. `secoes_pre_existentes_preservadas_em_4_skills` — todas as secoes
   originais (Pre-requisitos, Argumentos, ETAPAs, Gotchas) continuam
   presentes — nao removeu nada por engano.

**Pendente para Fase 4**:
- CI gate FR-CACHE-008A (rodar `cstk doctor` + `validate-documentation`
  na CI quando SKILL.md afetada muda) — adicionar em workflow do
  release.
- CHK022 (review-task com cache populado) — adicionar quando Fase 3
  popular cache no orquestrador (sem cache populado, test seria no-op).
- Diff-baseline real do LLM output — depende de fixture-de-LLM
  reprodutivel; fora de escopo automatable.

---

## Fase 3 — Orquestrador + relatorio

### T3.1 [C] Integrar `state-cache.sh ensure` no `agente-00c-orchestrator.md`

**Path**: `global/agents/agente-00c-orchestrator.md`
**Spec ref**: FR-CACHE-004.
**Detalhes**:
- No fim da etapa `briefing` (apos `pipeline.sh detect-completion`),
  invocar `state-cache.sh ensure --artifact briefing
  --source-path <briefing.md>`.
- No fim da etapa `constitution`, idem para constitution.
- Registrar Decisao auditavel via `state-decisions.sh register`.

### T3.2 [C] Pre-flight drift check no inicio de cada onda N>1

**Path**: `agente-00c-orchestrator.md` (Loop principal step 1.5)
**Spec ref**: FR-CACHE-009, FR-CACHE-010.
**Detalhes**:
- Apos `state-lock.sh acquire` + `state-validate.sh` + `sha256-verify`,
  invocar `state-cache.sh check-drift` para briefing e constitution.
- MAJOR drift → registrar `BloqueioHumano` antes de prosseguir.
- MINOR/PATCH drift → invocar `state-cache.sh ensure` para regenerar.

### T3.3 [C] Espelhar T3.1 e T3.2 em `agente-00c-feature-orchestrator.md`

**Path**: `global/agents/agente-00c-feature-orchestrator.md`
**Spec ref**: cobertura da feature-00c (mesma primitiva, mesmo state.json).

### T3.4 [A] Secao `### Cache de Artefatos` em `report.sh generate`

**Path**: `global/skills/agente-00c-runtime/scripts/report.sh`
**Spec ref**: FR-CACHE-013.
**Detalhes**:
- Adicionar secao apos `### Decisoes` (ou apos `### Bloqueios`).
- Conteudo: tabela 2 colunas (briefing + constitution) com source_chars,
  resumo_chars, estrategia, hits, drift detectado.
- Subsecao "Economia liquida": `tokens_economizados_estimados`.

---

## Fase 4 — Integracao + release

### T4.1 [C] Test E2E em projeto fixture

**Path**: `tests/cstk/test_cache-pipeline-e2e.sh` (NOVO).
**Detalhes**:
- Criar fixture mini-projeto com briefing+constitution conhecidos
  (>= 5k chars cada).
- Rodar simulacao de 3 ondas via primitivas (sem precisar invocar
  Claude — tests sao para o runtime POSIX).
- Validar: cache populado na onda 1, hits nas ondas 2 e 3,
  drift detectado quando arquivo alterado.

### T4.2 [A] Medicao real de SC-001 em projeto piloto

**Detalhes**:
- Selecionar 1 projeto real (ex: `cstk-cli` ou um existente).
- Rodar `/agente-00c` BASELINE (sem cache) — capturar baseline de tokens.
- Mergear PR → rodar `/agente-00c` COM cache em ramo separado.
- Comparar `metricas.cache.tokens_economizados_estimados` real vs
  estimativa em spec (5-10k tok/onda).
- Documentar resultado em `validation-runs/sc-001-piloto.md`.

### T4.3 [M] Atualizar CHANGELOG.md + bump de versao MINOR

**Path**: `CHANGELOG.md`
**Detalhes**:
- Entrada nova em `[Unreleased]` descrevendo Added/Changed.
- Schema_version bump documentado (X.Y.0 → X.(Y+1).0).
- Bump da versao do toolkit (MINOR — feature nova, nao breaking).

### T4.4 [A] Atualizar doc em CLAUDE.md (per-user) com nota sobre o cache

**Detalhes**: nao versionado, mas Joao adiciona uma linha em
`CLAUDE.md` local explicando que o cache existe + como inspecionar
(`state-cache.sh status`).

---

## Matriz de dependencias

```
T0.1 (clarify)
  │
  ├─→ T1.1 (ensure) ──→ T1.3 (get-resumo, check-drift, invalidate)
  │      │                    │
  │      └─→ T1.2 (resumo)    └─→ T1.4 (metrics, status)
  │                                    │
  │                                    └─→ T1.5 (tests) ──→ T1.6 (validate)
  │
  ├─→ T2.1, T2.2, T2.3, T2.4 (skills) ──→ T2.5 (regressao)
  │      [dependem de T1.3 estar disponivel]
  │
  ├─→ T3.1, T3.2, T3.3 (orquestrador) ──→ T3.4 (relatorio)
  │      [dependem de T1.1 + T1.3 estaveis]
  │
  └─→ T4.1 (e2e) ──→ T4.2 (piloto) ──→ T4.3 (changelog) ──→ T4.4 (docs)
         [depende de TUDO acima merged]
```

Caminho critico: T0.1 → T1.1 → T1.3 → T1.5 → T3.1/T3.2 → T4.1 → T4.2 → T4.3.

---

## Coverage matrix (Requisitos × Tarefas)

| FR-CACHE | Tarefa(s) cobrindo |
|----------|---------------------|
| FR-CACHE-001 (campos opcionais) | T1.1, T1.6 |
| FR-CACHE-002 (estrutura do campo) | T1.1, T1.6 |
| FR-CACHE-003 (schema_version bump) | T1.6, T4.3 |
| FR-CACHE-004 (populacao na onda 1) | T1.1, T3.1, T3.3 |
| FR-CACHE-005 (politica de geracao) | T0.1, T1.2 |
| FR-CACHE-006 (secrets-filter) | T1.1, T1.5 (cenario 3) |
| FR-CACHE-007 (threshold passthrough) | T1.1, T1.5 (cenario 2) |
| FR-CACHE-008 (protocolo de leitura) | T2.1-T2.4 |
| FR-CACHE-009 (invalidacao auto) | T1.3, T3.2 |
| FR-CACHE-010 (drift MAJOR → bloqueio) | T1.3, T3.2 |
| FR-CACHE-011 (Decisao em invalidacao) | T1.1, T1.3 |
| FR-CACHE-012 (contadores metricas) | T1.4 |
| FR-CACHE-013 (secao no relatorio) | T3.4 |
| FR-CACHE-014 (standalone preservado) | T2.5 |
| FR-CACHE-015 (exit-codes get-resumo) | T1.3, T1.5 |
| FR-CACHE-016 (exige lock) | T1.1-T1.4 (validar em T1.5 cenario 13) |
| FR-CACHE-017 (state-validate) | T1.6 |
| SC-001 (>= 70% economia) | T4.2 |
| SC-002 (regressao = 0) | T2.5 |
| SC-003 (100% drift detectado) | T1.5 |
| SC-004 (zero secrets vazados) | T1.5 (cenario 3) |
| SC-005 (suite 15+ cenarios) | T1.5, T2.5 |

---

## Pontos de validacao (gates entre fases)

- **Apos Fase 0**: spec atualizada + plan sem `[NEEDS CLARIFY]`.
- **Apos Fase 1**: `state-cache.sh` 6 subcomandos passando >= 15
  cenarios. `./tests/run.sh` sem regressao.
- **Apos Fase 2**: skills modificadas; suite de regressao
  standalone passa com diff=0. `./tests/run.sh` sem regressao.
- **Apos Fase 3**: orquestrador integrado; pipeline simulada local
  registra hits.
- **Apos Fase 4**: piloto real mostrou SC-001 atendido (>=70%
  economia). CHANGELOG atualizado. Versao bumped.
