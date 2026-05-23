# Implementation Plan: cstk Knowledge DB

**Feature**: `cstk-knowledge-db` | **Date**: 2026-05-23 | **Spec**:
[spec.md](./spec.md)

## Summary

Camada **aditiva** de memoria cross-feature pesquisavel. Um indice SQLite
global ao usuario (`~/.claude/cstk/knowledge.db`) com FTS5 ingere, ao fim
de cada onda, o conhecimento ja estruturado do `state.json` (decisoes,
bloqueios, retros, skills invocadas) com proveniencia completa, e expoe
busca full-text cross-projeto/feature via `cstk recall`. A camada e
estritamente **read-only sobre o state transacional** (zero risco no
caminho critico) e **best-effort** (qualquer falha degrada gracioso —
nunca aborta a onda). O indice e derivado e reconstruivel via
`--reindex`.

Abordagem tecnica (da pesquisa): SQLite+FTS5 sob carve-out de deps
opcionais; concorrencia via WAL + `busy_timeout` + retry/backoff (sem
reusar o lock transacional); idempotencia por chave de proveniencia
(upsert); filtro de segredos confinado, aplicado so a texto livre.

## Technical Context

**Language/Version**: POSIX sh (`#!/bin/sh`, `set -eu`, sem bash-isms) —
Constitution Principio II
**Primary Dependencies**: `sqlite3` (FTS5) e `jq` como **deps opcionais**
sob carve-out 1.1.0 (ver §Optional-dep registry); `secrets-filter.sh` do
runtime; ferramentas POSIX canonicas (`mktemp`, `printf`, `grep`,
`command`, `sed`)
**Storage**: SQLite single-file em `~/.claude/cstk/knowledge.db` (override
`CSTK_KNOWLEDGE_DB` / `--db`); WAL mode
**Testing**: harness POSIX do repo (`tests/run.sh`); novo
`tests/cstk/test_recall.sh` (convencao `cli/lib/<n>.sh` →
`tests/cstk/test_<n>.sh`)
**Target Platform**: ambiente local do usuario (macOS/Linux com shell
POSIX); zero servidor, zero rede (Principio IV)
**Project Type**: CLI tool (single-layer) — extensao do binario `cstk`
**Performance Goals**: busca interativa (<1s p/ indice tipico);
idempotencia O(registros da onda) por ingestao
**Constraints**: nunca escrever no state transacional (SC-006); nunca
abortar onda (FR-018/SC-003); deps so via carve-out (FR-020); POSIX puro
(FR-021); **escaping SQL/FTS obrigatorio** — `sqlite3` CLI nao tem bind
nativo via argv, entao `'`→`''` (SQL) e query como frase FTS5 `"`→`""`
sao a defesa primaria contra A05/CWE-89 (ver §Security); `project` =
basename do projeto-alvo para reduzir captura de segredo em path
**Scale/Scope**: indice cresce ~dezenas de registros por onda; uso
single-user; reconstruivel a qualquer momento

## Constitution Check

*GATE: passou antes do Phase 0; re-checado apos Phase 1 (ver §Re-check).*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (NON-NEGOTIABLE) | PASS | feature entra via spec→clarify→plan→tasks; artefatos em `docs/specs/cstk-knowledge-db/` |
| II. POSIX sh puro, zero dep (NON-NEGOTIABLE) | PASS | scripts `#!/bin/sh` + `set -eu`, sem bash-isms; `sqlite3`/`jq` entram pela carve-out 1.1.0 com as 3 condicoes cumulativas (ver §Optional-dep registry) |
| III. Formato canonico de skill | N/A | feature e extensao do CLI `cstk`, nao uma skill; segue convencao de `cli/lib/<cmd>.sh` |
| IV. Zero coleta remota (NON-NEGOTIABLE) | PASS | indice 100% local; nenhuma rede; nenhum upload (FR-017); secrets-filter como defesa em profundidade |
| V. Profundidade sobre adocao | PASS | feature reduz retrabalho (reaproveita aprendizado cross-feature) em vez de perseguir visibilidade |

Quality Standards aplicaveis:

- POSIX/shellcheck `-s sh`: meta zero warnings.
- Teste automatizado por script novo: `tests/cstk/test_recall.sh`
  (FR-022, SC-007); `--check-coverage` nao pode acusar orfao.
- SemVer + CHANGELOG: feature adiciona comando novo (`cstk recall`) —
  MINOR bump no release.
- Nenhum secret em repo: garantido por FR-017 + Principio IV.

## Optional-dep registry (carve-out Principio II amendment 1.1.0)

Demonstracao das tres condicoes cumulativas (a)(b)(c) para cada dep
opcional. Modelo: §Complexity Tracking de `docs/specs/_archived/cstk-cli/`.

### Dep: `sqlite3` (com FTS5)

- **(a) Opcional + fallback graceful testado**: a feature funciona sem
  `sqlite3` — ingestao emite aviso e pula (FR-018); `recall` informa que
  a memoria esta indisponivel. Coberto por teste (Cenario 9 do
  quickstart, FR-019).
- **(b) Confinado a UM arquivo**: toda referencia a `sqlite3` vive em
  `cli/lib/recall.sh`. Verificavel:
  `grep -rn 'sqlite3' cli/lib/` casa somente `cli/lib/recall.sh`.
- **(c) Declarada com justificativa/path/fallback**: justificativa =
  engine zero-config com FTS5 nativo (busca full-text + ranking) e
  upsert idempotente; path = `cli/lib/recall.sh`; fallback = degradacao
  graciosa (aviso + skip/“indisponivel”, exit 0).

### Dep: `jq`

- **(a) Opcional + fallback graceful testado**: sem `jq`, a ingestao nao
  parseia `state.json` → aviso + skip (FR-018). Coberto por teste
  (Cenario 10 do quickstart).
- **(b) Confinado a UM arquivo**: o uso de `jq` desta feature vive em
  `cli/lib/recall.sh` (o precedente `cli/lib/hooks.sh` permanece o unico
  outro arquivo com `jq`; confinamento e por arquivo identificavel — cada
  uso e localizavel num unico arquivo).
- **(c) Declarada**: justificativa = parse de JSON estruturado do
  `state.json`; path = `cli/lib/recall.sh`; fallback = degradacao
  graciosa.

### Dep: `secrets-filter.sh` (do runtime)

- Nao e dep externa nova — e helper interno do runtime. Reuso confinado a
  `cli/lib/recall.sh` (FR-017). Se ausente, a ingestao degrada gracioso
  (sem scrub → melhor pular do que vazar; decisao: na ausencia do helper,
  ingestao emite aviso e pula a onda, mantendo o invariante de seguranca).

## Project Structure

### Documentation (this feature)

```
docs/specs/cstk-knowledge-db/
├── spec.md
├── plan.md          # This file
├── research.md      # Phase 0 output
├── data-model.md    # Phase 1 output
├── quickstart.md    # Phase 1 output
└── contracts/
    ├── ingest-helper.md   # contrato da ingestao pos-onda
    └── cstk-recall.md     # contrato do comando cstk recall (+ ingest/reindex)
```

### Source Code (repository root)

```
cli/
├── cstk                  # binario dispatcher (ja existe) — registra `recall`
└── lib/
    ├── recall.sh         # NOVO — recall_main + ingestao + reindex;
    │                     #   UNICO arquivo com sqlite3 + jq + secrets-filter
    │                     #   (carve-out condicao b); define schema + pragmas
    ├── common.sh         # (existente) log_info/log_warn/log_error reusados
    └── hooks.sh          # (existente) precedente de jq confinado

tests/cstk/
├── test_recall.sh        # NOVO — cobre cenarios 1-14 do quickstart
└── fixtures/
    └── knowledge/        # NOVO — state.json sinteticos p/ ingestao/reindex

~/.claude/cstk/
└── knowledge.db          # runtime, fora do repo; criado on-demand
```

**Structure Decision**: concentrar ingestao + recall + reindex + schema +
todas as deps opcionais (`sqlite3`, `jq`, `secrets-filter.sh`) em UM unico
arquivo `cli/lib/recall.sh`. Razao: satisfaz a condicao (b) do carve-out
(grep localiza todas as mencoes num arquivo) e simplifica o mapeamento de
teste para um unico `tests/cstk/test_recall.sh` (FR-022/SC-007). O comando
de usuario e `cstk recall` (despacho ja existente
`cli/lib/<cmd>.sh::<cmd>_main`); modos auxiliares via flags `--ingest` e
`--reindex`. A ingestao pos-onda e disparada chamando o binario `cstk`
(degrada gracioso se ausente) — o runtime/orquestrador permanece
desacoplado do schema do indice.

## Convencoes de Borda

N/A — single-layer. A feature e um CLI tool sobre SQLite local, sem
fronteira backend↔frontend, sem serializacao de DTO cross-camada, sem
mapper. A unica "convencao de dados" e o schema SQL (snake_case, ingles),
cuja fonte da verdade e `cli/lib/recall.sh` (documentado em
`data-model.md`). Nenhum roundtrip de payload a validar.

## Complexity Tracking

> Sem violacao de constitution. As deps `sqlite3`/`jq` NAO sao violacao —
> sao conformidade explicita via o carve-out 1.1.0 do Principio II
> (subsecao "Optional dependencies with graceful fallback"), conforme
> Decision Framework item 4 (subsecoes de carve-out sao mecanismo valido,
> nao opt-out). Detalhamento das 3 condicoes em §Optional-dep registry.
> Nenhuma entrada de Complexity Tracking necessaria.

## Security (gate owasp-security)

Gate `owasp-security` rodado apos Phase 1. Mapeamento de superficie e
findings (detalhe em data-model §Security Considerations e nos contratos):

| # | Finding | OWASP/CWE | Sev | Status |
|---|---------|-----------|-----|--------|
| S1 | `sqlite3` CLI nao tem bind via argv; mitigacao "bind parameter" do contrato original era irrealizavel — risco de SQLi/FTS injection se implementado por concatenacao | A05 / CWE-89 | HIGH | Corrigido nos artefatos: escaping 2-camadas obrigatorio (`'`→`''` SQL; frase FTS5 `"`→`""`), verificado empiricamente; testes adversariais 13b/13c |
| S2 | Segredo embutido em campo de proveniencia/estruturado (que nao passa pelo filtro, FR-017) | A02 | MEDIUM | Mitigado: `project`=basename; indice 100% local (Principio IV); ids/scores/ts sem superficie pratica |
| S3 | Degradacao graciosa (exit 0) poderia mascarar falha de seguranca | A10 | LOW | Esclarecido: exit 0 so para indisponibilidade operacional; erro de uso=exit 2; escaping e prevencao por construcao + teste, nao runtime-degradado |
| S4 | Privacidade / zero rede | Principio IV | — | PASS: sem rede, sem upload |

Validacao empirica do escaping (sonda em `sqlite3` :memory:):
`'`→`''` armazena `O'Brien'; DROP TABLE x; --` literalmente sem injecao
(exit 0); frase FTS5 com `"`→`""` executa `"aspas" AND (paren) *` sem
erro de sintaxe (exit 0).

## Re-check (pos-Phase 1)

Re-validacao apos design:

- **II (POSIX/deps)**: o design nao introduziu bash-isms; deps continuam
  confinadas a um arquivo e cobertas por fallback testado. PASS.
- **IV (zero remoto)**: o design e 100% local; WAL/FTS5 nao tocam rede;
  secrets-filter so reforca privacidade. PASS.
- **I (SDD)**: artefatos completos (spec/research/data-model/contracts/
  quickstart/plan). PASS.
- **Seguranca (gate)**: finding HIGH (S1) corrigido nos artefatos antes
  de avancar; escaping obrigatorio agora e parte do contrato +
  constraint + teste adversarial. MEDIUM (S2) mitigado por basename +
  localidade. PASS apos correcao.
- Nenhuma complexidade nao justificada introduzida (um unico arquivo
  novo + um teste novo). PASS.

## Artefatos

| Arquivo | Status |
|---------|--------|
| docs/specs/cstk-knowledge-db/plan.md | Criado |
| docs/specs/cstk-knowledge-db/research.md | Criado |
| docs/specs/cstk-knowledge-db/data-model.md | Criado |
| docs/specs/cstk-knowledge-db/contracts/ingest-helper.md | Criado |
| docs/specs/cstk-knowledge-db/contracts/cstk-recall.md | Criado |
| docs/specs/cstk-knowledge-db/quickstart.md | Criado |

## Proximos Passos

1. `/checklist` — gerar quality gate antes de implementar.
2. `/create-tasks` — decompor o plano em backlog executavel.
3. `/analyze` — validar consistencia cross-artifact (apos tasks).

**Constitution**: PASS | **NEEDS CLARIFICATION restantes**: 0
