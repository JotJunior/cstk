# Implementation Plan: Enxugar os prompts dos orquestradores autonomos

**Feature**: `orchestrator-slim` | **Date**: 2026-09-29 | **Spec**: [spec.md](./spec.md)

## Summary

Reduzir o prompt-base dos dois orquestradores
(`agente-00c-orchestrator.md`, 146014 bytes; `agente-00c-feature-orchestrator.md`,
104702 bytes) em >= 40% cada (FR-018), movendo secoes especificas de fase para
arquivos de referencia lidos sob demanda, sem alteracao semantica (FR-004).
Abordagem (research.md):

- Referencias em `plugins/cstk/skills/agente-00c-runtime/references/orchestrators/<root|feature>/<phase>.md`
  — o unico local que os dois canais distribuem como diretorio (Decision 1).
- Um arquivo por (orquestrador, fase); blocos multi-fase duplicados entre
  marcadores `FRAGMENT` com teste de byte-identidade (Decision 2). Sem
  referencia compartilhada entre O e F enquanto nenhum bloco movivel for
  byte-identico (medido: nenhum).
- Stub com heading original no lugar de cada secao movida + ponteiro
  padronizado com marcador `ORCH-REF` (Decisions 4-5).
- Resolucao via novo `orchestrator-refs.sh path` (ordem `strict` de
  `_resolve-root.sh`); falha => bloqueio humano (FR-010, Decision 3).
- Paridade provada por 3 verificacoes deterministicas contra o baseline
  `9f97e99`: preservacao de linhas, blocos de comando, literais contratuais
  (Decision 8).
- Medicao por `scripts/measure-orchestrator-prompts.sh`: bytes sempre; tokens
  `indisponivel` offline (fato medido) => gate em bytes com limitacao
  declarada (dec-010); observado via knowledge.db com `n`/cobertura
  (Decision 7).

Bloco "Finalize terminal" (`commit-mode.sh finalize`, onda terminal) fica no
prompt-base de ambos, fora do fragmento `stage-commit-hook` (data-model
§Decisao CHK021): O 946 bytes, F 460 bytes nao sao movidos.

Projecao (estimativa de planejamento recalculada com 650 bytes por stub e o
bloco Finalize no prompt-base; data-model §Projecao): O ~48%, F ~50% (meta
FR-018: 40% em cada).

## Technical Context

**Language/Version**: POSIX sh (scripts e testes); Markdown (prompts/referencias)
**Primary Dependencies**: nenhuma nova; `git` no script de desenvolvimento; `sqlite3` opcional com fallback no script de medicao
**Storage**: N/A (sem dados persistentes novos)
**Testing**: suite shell do repositorio (`tests/run.sh`, `tests/test_*.sh`), `LC_ALL=C`
**Target Platform**: qualquer ambiente POSIX onde o toolkit roda (fonte: briefing §Stack linha 79 "roda em qualquer ambiente POSIX sem setup"), pelos dois canais de instalacao da spec FR-008 (`cstk install` e plugin nativo)
**Project Type**: toolkit/CLI (prompts de agente + runtime POSIX)
**Performance Goals**: prompt-base de O <= 87608 bytes e de F <= 62821 bytes (projecao ~75.7k e ~52.4k com o bloco Finalize terminal mantido no prompt-base); toda fase com `loaded_bytes` < baseline
**Constraints**: paridade comportamental total (FR-004/FR-005); <= 1 leitura de referencia por fase percorrida (SC-006); sem rede
**Scale/Scope**: 2 prompts (250716 bytes), ~23 referencias novas, 1 script de runtime, 1 script de desenvolvimento, 12 testes migrados + 3 testes novos

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checar apos Phase 1.*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo | PASS | pipeline completa via feature-00c; spec+plan+tasks em `docs/specs/orchestrator-slim/`; entrada de CHANGELOG prevista |
| II. POSIX sh puro | PASS | `orchestrator-refs.sh` e testes em `#!/bin/sh` + `set -eu`, sem bash-isms; `sqlite3` so opcional, com fallback testado, confinado a `scripts/measure-orchestrator-prompts.sh` e declarado aqui (carve-out 1.1.0: a, b, c) |
| III. Progressive disclosure | PASS | a feature aplica ao agente o mesmo principio que a constitution exige de SKILL.md (ponto de entrada enxuto + `references/` sob demanda) |
| IV. Zero coleta remota | PASS | nenhuma chamada de rede; `count_tokens` da API descartado por esse motivo |
| V. Profundidade acima de adocao | PASS | reducao de custo recorrente por onda com prova de paridade |
| VI. Veracidade de dados | PASS | todo numero do plano vem de medicao citada; projecoes rotuladas como estimativa; tokens reportados `indisponivel` em vez de estimados |

## Project Structure

### Documentation (this feature)

```text
docs/specs/orchestrator-slim/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── orchestrator-refs-cli.md
│   ├── pointer-format.md
│   └── measure-cli.md
└── measurements/          # gerado na execucao
    ├── baseline.md
    └── after.md
```

### Source Code (repository root)

```text
plugins/cstk/agents/
├── agente-00c-orchestrator.md            # EDITADO: stubs no lugar das secoes movidas
└── agente-00c-feature-orchestrator.md    # EDITADO: idem
plugins/cstk/skills/agente-00c-runtime/
├── scripts/
│   ├── _resolve-root.sh                  # existente, reutilizado (ordem strict)
│   └── orchestrator-refs.sh              # NOVO
└── references/
    ├── (4 arquivos existentes, intocados)
    └── orchestrators/                    # NOVO
        ├── root/{bootstrap,briefing,constitution,roadmap,specify,clarify,plan,checklist,create-tasks,execute-task,converge,review-features}.md
        └── feature/{bootstrap,specify,clarify,plan,checklist,create-tasks,execute-task,converge,toolkit-issue}.md
scripts/
└── measure-orchestrator-prompts.sh       # NOVO (desenvolvimento, fora do catalogo)
tests/
├── lib/orchestrator-corpus.sh            # NOVO helper sourceable
├── fixtures/orchestrator-slim/           # NOVO inventarios (contract-literals.tsv, command-blocks.baseline.txt, rewritten-lines.tsv)
├── test_orchestrator-refs.sh             # NOVO: CLI + FR-009 (subtree, tarball, copia instalada)
├── test_orchestrator-slim-parity.sh      # NOVO: FR-006/FR-016 + fragmentos + meta FR-018 em bytes
├── test_measure-orchestrator-prompts.sh  # NOVO: medicao deterministica + fallback observado
└── (12 testes existentes migrados — data-model.md §Testes)
```

**Structure Decision**: referencias como subdiretorio de `references/` do
skill de runtime (Decision 1); nenhum diretorio novo fora dos ja existentes
exceto `references/orchestrators/`, `tests/fixtures/orchestrator-slim/` e
`docs/specs/orchestrator-slim/measurements/`.

## Ordem de implementacao (para create-tasks)

1. **Baseline primeiro** (FR-013): script de medicao + `measurements/baseline.md`
   contra `9f97e99`; inventarios de fixtures (literais, blocos de comando)
   extraidos do baseline; teste de paridade escrito e verde contra o
   baseline (corpus = so o prompt-base) ANTES de qualquer edicao dos prompts.
2. `orchestrator-refs.sh` + testes de CLI.
3. Helper `tests/lib/orchestrator-corpus.sh` + migracao dos 12 testes para o
   corpus (ainda verdes com corpus = prompt-base).
4. Mover secoes do O, uma fase por vez, rodando o teste de paridade a cada
   fase movida; depois do F.
5. Secao "Referencias de fase" em cada prompt-base (FR-010) + stubs.
6. Teste FR-009 (subtree + tarball + copia instalada) e `DOC_DIRS` de
   `test_doc-subcommands.sh`.
7. `measurements/after.md`; checar meta FR-018 em bytes; se nao atingida sem
   violar paridade, registrar "meta nao atingida" (FR-017).
8. CHANGELOG, fixtures (`tests/cstk/fixtures/regen.sh`), suite completa.

## Convencoes de Borda

N/A — single-layer (texto de prompt + scripts POSIX locais; sem borda de
payload entre camadas).

## Riscos

| Risco | Mitigacao |
|-------|-----------|
| Trecho classificado "fase" que na verdade roda em toda onda | verificacao manual guiada pelo inventario + margem de ~8-10 pontos percentuais sobre a meta (projecao ~48%/~50% contra 40%) permite devolver trechos ao prompt-base |
| Onda terminal nao leria o bloco `commit-mode.sh finalize` (CHK021) | bloco mantido no prompt-base de O e de F, fora de fragmento; teste de paridade afirma sua presenca |
| Orquestrador esquece de ler a referencia | stub no lugar exato do passo + secao "Referencias de fase" junto ao Contrato de conclusao de turno + regra FR-010 |
| Referencia ausente em instalacao antiga (catalogo e orquestrador fora de sincronia) | `path` exit 1 => bloqueio humano, nunca improviso (FR-010) |
| Teste migrado afrouxado sem perceber | inventario `contract-literals.tsv` roda contra baseline e corpus novo — padrao removido ou alterado aparece como diferenca |
| Referencia vira instrucao carregada de disco (LLM01/ASI04) | gate owasp-security: resolucao `strict` + confinamento sem symlink (S1), limite de 2000 linhas + marcador final contra leitura truncada (S2), datas validadas antes de SQL no script de medicao (S3) — ver contracts |
| Esta propria execucao usa os orquestradores instalados em `~/.claude/agents` | editar o repositorio nao afeta a execucao em andamento; a nova versao so vale apos release + `cstk update` |

## Complexity Tracking

> Sem violacoes de constitution a justificar.

| Violacao | Por Que Necessario | Alternativa Simples Rejeitada Porque |
|----------|-------------------|--------------------------------------|
| — | — | — |
