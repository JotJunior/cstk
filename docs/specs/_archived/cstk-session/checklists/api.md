# API/CLI Contract Checklist: cstk-session

**Purpose**: Validar qualidade dos requisitos do contrato CLI — exit codes,
output formats, idempotencia, mensagens de erro acionaveis.
**Created**: 2026-05-19
**Feature**: [spec.md](../spec.md), [contracts/cli-session.md](../contracts/cli-session.md)

## Cobertura de Subcomandos

- [x] CHK001 - Os 4 verbos tem contrato completo? Sim — contracts/cli-session.md cobre sinopse/args/exit/stdout/stderr de cada um. [Completude]
- [x] CHK002 - `cstk session` sem subcomando? Sim — contracts §"Comando: cstk session (sem subcomando)" + exit 2. [Completude]
- [x] CHK003 - Flags mutex declaradas? Sim — `--reset` vs `--reuse` em contracts §start: "Ambos passados = exit 2". [Clareza]

## Exit Codes

- [x] CHK004 - Exit codes 5-13 mutuamente exclusivos com 0-4 do cstk? Sim — cstk usa 0,1,2,3,4; feature usa 5-13 sem sobreposicao. [Consistencia]
- [x] CHK005 - Cada exit != 0 tem mensagem acionavel? Sim — todas as mensagens de erro em contracts citam acao corretiva. [Spec §SC-006]
- [x] CHK006 - Exit 5/6/7/8 sao distintos? Sim — contracts §start lista cada um. [Consistencia]
- [x] CHK007 - 11 (gh nao instalado) vs 12 (gh nao autenticado)? Sim — distintos para acao diferente. [Clareza]
- [x] CHK008 - Exit 10 (cancelado) e nao-erro? Documentado em contracts §end: "Usuario cancelou prompt (resposta != y)". [Clareza]

## Output Format

- [x] CHK009 - stdout/stderr consistente? Sim — contracts separa explicitamente. [Consistencia]
- [x] CHK010 - `--json` produz JSON valido? Sim — contracts §list mostra estrutura. [Spec §FR-008]
- [x] CHK011 - `--json` suprime rodape? Sim — FR-008: "Rodape de tip e suprimido em modo JSON". [Consistencia]
- [x] CHK012 - Tabela tem cabecalho fixo? Sim — `NAME BRANCH IDLE STATUS PATH` em contracts. [Estabilidade]
- [x] CHK013 - JSON em camelCase? Sim — plan §Convencoes de Borda + FR-008. [Consistencia]

## Idempotencia

- [x] CHK014 - `start` ja existente? Erro sem destruir — FR-015 + Story 1 scenario 2 + exit 6. [Spec §FR-015]
- [x] CHK015 - `pr` quando PR ja existe? Retorna URL com exit 0 — FR-011 + Story 4 scenario 2. [Spec §FR-011]
- [x] CHK016 - `end <inexistente>` erro claro? Sim — exit 9 + Story 2 scenario 6. [Spec §FR-015]
- [x] CHK017 - `list` em repo vazio retorna exit 0? Sim — Story 3 scenario 1. [contracts §list]

## Comportamento Sob Falha

- [x] CHK018 - `git worktree add` falhar no meio de `start`? FR-017: worktree parcial fica criada; stderr instrui `cstk session end <name> --force`. [Spec §FR-017]
- [x] CHK019 - `gh pr create` falhar APOS push? FR-017: branch fica pushada; stderr instrui retry `gh pr create` ou desfazer via `git push -d origin <branch>`. Sem rollback automatico. [Spec §FR-017, Clarifications]
- [x] CHK020 - `end` com `git worktree remove` falhando mas `git branch -D` succeeding? Coberto por FR-006: "Se remocao parcial falhar, mensagem indica estado residual exato". [Spec §FR-006]
- [x] CHK021 - Repo nao-git: TODOS subcomandos exit consistente? FR-003 cobre `start`; FR-013 generaliza para os outros via `git rev-parse --git-common-dir` que ja falha em repo nao-git. [Consistencia]

## Argumentos e Flags

- [x] CHK022 - `--reset`/`--reuse` mutex em todos os artefatos? Sim — Spec §FR-001 + contracts §start. [Consistencia]
- [x] CHK023 - `--force`/`--draft`/`--title`/`--body`/`--reviewer` documentadas? Sim — contracts §end e §pr cobrem cada flag. [Completude]
- [x] CHK024 - Flag desconhecida → exit 2? Convencao do cstk (`CSTK_EXIT_USAGE=2`); aplicada por padrao. [contracts]
- [x] CHK025 - `<name>` ausente → exit 2? Convencao do cstk; aplicada por padrao. [contracts]

## Acessibilidade de Mensagens

- [x] CHK026 - Mensagens auto-contidas? Sim — SC-006 enforce. [Spec §SC-006]
- [x] CHK027 - Mensagens citam acao corretiva? Sim — SC-006: "100% das chamadas que falham por pre-condicao retornam mensagem que o usuario consegue acionar". [Spec §SC-006]
- [x] CHK028 - Mensagens sem acentos/unicode? Verificado — mensagens em portugues sem acentos, consistente com o resto do toolkit (`cli/cstk`, `cli/lib/*`). [Compatibilidade]

## Comportamento Cross-Worktree

- [x] CHK029 - FR-013 cobre invocacao a partir de uma worktree-sessao? Sim — texto explicit "principal OU worktree". [Spec §FR-013]
- [x] CHK030 - `list` de dentro de uma sessao mostra ela mesma? Sim — inclui com marcador `CURRENT` na coluna STATUS. FR-007 atualizado + Story 3 scenarios 4-5. [Spec §FR-007, Clarifications]
- [x] CHK031 - Path relativo aceito em `<name>`? Nao — regex `^[a-z0-9]` rejeita `.` e `./`. [Consistencia]

## Notes

- Marcar items concluidos com `[x]`
- Exit codes da feature documentados em `contracts/cli-session.md`
- Itens cross-worktree (CHK029-031) podem revelar gap em FR-013
