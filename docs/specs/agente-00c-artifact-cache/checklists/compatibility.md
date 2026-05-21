# Compatibility Checklist: Agente-00C Artifact Cache

**Purpose**: Validar QUALIDADE dos requisitos de compatibilidade da
feature artifact-cache — preservacao de behavior standalone, schema
bump backwards-compatible, interacao com agente-00c/feature-00c
existentes.
**Created**: 2026-05-21
**Feature**: [`spec.md`](../spec.md)

## Standalone behavior das skills (FR-CACHE-014, SC-002)

- [ ] CHK001 - O criterio "output identico ao baseline pre-feature"
  (SC-002) eh definido em granularidade clara — diff de bytes do
  arquivo gerado? Hash? Subconjunto de campos? [Mensurabilidade, Spec §SC-002]
- [ ] CHK002 - Quais sao exatamente as "5 fixtures" mencionadas em
  SC-002 — uma por skill afetada (specify, clarify, plan,
  execute-task, checklist?) + 1 cross-skill (qual)? [Clareza, Spec §SC-002, Tasks T2.5]
- [ ] CHK003 - Skills NAO afetadas (briefing, constitution,
  create-tasks, review-task, review-features, etc) tem requisito
  explicito de "nao mudam comportamento", ou se assume? Como saber
  se uma mudanca colateral quebrou skill nao listada? [Cobertura, Gap]
- [ ] CHK004 - "Sem state.json" e "Com state.json mas sem cache"
  comportam-se IDENTICAMENTE (FR-CACHE-014). Existe teste com
  state.json populado mas SEM briefing_cache/constitution_cache? [Cobertura, Spec §FR-CACHE-014]
- [ ] CHK005 - Skill executada por outro orquestrador customizado
  (terceiro) — que cria state.json com schema diferente — nao quebra.
  Esse cenario eh testado? [Edge case, Gap]

## Schema bump em state.json

- [ ] CHK006 - O bump de schema_version eh MINOR (e.g., 1.4.0 → 1.5.0).
  A spec define a regra: campos opcionais novos = MINOR; mudanca em
  campos existentes = MAJOR? [Clareza, Spec §FR-CACHE-003, Plan §Compatibilidade]
- [ ] CHK007 - State.json legado (sem campos de cache) eh upgrade-compatible
  sem migrador. Existe teste que carrega state.json v1.4.0 com novo
  state-validate.sh v1.5.0 e nao falha? [Mensurabilidade, Tasks T1.6]
- [ ] CHK008 - Estado legado eh detectado automaticamente OU exige
  flag explicita? FR-CACHE-003 diz "upgrade-compatible" mas nao
  especifica como. [Ambiguity, Spec §FR-CACHE-003]
- [ ] CHK009 - Mudanca FUTURA do schema (v1.5 → v1.6) que adicione
  campos no `briefing_cache` quebra cache populado em v1.5? Existe
  politica de forward-compat? [Cobertura, Gap]
- [ ] CHK010 - Validacoes FR-CACHE-017 aplicam SOMENTE quando campos
  de cache estao presentes? Estado legado sem cache deve passar
  validate sem erro. [Cobertura, Spec §FR-CACHE-017]

## Interacao com agente-00c root

- [ ] CHK011 - O cache eh acessado tanto por `agente-00c-orchestrator`
  (root) quanto por `agente-00c-feature-orchestrator` (feature). Os
  dois orquestradores compartilham a primitiva `state-cache.sh`?
  [Completude, Spec §Dependencies "Features paralelas"]
- [ ] CHK012 - Path do state.json eh diferente entre root
  (`.claude/agente-00c-state/`) e feature (`.claude/feature-00c-state/<short>/`).
  A primitiva `state-cache.sh` aceita ambos via `--state-dir`? [Clareza, Gap]
- [ ] CHK013 - Se um projeto roda agente-00c (root) E feature-00c em
  paralelo (FR-026 ja preve essa coexistencia), cada um tem seu cache
  proprio sem race? [Edge case, Spec §FR-026 herdado]

## Interacao com cstk session

- [ ] CHK014 - Em `cstk session start`, a copia do `.claude/` exclui
  state.json (per FR-002 da feature cstk-session). O cache (que vive
  EM state.json) tambem fica excluido — sessao parte do zero. Esse
  contrato esta documentado? [Cobertura, Gap]
- [ ] CHK015 - Em retomada de session, briefing/constitution sao os
  mesmos do main (compartilhados via worktree). Cache regenera
  inutilmente em cada session ou pode compartilhar? [Edge case, Gap]

## Dependencias externas

- [ ] CHK016 - Requisitos de versao de `jq` (usado no state-rw.sh) e
  `sha256sum`/`shasum` (calculo de hash) estao documentados? [Completude, Plan §Linguagem e runtime]
- [ ] CHK017 - macOS vs Linux: divergencia entre `sha256sum` (linux)
  e `shasum -a 256` (macos) eh tratada por wrapper, ou cada chamada
  faz detect? Consistencia entre OS? [Clareza, Tasks T1.1]
- [ ] CHK018 - Hashes calculados em macos vs linux do MESMO conteudo
  sao iguais byte-a-byte? Test cross-platform existe? [Mensurabilidade, Gap]

## Backward compatibility de skills

- [ ] CHK019 - SKILL.md das 4 skills afetadas ganha bloco "## Leitura
  de artefatos foundational" (FR-CACHE-008). Esse bloco quebra parsers
  de SKILL.md existentes (cstk doctor, validate-documentation, etc)?
  [Edge case, Gap]
- [ ] CHK020 - Skills compostas (outras skills que invocam specify/
  clarify/plan/execute-task internamente) herdam o protocolo de
  leitura automaticamente, ou cada uma precisa adotar? [Cobertura, Gap]

## Auditabilidade cross-versao

- [ ] CHK021 - Relatorio final gerado por execucao no schema v1.5
  (com cache) eh comparavel com relatorio de execucao no schema v1.4
  (sem cache)? Secao "Cache de Artefatos" eh adicao puramente aditiva?
  [Clareza, Spec §FR-CACHE-013]
- [ ] CHK022 - `review-task` skill consegue ler state.json com cache
  sem regredir suas metricas? [Cobertura, Gap]

## Migracao operacional

- [ ] CHK023 - Operador que ja tem execucao em andamento (state.json
  v1.4 em progresso) e atualiza o toolkit para v1.5 — o que acontece?
  Spec diz "upgrade-compatible" — significa que continua a execucao
  sem cache, OU regenera cache na proxima onda? [Ambiguity, Plan §Compatibilidade]
- [ ] CHK024 - O cache em state.json sobrevive a `cstk update` /
  `cstk doctor reconcile`? Ou o reset de runtime invalida? [Edge case, Gap]

## Notes

- Marcar items concluidos com `[x]`
- Items rastreaveis: 16/24 (~67%) — abaixo do minimo 80%
- **CRITICO**: este checklist revelou 8 gaps em compatibility que
  precisam de FRs novos ou esclarecimentos na spec:
  - CHK003 (skills nao-afetadas), CHK005 (orquestrador 3rd-party),
    CHK009 (forward-compat futuro), CHK012 (path state.json variavel),
    CHK014/015 (interacao com cstk session), CHK018 (cross-platform),
    CHK019/020 (parsers e composicao de skills), CHK022 (review-task),
    CHK024 (interacao com cstk update)
- Sugestao: rodar `/clarify` novamente com foco em compatibility OU
  documentar esses 8 gaps como `[NEEDS CLARIFY rodada-2]` na spec antes
  de iniciar Fase 1
