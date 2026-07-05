# Implementation Plan: enforced-guards

**Feature**: `enforced-guards` | **Date**: 2026-07-05 | **Spec**: [spec.md](./spec.md)

## Summary

Tornar **enforced** tres guardas de seguranca hoje **advisory**: (US1)
interceptacao automatica de comandos Bash de execucoes autonomas
`agente-00c`/`feature-00c`, validados contra as regras ja existentes de
`bash-guard.sh`, num ponto que nao depende da prosa do orquestrador lembrar
de chamar a checagem; (US2) verificacao de integridade fail-closed antes de
`cstk serve` executar codigo baixado; (US3) allowlist de hosts confiaveis em
`install`/`self-update`.

**Abordagem tecnica** (da research): US1 usa o hook `PreToolUse` do harness
Claude Code (contrato confirmado via documentacao oficial,
`research.md` Decision 1) — um script novo, casca fina em POSIX sh com `jq`
como dependencia OPCIONAL confinada (carve-out Principio II 1.1.0), que
delega toda decisao de regra ao `bash-guard.sh` ja existente e inalterado.
Ausencia de `jq` ou qualquer falha do proprio hook e tratada pelo MESMO
caminho fail-closed exigido por FR-007. A propagacao do hook a subagentes
spawnados **nao esta confirmada pela documentacao oficial** — tratada como
risco aberto com spike de validacao empirica obrigatorio antes do restante
de US1 (Scenario 0 do quickstart). US2 substitui o ramo "aviso e prossegue"
de `serve.sh` por bloqueio-por-padrao com bypass explicito via flag/env,
auditado. US3 generaliza a allowlist de host ja usada por `serve.sh`
(4 dominios GitHub, fato ja em producao) para `install`/`self-update`. Nenhuma
das tres frentes remove a camada advisory existente (FR-005/FR-015).

## Technical Context

**Language/Version**: POSIX sh puro (shebang `#!/bin/sh`, `set -eu`) —
Principio II NON-NEGOTIABLE. Excecao disciplinada: `jq` como dependencia
OPCIONAL confinada a um unico arquivo novo (`pretooluse-bash-guard.sh`), sob
o carve-out formal do amendment 1.1.0 — ver Constitution Check e
`research.md` Decision 2.
**Primary Dependencies**: nenhuma obrigatoria nova. `jq` opcional (ja usado
hoje em `cli/lib/hooks.sh` sob o mesmo carve-out — nao e a primeira vez que
o toolkit aceita essa dependencia opcional).
**Storage**: arquivos texto/JSONL locais no projeto-alvo —
`.claude/enforcement-log.jsonl` (novo, `EnforcementDecisionLog` +
`IntegrityVerificationOutcome`), `.claude/agente-00c-whitelist` /
`.agente-00c-whitelist.txt` (ja existentes, reusados sem mudanca). Nenhum
banco de dados, nenhuma escrita em `state.json` a partir do hook (Decision 5
— separacao deliberada do dado transacional SDD).
**Testing**: harness do repo (`tests/run.sh`). Novo:
`tests/test_pretooluse-bash-guard.sh` (script novo mapeia 1:1, convencao do
`CLAUDE.md`), extensoes em `tests/cstk/test_install.sh`,
`tests/cstk/test_self-update.sh`, `tests/cstk/test_serve.sh`, novo
`tests/cstk/test_trusted-hosts.sh`. Fixtures de hook: simular stdin JSON via
`printf '%s' "$json" | ./pretooluse-bash-guard.sh` (sem depender do harness
real rodando em CI).
**Target Platform**: CLI local (`cstk`) + harness Claude Code (hook), macOS/
Linux POSIX sh — mesmo alvo do restante do toolkit.
**Project Type**: cli / hook script (extensao de scripts shell existentes +
1 script novo de hook + settings.json snippet).
**Performance Goals**: hook nao MUST adicionar atraso perceptivel a comandos
permitidos (FR-003/SC-004) — `bash-guard.sh` ja e rapido (grep/case puro,
sem I/O de rede); orcamento informal: hook completo (parse + delegate +
log) sob ~200ms no caso comum, dentro do timeout de hook proposto (5s,
`GuardHookRegistration.timeout`, larga margem).
**Constraints**: hook MUST ser fail-closed em qualquer falha interna
(FR-007); MUST NOT introduzir segundo mecanismo de distribuicao (FR-017);
MUST preservar 100% do comportamento advisory existente (FR-005/FR-015).
**Scale/Scope**: uso local de 1 operador por projeto-alvo — sem
concorrencia multi-usuario a considerar (mesmo perfil de escala do restante
do toolkit).

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checar apos Phase 1.*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (NON-NEGOTIABLE) | PASS | feature entrou via `specify` → `clarify` (2 rodadas, block-001 resolvido) → `plan` (este documento); `create-tasks`/`execute-task` seguem depois. |
| II. POSIX sh puro (NON-NEGOTIABLE) | PASS (via carve-out 1.1.0) | `pretooluse-bash-guard.sh` usa `jq` como dependencia OPCIONAL confinada a esse unico arquivo, com fallback fail-closed testavel — as 3 condicoes cumulativas do carve-out estao satisfeitas e documentadas em `research.md` Decision 2. `bash-guard.sh`/`path-guard.sh` existentes permanecem 100% POSIX puro, inalterados. Demais scripts tocados (`install.sh`, `self-update.sh`, `serve.sh`, novo `trusted-hosts.sh`) continuam POSIX puro sem dependencia nova. |
| III. Formato canonico de skill | N/A | feature nao cria skill nova nem altera `SKILL.md` existente; adiciona subpasta `hooks/` a uma skill ja existente (`agente-00c-runtime`), consistente com Principio III (conteudo pesado em subpasta, carregado sob demanda pelo mecanismo de instalacao). |
| IV. Zero coleta remota (NON-NEGOTIABLE) | PASS | nenhum dado sai da maquina do operador; `enforcement-log.jsonl` e local; a allowlist de hosts (US3) e sobre ORIGEM de download ja necessario (release do proprio toolkit/painel), nao telemetria. |
| V. Profundidade sobre adocao | PASS | feature fecha uma lacuna de seguranca real (gap fail-open observado em `serve.sh`) em vez de perseguir feature vistosa; reusa mecanismos existentes (`bash-guard.sh`, `merge_settings`, allowlist de `serve.sh`) em vez de reinventar. |
| VI. Veracidade de Dados (NON-NEGOTIABLE) | PASS | todo contrato de interface externa citado (schema do hook `PreToolUse`) tem fonte oficial citada (`research.md` Decision 1); a lista de hosts (US3) e fato ja em producao (`serve.sh:31`), nao invencao; a propagacao do hook a subagentes foi o unico ponto sem fonte documental confirmavel — tratada como RISCO ABERTO com spike de validacao empirica obrigatorio (Decision 4), e RESOLVIDA por observacao direta na task 1.1 (2026-07-05: INTERCEPTADO, evidencia em `research.md` Decision 4) antes de qualquer afirmacao de cobertura. |

## Project Structure

### Documentation (this feature)

```
docs/specs/enforced-guards/
├── spec.md
├── plan.md          # This file
├── research.md       # Phase 0 output
├── data-model.md      # Phase 1 output
├── quickstart.md       # Phase 1 output
└── contracts/           # Phase 1 output
    ├── pretooluse-hook.md
    ├── enforcement-log.md
    └── trusted-hosts.md
```

### Source Code (repository root)

```
global/skills/agente-00c-runtime/
├── scripts/
│   ├── bash-guard.sh          # existente, INALTERADO (regra de negocio)
│   └── path-guard.sh          # existente, INALTERADO (fora do escopo de US1 — spec cobre so Bash)
└── hooks/                     # [PROPOSTA] novo, subpasta da skill existente
    ├── pretooluse-bash-guard.sh   # novo — casca fina, delega a bash-guard.sh
    └── settings.snippet.json      # novo — trecho "hooks"."PreToolUse" a mesclar

cli/lib/
├── hooks.sh            # existente — ganha nova funcao apply_guard_hooks() (Decision 9)
├── install.sh           # existente — _install_apply_hooks_if_needed ganha 2o ramo (skill agente-00c-runtime, nao so language-*)
├── update.sh             # existente — ganha chamada equivalente (hoje NAO toca hooks, achado da research)
├── self-update.sh         # existente — _su_resolve_urls ganha checagem de host (US3)
├── serve.sh                # existente — bloco fail-open (linhas 213-215) vira fail-closed + flag --allow-unverified (US2)
├── list.sh                  # NAO tocado nesta feature (achado colateral fora do escopo, ver research.md Decision 7)
└── trusted-hosts.sh          # [PROPOSTA] novo — constante compartilhada + funcao de checagem (US3, Decision 7)

tests/
├── test_pretooluse-bash-guard.sh   # novo
└── cstk/
    ├── test_install.sh              # existente, extensao (US3 + US1 provisioning)
    ├── test_self-update.sh           # existente, extensao (US3)
    ├── test_update.sh                 # existente, extensao (provisioning do hook, Decision 9)
    ├── test_serve.sh                   # existente, extensao (US2)
    └── test_trusted-hosts.sh            # novo
```

**Structure Decision**: reusar a arvore existente ao maximo — novo codigo
concentrado em (a) uma subpasta `hooks/` dentro da skill `agente-00c-runtime`
ja existente (evita novo mecanismo de distribuicao, FR-017) e (b) extensoes
pontuais em arquivos `cli/lib/*.sh` ja responsaveis pelo comportamento que
cada US modifica. Nenhum diretorio novo de top-level.

## Convencoes de Borda

N/A — single-layer (scripts CLI + hook local do harness). Sem borda
backend↔frontend, sem API HTTP propria, sem SPA consumindo payload desta
feature.

## Complexity Tracking

> Preenchido apenas para o unico ponto do Constitution Check com nota de
> carve-out (Principio II), conforme praticado por `docs/specs/_archived/cstk-cli/plan.md`
> (primeiro precedente do mesmo carve-out).

| Violacao (carve-out, nao violacao pura) | Por Que Necessario | Alternativa Simples Rejeitada Porque |
|----------|-------------------|--------------------------------------|
| `jq` como dependencia opcional em `pretooluse-bash-guard.sh` | O hook recebe JSON aninhado (`.tool_input.command`) via stdin — contrato do harness, nao escolha do toolkit; POSIX puro nao tem parser JSON confiavel para extrair um campo aninhado com escaping arbitrario | Parsing via `grep`/`sed`/`awk` ad-hoc: rejeitado porque uma extracao incorreta do comando e exatamente o furo de seguranca que a feature existe para fechar — fragilidade inaceitavel numa camada de enforcement. Fundir o parsing dentro de `bash-guard.sh` (que so recebe `--command` ja extraida): rejeitado, quebraria a condicao (b) do carve-out (confinamento a um unico arquivo) e acoplaria o guard reusavel-por-prosa ao contrato do harness. |

## Threat Model (achado do gate `owasp-security`)

**O que esta feature protege**: o orquestrador/modelo (agente-00c/feature-00c)
emitindo um comando Bash perigoso por lapso, instrucao manipulada (prompt
injection) ou condicao de borda — sem depender da prosa do orquestrador
lembrar de chamar a checagem (o problema central que a spec descreve).

**O que esta feature NAO protege (fora do threat model, MUST estar
explicito)**: um operador (ou qualquer processo com o mesmo nivel de acesso
de escrita do operador ao projeto-alvo) que edite deliberadamente
`.claude/settings.json`/`settings.local.json` para remover ou neutralizar o
hook `PreToolUse`. Quem tem esse acesso poderia igualmente editar
`bash-guard.sh` diretamente hoje — a garantia enforced desta feature e sobre
o COMPORTAMENTO DO MODELO dentro de uma configuracao ja provisionada
corretamente, nao uma defesa contra adulteracao deliberada da propria
configuracao de seguranca por quem ja tem acesso local equivalente ao do
operador. Nenhuma mitigacao adicional e proposta para esse vetor nesta
feature (research.md Decision 11) — documentado para nao alegar uma garantia
mais forte do que a real (mesmo espirito do Acceptance Scenario 3 de US1).

**Achados do gate tratados como MUST resolvido neste plano** (nao adiados):

- `enforcement-log.jsonl` MUST filtrar o campo `command` via
  `secrets-filter.sh scrub` antes do append (Decision 10) — comandos
  bloqueados frequentemente carregam credenciais em texto puro.
- Checagem de host (US3/`trusted-hosts.md`) MUST ser por igualdade EXATA do
  componente authority (userinfo removido, case-insensitive), nunca por
  substring — previne bypass por host confusable (CWE-290).
- Bypass de integridade em `cstk serve` (US2/Decision 6) MUST emitir aviso de
  alta visibilidade em stderr toda vez que disparar (flag ou env var), para
  que uma env var esquecida setada permanentemente nao vire fail-open
  silencioso.

## Riscos e Unknowns em aberto (nao bloqueantes para `create-tasks`, mas MUST ser a primeira task)

1. ~~Propagacao do hook `PreToolUse` a subagentes spawnados — nao confirmada
   pela documentacao oficial~~ **RESOLVIDO (spike task 1.1, 2026-07-05):
   INTERCEPTADO** — o hook propaga a subagentes spawnados via tool
   Agent/Task; US1 cobre esse caso sem mudanca de design (`research.md`
   Decision 4).
2. **Inconsistencia pre-existente de nome do arquivo de whitelist**
   (`.claude/agente-00c-whitelist` vs `.agente-00c-whitelist.txt` — Decision 8):
   nao resolvida por esta feature (fora do escopo das FRs); o hook tenta
   ambos os nomes.
3. ~~`enforcement-log.jsonl` sem secrets-filter no campo `command`~~ **MUST
   resolvido neste plano** (nao e mais unknown/pendente) — ver "Achados do
   gate tratados como MUST resolvido neste plano" acima: o campo `command`
   MUST passar por `secrets-filter.sh scrub` antes do append (Decision 10,
   §Threat Model; `contracts/enforcement-log.md`; `data-model.md`). Item
   mantido aqui apenas por rastreabilidade historica do gate que o
   levantou (CHK036) — nao ha acao pendente.
4. **Achados colaterais fora do escopo desta spec** (nao geram task aqui,
   apenas nota para eventual spec futura): `cli/lib/update.sh` e
   `cli/lib/list.sh` aceitam `http://` sem rejeitar (assimetria com
   `install.sh`/`self-update.sh`); nenhuma FR desta spec pede correcao disso.
