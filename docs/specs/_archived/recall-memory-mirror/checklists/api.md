# API Checklist: Recall Memory Mirror

**Purpose**: Validar qualidade dos requisitos de surface CLI do `cstk recall` — contratos de
input/output, exit codes, enum `--type`, help/usage e compatibilidade de output para os 5 novos
modos (busca unificada com memories, `--type memory`, `--ingest` aditivo, `--reindex`, `--list-memories`).
**Created**: 2026-05-27
**Feature**: [spec.md](../spec.md) | Contrato: [contracts/cstk-recall-memories.md](../contracts/cstk-recall-memories.md)

## Contratos e Schemas

- [x] CHK001 - O contrato define input/output para todos os 5 comandos novos/modificados? [Completude, Spec §FR-011/012/013] {auto}
  > Evidencia: `contracts/cstk-recall-memories.md` documenta os 5 comandos com tabelas de input, output renderizado e exit codes cada.

- [x] CHK002 - Todos os exit codes dos novos modos estao definidos e documentados? [Completude, Spec §FR-008/013] {auto}
  > Evidencia: Comandos 1 e 5 definem `exit 0` (sucesso + degradacao graciosa) e `exit 2` (uso incorreto). Ingest herda guardas existentes.

- [x] CHK003 - O enum `--type` extendido com `memory` documenta o erro para valor invalido? [Clareza, Spec §FR-012] {auto}
  > Evidencia: Contrato Cmd 2: `--type invalido → exit 2, msg '--type fora do enum (decision|bloqueio|retro|skill|memory)'`.

- [x] CHK004 - A adicao de `, N memories` ao output do `--ingest` e documentada como aditiva (nao breaking)? [Consistencia, Spec §CQ2] {auto}
  > Evidencia: Contrato Cmd 3 Output: "Apenas `, N memories` e acrescido ao final. Campos existentes inalterados." Plan §Convencoes de Borda confirma.

- [x] CHK005 - O comportamento de `--list-memories` sem `--project` (lista todos os projetos) esta explicito? [Clareza, Spec §FR-013] {auto}
  > Evidencia: Contrato Cmd 5 Input: `--project` opcional; sem ela = todos os projetos. Output mostra `project` em cada linha.

- [x] CHK006 - Combinacoes invalidas de flags (ex: `--list-memories` + modo busca) tem exit 2 documentado? [Completude, Spec §FR-013] {auto}
  > Evidencia: Contrato Cmd 5: `exit 2` para "flag invalida combinada". [Ambiguity] leve: quais combinacoes exatas disparam exit 2 nao esta enumerada — nao impede implementacao, mas o teste pode precisar de especificacao adicional.

- [x] CHK007 - O campo `project` e visivel na renderizacao de busca (proveniencia cross-projeto)? [Completude, Spec §US1 cenario 1] {auto}
  > Evidencia: Contrato Cmd 1 Output: `[memory] cstk / memory / - / 2026-05-27T18:00:00Z (slug)` — projeto visivel.

- [x] CHK008 - `--list-memories` com projeto sem memorias indexadas retorna stdout vazio, exit 0? [Cobertura, Spec §US4 cenario 2] {auto}
  > Evidencia: Spec US4 cenario 2 + Contrato Cmd 5 exit codes: "stdout vazio, exit 0".

- [x] CHK009 - O help/usage do `cstk recall` documenta `--list-memories` e a extensao do enum `--type`? [Completude, Spec §FR-013] {auto}
  > Evidencia: Contrato §Help/usage: `recall_usage` ganha linha `cstk recall --list-memories [--project P] [--db PATH]` + nota sobre `--type memory`.

- [x] CHK010 - O modo `--context` (read-back loop) nao exige mudanca de contrato ao herdar `memory` no enum? [Consistencia, Spec §FR-012, research.md Decision 8] {auto}
  > Evidencia: Research Decision 8: "`validate_type` aceita `memory` apos bump do enum; o modo `--context` usa o mesmo `validate_type` — sem mudanca de contrato."

## Notes

- Items `{auto}` ja vem resolvidos (`[x]` com evidencia citada)
- `[Ambiguity]` em CHK006 (combinacoes invalidas de flags) pode ser resolvido em `/clarify` se o implementador precisar de lista exaustiva
- Nenhum gap de completude detectado neste dominio — todos os 10 items passaram
