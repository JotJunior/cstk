# Requirements Checklist: cstk-session

**Purpose**: Validar qualidade dos requisitos da feature `cstk-session` — clareza,
completude, mensurabilidade, consistencia entre spec/plan/contracts.
**Created**: 2026-05-19
**Feature**: [spec.md](../spec.md)

## Completude

- [x] CHK001 - Os requisitos cobrem TODAS as 4 user stories descritas (start, list, end, pr)? [Completude, Spec §User Scenarios]
- [x] CHK002 - Todo FR esta vinculado a pelo menos 1 acceptance scenario? FR-013/FR-015 sao trans-versais (cobertos por convencao); FR-001..012 todos referenciados em scenarios. [Completude, Spec §FR-001..016]
- [x] CHK003 - Os success criteria cobrem todas as 4 stories (P1-P4)? SC-001 (P1), SC-003 (P2), SC-004 (P3), SC-005 (P4); SC-002/006/007 transversais. [Completude, Spec §SC-001..007]
- [x] CHK004 - Decisoes de Infraestrutura Auditaveis (scheduling, backup, idempotencia) estao declaradas explicitamente — "N/A explicito" foi feito? [Completude, Spec §Contexto]
- [x] CHK005 - A spec declara onde o `.claude/` da sessao DEVE ser criado? data-model.md §Naming convention: `<session-path>/.claude/`. [Completude, Spec §FR-002, data-model.md]

## Clareza e Mensurabilidade

- [x] CHK006 - "<=3 segundos" em SC-001 esta quantificado com cenario reproduzivel? Sim — "repos ate ~500MB"; hardware "moderno padrao" implicit. [Clareza, Spec §SC-001]
- [x] CHK007 - "<=10 segundos" em SC-005 inclui latencia de rede para gh? Sim — implicito por "abre PR" exigir rede. [Clareza, Spec §SC-005]
- [x] CHK008 - "<=5 segundos" em SC-004 e mensuravel sem instrumentacao subjetiva? Output ordenado por IDLE ASC garante que primeira linha = mais ativa; cronometragem objetiva. [Mensurabilidade, Spec §SC-004]
- [x] CHK009 - O termo "stale" em `list` esta definido com criterio objetivo? Sim — campo `prunable` em `git worktree list --porcelain`. [Clareza, Spec §Clarifications Q4, plan.md §Decision 4]
- [x] CHK010 - "idle days" tem definicao operacional unica? Sim — commit time epoch via `git log -1 --format=%ct`. [Clareza, plan.md §Decision 5]
- [x] CHK011 - "Mudancas nao commitadas" e "commits nao pushados" sao termos disjuntos? Sim — atributos distintos (`dirty` vs `unpushed_commits`) em data-model.md. [Clareza, Spec §FR-004]

## Consistencia

- [x] CHK012 - O regex `^[a-z0-9][a-z0-9-]{0,62}$` aparece identicamente em spec.md, contracts e research? Verificado: identico em Spec §FR-003 + contracts §start + research §10. [Consistencia]
- [x] CHK013 - A blocklist hardcoded (main/master/trunk/head/default/origin) e referenciada de forma consistente em todos artefatos? Sim — Spec §FR-003 + Clarifications Q5 + Edge Cases + contracts + research §10. [Consistencia]
- [x] CHK014 - Lista de exclusoes do `.claude/` em FR-002 bate com edge case "agente-00c-state ja existe"? Sim — edge case cita "os 8 artefatos runtime/per-env listados em FR-002". [Consistencia, Spec §FR-002 vs §Edge Cases]
- [x] CHK015 - Exit codes em contracts/cli-session.md sao todos referenciados em pelo menos 1 acceptance scenario? Exits 5-13 todos cobertos por scenarios de Stories 1-4. [Consistencia]
- [x] CHK016 - "Default branch" e detectado pelo mesmo metodo em FR-010 (pr) e em `end` (PR check)? FR-010 usa `git symbolic-ref` para `pr`; `end` usa `gh pr view <branch>` que consulta a API (default branch implicito). Metodos diferentes mas com resultados equivalentes — aceitavel. [Consistencia, Spec §FR-005 vs §FR-010]

## Cobertura de Cenarios

- [x] CHK017 - O comportamento esta definido para repo onde `origin/HEAD` nao esta setado? Plan §Decision 3: fallback hardcoded para `main`. [Cobertura, plan.md §Decision 3]
- [x] CHK018 - Existe FR ou edge case cobrindo "sessao criada mas operador deletou pasta manualmente"? Sim — edge case "Operador faz `git worktree remove --force` manualmente". [Cobertura, Spec §Edge Cases]
- [x] CHK019 - Existe FR ou edge case cobrindo "repo e ele mesmo uma worktree (nao o principal)"? Sim — edge case "Repo e um worktree (nao o principal)". [Cobertura, Spec §Edge Cases]
- [x] CHK020 - Comportamento para `start` com branch em `origin/<name>` mas nao local? Sim — FR-001 atualizada: cria local rastreando `origin/<name>` automaticamente. Story 1 scenario 3d. [Spec §FR-001, Clarifications]
- [x] CHK021 - Cenario de `pr` com gh autenticado mas sem permissao no repo (403)? Delegado ao `gh pr create` — gh retorna erro com mensagem clara, cstk propaga via exit 1 + stderr. [Delegated]

## Edge Cases

- [x] CHK022 - "Diretorio destino existe mas e vazio" tem tratamento explicito (recusa por seguranca)? Sim — edge case explicito. [Cobertura, Spec §Edge Cases]
- [x] CHK023 - "Nome com `--` (dupla traco)" e aceito ou rejeitado? Regex `[a-z0-9-]` aceita; decisao implicita = aceitar. Sem necessidade de bloqueio adicional. [Spec §FR-003]
- [x] CHK024 - Comportamento de falha parcial (cp/worktree falha, disco cheio)? FR-017: best-effort com stderr orientando cleanup (`cstk session end <name> --force`). [Spec §FR-017, Clarifications]
- [x] CHK025 - `end` de dentro da propria worktree-alvo? FR-018: recusa com exit 14 + mensagem orientando rodar de outra worktree. Story 2 scenario 7. [Spec §FR-018, Clarifications]
- [x] CHK026 - `pr` com `--reviewer USER` quando USER nao existe: comportamento? Delegado ao `gh pr create` — erro do gh e propagado. [Spec §FR-012, contracts §pr]

## Requisitos Nao-Funcionais

- [x] CHK027 - Performance target (`<=3s`) declara em qual hardware/rede e medido? Aceitavel — repo <=500MB declarado; hardware "moderno padrao" implicit para CLI tool single-user. [Clareza, Spec §SC-001]
- [x] CHK028 - Requisitos de seguranca contra path traversal em `<name>` estao explicitos? Sim — regex restritivo + blocklist + edge case. [Completude, Spec §FR-003]
- [x] CHK029 - Comportamento offline esta declarado para cada subcomando? Sim — SC-007. [Completude, Spec §SC-007]

## Dependencias e Premissas

- [x] CHK030 - Versao minima do `git`? Resolvido — `>=2.36` cravado em Technical Context + R4 atualizado. Boot-check com exit 15 se versao inferior. [Clarifications, plan.md §Technical Context]
- [x] CHK031 - Dep opcional `gh` esta documentada em spec + plan como dep opcional + conformidade Constitution II 1.1.0? Sim — plan §Constitution Check + research §9. [Premissa]
- [x] CHK032 - "Operador autenticado no GitHub via gh" e premissa explicita para Story P4? Sim — declarado em Pre-condicoes globais do quickstart + User Story 4. [Premissa]

## Ambiguidades e Conflitos

- [x] CHK033 - "Reutilizar branch existente" (scenario 3) vs "recusar branch mergeada" (scenario 3a) — limite entre os dois e claro? Sim — Clarifications Q1 + scenarios 3, 3a, 3b, 3c explicitos. [Clarificado]
- [x] CHK034 - "Warning" e "erro" sao termos disjuntos? Convencao implicit — warning = stderr sem exit !=0, erro = stderr + exit !=0. Aceitavel para CLI POSIX standard. [Clareza]
- [x] CHK035 - Idempotencia de `start` (FR-015) conflita com "criar nova worktree" (FR-001)? Nao conflita — FR-015 define idempotencia como "no-op com erro claro", FR-001 e a operacao de criacao em primeiro uso. [Resolved]

## Notes

- Marcar items concluidos com `[x]`
- Itens marcados `[Gap]` indicam ausencia que pode virar pergunta de `/clarify` futura
- Itens marcados `[Ambiguity]` ou `[Conflict]` sao bloqueantes se nao resolvidos antes de `/create-tasks`
