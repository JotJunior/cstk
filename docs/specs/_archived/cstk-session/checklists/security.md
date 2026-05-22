# Security Checklist: cstk-session

**Purpose**: Validar qualidade dos requisitos de seguranca — validacao de
input, path traversal, dependencia externa (gh), exposicao de dados
sensiveis no `.claude/`.
**Created**: 2026-05-19
**Feature**: [spec.md](../spec.md)

## Validacao de Input

- [x] CHK001 - O regex rejeita prefixo `-`? Sim — `^[a-z0-9]` exige comecar com alfanumerico. [Spec §FR-003]
- [x] CHK002 - O regex rejeita unicode/acentos? Sim — classes ASCII `[a-z0-9-]`. [Spec §FR-003]
- [x] CHK003 - Blocklist case-insensitive? Sim — regex ja garante lowercase, blocklist e exact-match suficiente. [Consistencia, Spec §FR-003]
- [x] CHK004 - Rejeicao de nomes que comecam com `.`? Sim — regex `^[a-z0-9]` impede. [Spec §FR-003]

## Path Traversal

- [x] CHK005 - Rejeicao de `..`, `/`, `\`, espaco? Sim — regex so aceita `[a-z0-9-]`. [Spec §FR-003]
- [x] CHK006 - Concatenacao segura sem eval? plan §3.1 usa variaveis shell padrao; sem eval. [Premissa, plan.md §3.1]
- [x] CHK007 - Comportamento declarado para `<repo-name>` (basename do PAP) contendo caracteres problematicos? Delegado ao `git worktree add` — git falha com mensagem clara se path nao e valido. Caso raro em uso solo. [Delegated]
- [x] CHK008 - FR-013 nao introduz vetor de escalation por symlink traversal? `git rev-parse --git-common-dir` resolve symlinks de forma segura via git. [Premissa, plan.md §FR-013]

## Dependencia Externa Confiavel (gh)

- [x] CHK009 - `pr` usa credenciais do gh sem cache adicional? cstk nunca toca em token — delega ao gh. [Spec §FR-009, Constitution IV]
- [x] CHK010 - Comportamento se `gh auth status` retorna credenciais expiradas/invalidas? Delegado ao gh — exit !=0 e tratado pela cstk como "nao autenticado" (exit 12 + mensagem `rode gh auth login` resolve ambos os casos). [Delegated]
- [x] CHK011 - `pr` documenta que NENHUM token e logado? Premissa implicit — cstk so chama `gh pr create`, gh nao expoe token em stdout. [Premissa, contracts §pr]

## Exposicao de Dados Sensiveis

- [x] CHK012 - Lista de exclusao FR-002 inclui artefatos sensiveis (state, settings.local, whitelist)? Sim — 8 itens cobrem todas as categorias runtime/per-env. [Completude, Spec §FR-002, Clarifications Q2]
- [x] CHK013 - `settings.local.json` na exclusion list? Sim. [Spec §FR-002]
- [x] CHK014 - `agente-00c-whitelist` na exclusion list? Sim. [Spec §FR-002]
- [x] CHK015 - Outros artefatos com PII (logs, traces, profile)? Lista de 8 e exaustiva para artefatos canonicos do `.claude/`; logs/traces nao sao gerados em `.claude/` pela feature. [Completude]

## Privilegio Minimo / Confirmacao Explicita

- [x] CHK016 - `end` exige confirmacao por padrao? Sim — FR-004 + Story 2 scenarios 2-5. [Spec §FR-004]
- [x] CHK017 - `--force` documentado como destrutivo? Sim — contracts §end + Story 2 scenario 3. [Spec §FR-004, contracts §end]
- [x] CHK018 - `end` NUNCA force-pusha? FR-006 lista apenas `git worktree remove` + `git branch -D`. Zero ops remotas destrutivas. [Premissa, Spec §FR-006]
- [x] CHK019 - `start --reset` com aviso? Sim — prompt interativo lista commits a descartar se branch nao-mergeada; `--force` bypassa. FR-001 atualizada + Story 1 scenario 3e. [Spec §FR-001, Clarifications]

## Defesa em Profundidade

- [x] CHK020 - Se regex falhar, blocklist ainda protege? Sim — validacao 2-step independente. [Defesa em profundidade, research §10]
- [x] CHK021 - Falha graciosa se `git worktree add` falhar parcialmente? FR-017: best-effort + stderr orientativo. [Spec §FR-017]
- [x] CHK022 - `cp -R + rm -rf` atomico OU erro sinalizado? FR-017: erro sinalizado + cleanup orientado via `cstk session end --force`. [Spec §FR-017]

## Logging e Observabilidade Segura

- [x] CHK023 - NENHUM token/credencial em logs? cstk nao gera logs proprios; gh handle proprio output. [Premissa, contracts §pr]
- [x] CHK024 - Mensagens vazam paths absolutos? Sim, mostram path completo (`/home/jot/Projects/...`). Aceitavel para uso solo CLI; nao ha risco de exposure publico nao-controlada. [Spec §FR-014]

## Conformidade

- [x] CHK025 - Constitution II 1.1.0 (gh) cumpre (a)(b)(c)? Sim — plan §Constitution Check declara individualmente cada condicao. [Constitution, plan.md]
- [x] CHK026 - Constitution IV (zero coleta remota)? Sim — plan declara que `gh pr create` e fetch para repo do usuario sob comando explicito; nao telemetria. [Constitution, plan.md]

## Notes

- Marcar items concluidos com `[x]`
- `[Gap]` = ausencia que pode requerer FR adicional ou clarificacao
- Itens de defesa em profundidade podem ser revisitados apos primeiro draft
