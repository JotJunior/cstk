# Implementation Plan: Escopar `backups/` na rotacao de round

**Feature**: `round-scoped-backups` | **Date**: 2026-08-21
**Spec**: [spec.md](./spec.md) | **Research**: [research.md](./research.md)
**Data model**: [data-model.md](./data-model.md) |
**Contract delta**: [contracts/state-rounds-backups.md](./contracts/state-rounds-backups.md) |
**Quickstart**: [quickstart.md](./quickstart.md)

## Summary

Corrigir a issue #150: hoje `state-rounds.sh rotate` move apenas o estado
transacional para `rounds/<label>/` e deixa `backups/` na raiz do state-dir; a
execucao nova (pos-reabertura) reinicia a numeracao em `wave-001.json` e
**sobrescreve** os snapshots do round anterior, destruindo trilha de auditoria.

Abordagem (research.md Decision 1): tornar `backups/` mais um item do **conjunto
movido**, deslocado para dentro do MESMO staging (`rounds/.<label>.staging/`) que
ja acumula o estado transacional, publicado pelo unico `rename(2)` de commit que
ja existe. A atomicidade exigida por FR-001/FR-008 e herdada do desenho atual —
nao ha ponto de commit novo. As mudancas se concentram em quatro pontos de um
unico arquivo (`state-rounds.sh`): montagem do CSV `files` do journal, validacao
J4 do `recover`, predicado de "staging completo" e roll-back tipo-consciente.
Nenhuma assinatura de CLI muda; o formato `ROUND|...` consumido pelo comando pai
permanece byte-compativel.

## Technical Context

**Language/Version**: POSIX `sh` (`#!/bin/sh` + `set -eu`) — inferido do
shebang e do cabecalho de `plugins/cstk/skills/agente-00c-runtime/scripts/state-rounds.sh`
e imposto pelo Principio II da constitution.
**Primary Dependencies**: utilitarios POSIX (`ls`, `mv`, `rm`, `mkdir`, `sed`,
`printf`, `date`). `sqlite3` e `jq` ja sao dep obrigatoria deste script sob o
carve-out do amendment 1.3.0 do Principio II (camada de estado transacional) —
esta feature **nao adiciona nenhuma dep nova**.
**Storage**: filesystem — layout do state-dir
(`.claude/feature-00c-state/<short>/`), com estado transacional em `state.json`
ou `state.db` (backend resolvido por `state-backend.sh`). Sem schema de banco
novo (ver data-model.md).
**Testing**: harness POSIX proprio — `tests/test_state-rounds.sh`, executado por
`./tests/run.sh test_state-rounds` (convencao de `CLAUDE.md` §Como testar
scripts shell; `--check-coverage` exige teste por script).
**Target Platform**: macOS/zsh (dev) e Ubuntu (CI) — fonte: `docs/constitution.md`
Principio II (portabilidade POSIX exigida nos dois ambientes) + cabecalho do
proprio `state-rounds.sh` ("Alvo real: macOS/zsh (dev) e Ubuntu (CI)"); ver dec-012.
**Project Type**: CLI / biblioteca de scripts (skill interna
`agente-00c-runtime`), single-layer.
**Performance Goals**: N/A — a rotacao ocorre uma vez por reabertura de feature; o
custo dominante e um `rename(2)` de diretorio no mesmo filesystem.
**Constraints**: (a) atomicidade tudo-ou-nada da rotacao; (b) recuperacao por um
unico comando (`recover`); (c) formato de stdout do `rotate` congelado por
consumidor externo (`plugins/cstk/commands/feature-00c.md` §2.bis passo 7.c);
(d) zero bashism, zero GNU-only.
**Scale/Scope**: um arquivo de script alterado, um contrato emendado, um arquivo
de teste estendido (12 cenarios novos, T-17..T-28, + T-15 emendado).

Nenhum `NEEDS CLARIFICATION`: nao ha eixo estrutural aberto (linguagem, stack,
arquitetura, persistencia, plataforma-alvo e tier ja estao fixados pelo projeto e
pelo script existente).

## Constitution Check

*GATE: passou antes do Phase 0; re-checado apos Phase 1 (§Re-check).*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (NON-NEGOTIABLE) | PASS | A correcao percorre a pipeline SDD completa (spec ratificada + clarify + este plan); o contrato afetado e emendado, nao contornado. |
| II. POSIX sh puro, zero dep externa (NON-NEGOTIABLE) | PASS | Codigo novo usa apenas `ls -A1`, `mv --`, `[ -d ]`, `[ -L ]`, `[ -e ]` — todas construcoes ja presentes no repo e exercitadas no CI dos dois alvos (`ls -1 --` no proprio `state-rounds.sh`/`_sr_next_label`; `ls -A` em `tests/test_feature-00c-preflight.sh`). Nenhum bashism, nenhum `local`, nenhum array. Nenhuma dep nova: `sqlite3`/`jq` ja eram dep deste script pelo carve-out do amendment 1.3.0. Gate executavel: cenario T-16 (`shellcheck -s sh`). |
| III. Formato canonico de skill | N/A | Nenhuma SKILL.md alterada; a mudanca e em script do runtime interno. |
| IV. Zero coleta remota (NON-NEGOTIABLE) | PASS | Operacao 100% local em filesystem; nenhuma chamada de rede introduzida. |
| V. Profundidade acima de metricas | PASS | A feature elimina uma classe de perda silenciosa de dados; o roll-back tipo-consciente (Decision 5) troca um sucesso falso por falha diagnosticavel. |
| VI. Veracidade de dados — zero fabricacao (NON-NEGOTIABLE) | PASS | Todo comportamento afirmado nos artefatos foi lido no arquivo citado ou verificado empiricamente (o aninhamento do `mv` de diretorio esta transcrito literalmente em research.md Decision 5). Emendas ainda nao aplicadas estao marcadas `[PROPOSTA]` no contract delta. |

Sem violacoes ⇒ **Complexity Tracking vazio** (ver §Complexity Tracking).

## Project Structure

### Documentation (this feature)

```
docs/specs/round-scoped-backups/
├── spec.md                              # ratificada + clarificada
├── plan.md                              # este arquivo
├── research.md                          # Phase 0 — 8 decisoes
├── data-model.md                        # Phase 1 — layout + journal
├── quickstart.md                        # Phase 1 — T-17..T-28
└── contracts/
    └── state-rounds-backups.md          # Phase 1 — delta do contrato base
```

### Source Code (repository root)

Arquivos REAIS tocados por esta feature:

```
plugins/cstk/skills/agente-00c-runtime/scripts/
└── state-rounds.sh                      # ALTERADO — 4 pontos (ver §Pontos de mudanca)

docs/specs/feature-reopen/contracts/
└── state-rounds.md                      # EMENDADO — conjunto movido, nunca movidos,
                                         #   sequencia, matriz do recover, G8, T-06

tests/
└── test_state-rounds.sh                 # ESTENDIDO — T-17..T-28; T-15 emendado
```

Arquivos REAIS **conferidos e nao alterados** (FR-007 / Decision 7):

```
plugins/cstk/agents/agente-00c-feature-orchestrator.md   # passo 8 do Loop: for-backup > backups/wave-NNN.json
plugins/cstk/agents/agente-00c-orchestrator.md           # mesma prosa de fechamento de onda
mcp/state-server/src/tools/close_wave.ts                 # backupDir = join(session.stateDir, "backups")
plugins/cstk/commands/feature-00c-abort.md               # snapshot no abort + rm -rf -- "$SD/backups"
plugins/cstk/commands/feature-00c.md                     # consumidor da linha ROUND|... (2.bis, passo 7.c)
```

Nenhum script do runtime (`plugins/cstk/skills/agente-00c-runtime/scripts/*.sh`)
escreve em `backups/` — verificado por grep; os escritores sao os quatro acima.

**Structure Decision**: mudanca confinada a um unico script + seu contrato + seu
teste. Nao ha modulo novo, nem helper novo, nem arquivo novo de runtime — a
primitiva de rotacao ja e o lugar arquitetural correto para a semantica "o que
pertence a um round".

## Convencoes de Borda

**N/A — single-layer.** A feature vive inteiramente dentro de um script POSIX que
manipula filesystem; nao ha borda backend↔frontend, DB↔backend nem broker↔consumer,
logo nao ha convencao de case style, DTO ou validacao de payload a declarar.

A unica fronteira de dados relevante e **script ↔ comando pai**, e ela e explicita
e congelada: a linha `ROUND|<label>|<backend>|<state_file>|<execution_id>|<status>`
em stdout, consumida por `plugins/cstk/commands/feature-00c.md` (§2.bis, passo 7.c).
Fonte da verdade: o bloco `printf 'ROUND|%s|%s|%s|%s|%s\n' ...` ao fim do `rotate`
em `state-rounds.sh`. Regressao coberta pelo cenario T-17 passo 4.

## Pontos de mudanca em `state-rounds.sh`

Quatro pontos, todos localizados por nome de funcao/bloco (nao por numero de
linha, que muda com a edicao):

| # | Local | Mudanca | FR |
|---|-------|---------|-----|
| P1 | bloco de montagem do backend/`_RT_FILES_CSV` no `rotate` (`# backend + arquivos transacionais`) | apos montar o CSV transacional, avaliar elegibilidade de `backups` (existe && nao-symlink && `ls -A1` nao-vazio) e anexa-lo ao fim do CSV | FR-001, FR-006 |
| P2 | guardas pre-escrita do `rotate` (junto do bloco `# G4 (pre): state-dir nao-symlink`) + passo `f` (laco de `mv`) | G8: recusar (exit `1`) se `<state-dir>/backups` for symlink, com **re-assercao imediatamente antes do `mv`** (janela TOCTOU) e assercao `[ -d ] && [ ! -L ]` no staging apos o `mv`; G9: `chmod 700` best-effort no `backups/` dentro do staging | FR-001 |
| P3 | `_sr_staging_complete` | predicado por tipo: `[ -d ]` para `backups`, `[ -f ]` para os demais | FR-004 |
| P4 | `recover`: validacao J4 (`case "$_rc_f" in ...`) + ramo `rollback` | J4 admite o literal `backups`; roll-back de diretorio assere destino inexistente antes do `mv` e falha exit `1` se existir (anti-aninhamento) | FR-004, FR-008 |

O ramo `forward` do `recover` **nao muda**: ele opera sobre o staging inteiro
(`mv -- "$_rc_staging" "$_rc_target"`), agnostico ao conteudo. O passo `f` do
`rotate` tambem nao muda estruturalmente — o mesmo laco sobre o CSV passa a
iterar uma entrada a mais, e `mv --` move diretorio tao bem quanto arquivo
quando o destino nao existe (que e o caso dentro do staging recem-criado).

## Ordem de implementacao sugerida

1. **P2 + P1** (guarda antes de habilitar o movimento) — com T-25, T-19, T-20 como
   gate: a elegibilidade nasce protegida contra symlink e contra dir vazio.
2. **T-15 emendado** — remove a assercao que contradiz FR-001, senao a suite fica
   vermelha durante toda a implementacao e perde valor de sinal.
3. **T-17, T-18** — happy path e nao-colisao entre rounds (o valor de negocio da
   issue #150).
4. **P3 + P4** — recuperacao tipo-consciente, com T-21, T-22, T-23, T-24.
5. **T-26, T-27** — regressoes de fronteira (purge do abort; `list`).
6. **Emenda do contrato base** + comentario T-06 no script.
7. `./tests/run.sh test_state-rounds` verde + `shellcheck -s sh` (T-16).

## Riscos e mitigacoes

| Risco | Impacto | Mitigacao |
|-------|---------|-----------|
| `mv` de diretorio sobre destino existente **aninha** silenciosamente (verificado em `Darwin`) | roll-back "bem-sucedido" deixando `backups/backups/` e state-dir corrompido | P4: assercao `[ ! -e ]` antes do `mv`; falha exit `1`; cenario T-23 com assercao anti-aninhamento explicita |
| J4 relaxada por engano (padrao/glob em vez de literal) | journal adulterado poderia mover caminhos arbitrarios | P4 mantem `case` por literais; T-24 exercita o controle negativo (`../../etc/passwd`) **e** o positivo (`backups`) |
| `backups/` volumoso aumenta a janela entre primeiro `mv` e commit | maior chance de interrupcao no meio | janela ja e coberta pelo journal; `backups` e a ULTIMA entrada do CSV, entao a interrupcao mais provavel cai no caso roll-back simples (T-22) |
| Divergencia macOS x Ubuntu no `ls -A1` de dir vazio | falso "nao-vazio" criaria `backups/` vazio no round | construcao com precedente no repo em codigo ja exercitado nos dois ambientes (`tests/test_feature-00c-preflight.sh` usa `ls -A` como teste de dir vazio); T-20 roda nos dois pelo CI |
| Contrato base e teste T-15 continuarem afirmando o oposto de FR-001 | documentacao mentindo + suite vermelha | itens 2 e 6 da ordem de implementacao; FR-003 cobre o contrato |
| Consumidor da linha `ROUND\|...` quebrar por campo novo | `/feature-00c --reopen` falha no passo 7.c | nenhum campo adicionado; T-17 passo 4 asserta a linha exata |
| TOCTOU entre a checagem G8 e o `mv` de `backups` (atacante local com escrita no state-dir troca o dir por symlink) | round preserva um symlink em vez dos snapshots | G8 re-assertada imediatamente antes do `mv` + assercao `[ -d ] && [ ! -L ]` no staging apos o `mv`. Nao permite escrita fora do state-dir: `mv` desloca o proprio link, nao segue o alvo. Achado do gate `owasp-security` (severidade low, defesa em profundidade). |
| Snapshots preservados com permissoes permissivas | leitura por outro usuario local dentro de `rounds/<label>/backups/` | G9 (`chmod 700` no `backups/` do staging). Conteudo ja filtrado por `secrets-filter.sh for-backup` na escrita; o `chmod 700` do round **nao e recursivo**. Achado do gate `owasp-security` (severidade low). |

## Fora de escopo

| Item | Motivo |
|------|--------|
| **Backfill/reparo de rounds ja rotacionados sem snapshots** (o caso real da issue #150, ondas 1-11 perdidas) | Decisao de clarify registrada na spec §Clarifications: a rotacao de `backups/` e capacidade **nova**; os snapshots daquelas ondas nunca foram movidos para dentro do round e nao existem em nenhuma outra fonte recuperavel — nao ha de onde reparar. Perda historica documentada, sem mecanismo de reconstrucao. |
| Mudanca em qualquer escritor de snapshot | FR-007 exige que continuem gravando em `<state-dir>/backups/wave-NNN.json`. |
| Guarda defensiva nova no `--purge-backups` | O path ja e derivado de `AGENTE_00C_STATE_DIR` e nao alcanca `rounds/`; cobertura passa a ser por teste (T-26), nao por codigo novo (research.md Decision 7). |
| Compactacao/rotacao por retencao dos snapshots dentro dos rounds | Nao esta na spec; rounds crescem monotonicamente por desenho da `feature-reopen`. |
| Fechar o limite conhecido de G6 (lock com liveness fraca) | Divida ja registrada no contrato base (`feature-reopen`), independente desta feature. |

## Complexity Tracking

> Preencher APENAS se Constitution Check tem violacoes que precisam justificativa.

**Vazio** — nenhuma violacao de principio. A feature nao adiciona dependencia,
arquivo, camada nem servico; amplia por um literal um conjunto ja existente e
adiciona uma guarda de simetria (G8) a uma tabela de guardas ja estabelecida.

## Re-check pos-Phase 1

| Pergunta | Resposta |
|----------|----------|
| O design introduziu complexidade nao justificada? | Nao — 4 pontos de edicao num arquivo, sem estrutura nova. A alternativa "campo novo no journal" foi explicitamente rejeitada por criar estado paralelo (research.md Decision 2). |
| Principios MUST continuam respeitados? | Sim — I, II, IV e VI reavaliados apos o design: nenhum bashism/GNU-only proposto, nenhuma rede, nenhuma afirmacao sem fonte, contrato emendado em vez de contornado. |
| Alguma decisao de Phase 1 exigiria emendar a constitution? | Nao. |
