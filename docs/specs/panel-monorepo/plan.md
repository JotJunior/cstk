# Implementation Plan: Migracao do painel para dentro do repositorio unico (monorepo)

**Feature**: `panel-monorepo` | **Date**: 2026-08-28 | **Spec**: [spec.md](spec.md)

## Summary

Incorporar o projeto `cstk-panel` ao repositorio `cstk` como subarvore
autocontida em `panel/`, preservando historico (`git subtree`), identidade de
projeto (`cstk-panel` via `--canonical-project`) e governanca propria
(`panel/docs/constitution.md` 2.0.2), enquanto versao e release passam a ser
unicas.

A parte perigosa nao e o `git subtree` — e a **distribuicao**. `cstk serve`
baixa o painel da rede e escolhe o asset por **posicao** ("primeiro `.tar.gz`
com sibling `.sha256`"). Passar a publicar o painel na mesma release do toolkit
faz essa logica pegar o tarball do toolkit, **conferir o checksum com sucesso**
(outcome `verified`, que por desenho nao loga), e so falhar tarde na extracao.
A abordagem tecnica central e, portanto: tornar a selecao **name-aware**
(`cstk-panel-`), e dar rastro auditavel ao caso "checksum conferiu mas o
payload nao era o painel".

Este plano DERIVA do plano de migracao aprovado pelo operador
(`~/.claude/plans/typed-snacking-diffie.md`). As seis decisoes de operador dele
sao insumo, nao objeto de re-decisao. Onde a verificacao empirica divergiu do
insumo, a divergencia esta registrada (dec-020) e o rationale corrigido em
`research.md` Decision 4.

## Technical Context

**Language/Version**: POSIX `sh` (toolkit, `cli/lib/` e
`plugins/cstk/skills/*/scripts/`); TypeScript / Node.js 20.x-24.x (painel,
`panel/`) — ambos herdados, nenhum introduzido
**Primary Dependencies**: toolkit — apenas ferramentas POSIX canonicas
(`awk`, `sed`, `grep`, `tar`, `curl`); painel — npm workspaces
(`apps/server`, `apps/web`, `packages/shared-types`), `better-sqlite3`
**Storage**: N/A para esta feature. Artefatos afetados sao arquivos versionados
e assets de release; a knowledge.db so e tocada na dimensao *identidade de
projeto* (nenhuma migracao de schema)
**Testing**: `./tests/run.sh` (suite POSIX do toolkit, gate bloqueante de
`release.yml:77`); `npm test` / `npm run typecheck` / `npm run build` no painel
**Target Platform**: shell POSIX em macOS/Linux (toolkit); Node.js local
(painel). Inalterado — herdado, nao decidido por esta feature. Fonte:
`docs/constitution.md` Principio II (POSIX sh portavel "em qualquer ambiente
POSIX sem setup") e `panel/package.json` `engines`
**Project Type**: monorepo poliglota — toolkit CLI + dashboard web, projetos
autocontidos lado a lado
**Performance Goals**: N/A — nenhum caminho quente alterado. O predicado de
selecao permanece uma unica passada de `awk` sobre a lista de assets
**Constraints**: (a) POSIX `sh` puro sem dependencia externa nova nas mudancas
de `cli/lib/` (Principio II); (b) zero requisicao de rede nova na UI do painel
(Principio IV); (c) `./tests/run.sh` MUST permanecer verde — e o gate de release
**Scale/Scope**: ~499 arquivos rastreados e 248 commits importados; 8 specs do
painel + 18 do toolkit; 4 arquivos de documentacao a atualizar (lista
verificada por grep, dec-023) + 2 a revisar; 3 modos de stub + 3 cenarios
novos em `tests/cstk/test_serve.sh`, mais 1 teste de drift em arquivo
proprio sob `tests/cstk/`

**NEEDS CLARIFICATION restantes**: 0. Nenhum eixo estrutural (linguagem/
runtime, stack, arquitetura, persistencia, ambiente-alvo, tier de entrega) ficou
em aberto — todos herdados ou ja fixados pelo operador no plano aprovado.

## Constitution Check

*GATE: passou antes do Phase 0. Re-checado apos Phase 1 (§Re-check).*

Constituicao avaliada: `docs/constitution.md` do projeto-alvo `cstk`,
**versao 1.3.0** (Ratified 2026-04-20, Last Amended 2026-07-30).
Nao e a do painel (2.0.2, que governa `panel/` e permanece intocada).

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD aplica-se recursivamente (NON-NEGOTIABLE) | PASS | A feature esta no pipeline completo (`spec.md` + `clarify` + este `plan.md` + tasks a seguir). Ha mudanca de CONTRATO de skill/CLI — o predicado de selecao de asset e o enum de `outcome` do enforcement-log — logo exige `spec.md` (existe) + bump de versao no CHANGELOG + nota de BREAKING se aplicavel; ambos previstos como tarefas. |
| II. Scripts POSIX sh puros, zero dep externa (NON-NEGOTIABLE) | PASS | Mudancas em `cli/lib/serve.sh` permanecem `#!/bin/sh` + `set -eu`, sem Bash-isms. O predicado name-aware e uma condicao adicional no `awk` ja existente. O teste de drift de Node majors le `panel/package.json` com `awk`, **nao** com `jq` — o carve-out 1.3.0 de dep obrigatoria e restrito a camada de estado transacional e a clausula (a) veda propagar a dep a outras partes do toolkit. Nenhuma dep nova. |
| III. Formato canonico de skill (progressive disclosure, gotchas, trigger) | N/A | Nenhuma `SKILL.md` e criada ou alterada por esta feature. |
| IV. Zero coleta remota de uso ou dados (NON-NEGOTIABLE) | PASS | Ponto de atencao real: FR-022 exige aviso na UI do painel. Resolvido como banner **estatico embutido no bundle** — sem feature-flag remoto, sem fetch a API de releases, funcional offline (dec-022, `research.md` Decision 6). `CSTK_PANEL_REPO` altera `owner/repo` de uma URL de **download**, nao introduz endpoint de telemetria, e o host segue preso a allowlist constante. |
| V. Profundidade e reducao de retrabalho acima de metricas de adocao | PASS | A feature e exatamente reducao de retrabalho: elimina duas PRs / duas releases / ordem de merge manual por mudanca cross-projeto, e converte a duplicacao de `_SERVE_SUPPORTED_NODE_MAJORS` em espelho verificado por gate. Nada aqui persegue visibilidade. |
| VI. Veracidade de dados — zero fabricacao (NON-NEGOTIABLE) | PASS | Todo fato afirmado em `research.md`, `data-model.md`, `contracts/` e `quickstart.md` cita arquivo e linha do repositorio ou resultado de sonda executada. Itens de contrato desenhados (ainda inexistentes) estao marcados `[PROPOSTA]`, distintos dos `[ATUAL]`. A unica afirmacao do plano-insumo que nao resistiu a verificacao foi contestada com sonda e corrigida, nao propagada (dec-020). |

**Resultado**: nenhum FAIL em principio MUST. Gate de constitution liberado.

**Gate `owasp-security` (pos-design)**: 0 critical, **4 high**, 5 medium, 3 low.
Tres achados foram incorporados ao design nesta mesma onda (nome exato em vez de
prefixo; validacao de `CSTK_PANEL_REPO`; validacao pre-extracao do tarball — ver
`research.md` Decision 12 e `contracts/serve-asset-selection.md` §7-§8). Dois
achados `high` sao de **postura de seguranca pre-existente** que esta feature
amplia ou herda (ausencia de attestation/assinatura no par asset+`.sha256`;
`curl -fsSL` seguindo redirect com allowlist checada so na URL pre-redirect, em
`cli/lib/http.sh`) e foram escalados como BloqueioHumano — a tabela de gates
exige decisao do operador para finding `high` em gate de seguranca. O operador
respondeu **aceitar o risco com rastro** (block-002 / dec-029); os termos do
aceite, com o argumento de raio de dano e as issues abertas, estao em
**§Achados residuais aceitos** e sao parte normativa deste plano.

## Convencoes de Borda

A feature atravessa fronteiras (workflow de release -> tarball -> `serve` ->
arvore extraida -> painel). As convencoes de nome e formato sao o contrato, e
cada uma tem **uma** fonte da verdade:

| Camada | Convencao | Validacao | Fonte da verdade |
|--------|-----------|-----------|------------------|
| Nome de asset de release | `cstk-<bare>.tar.gz` (toolkit), `cstk-panel-<bare>.tar.gz` (painel) | passo "Verify build artifacts" do workflow + cenario `both-pairs` | `.github/workflows/release.yml` |
| Par de integridade | `<asset>` + `<asset>.sha256`, igualdade de string completa | `_serve_download_verify_extract` | `cli/lib/serve.sh` |
| Discriminador de asset | nome **exato** `cstk-panel-<bare>.tar.gz`, derivado de `tag_name`, comparado por **igualdade** sobre o basename (nunca prefixo, nunca substring de URL) | cenarios `both-pairs` / `toolkit-only` (matriz de decisao, incl. o caso `cstk-panel-docs-*`, em `contracts/serve-asset-selection.md` §3.3) | `contracts/serve-asset-selection.md` §3.2 |
| Estrutura do tarball | um diretorio de topo `cstk-panel-<bare>/`, com `package.json` + `package-lock.json` na raiz | `serve.sh:488`, `serve-docker.sh:356` | `git archive --prefix=... HEAD:panel` |
| Host de download | allowlist constante, nao-configuravel por env | `trusted_host_check` | `cli/lib/trusted-hosts.sh:47` |
| Origem (owner/repo) | `CSTK_PANEL_REPO`, default `JotJunior/cstk` | composicao de string com host fixo | `cli/lib/serve.sh` |
| Faixa de Node suportada | `20 22 23 24` | teste de drift novo (`awk` sobre `engines.node`) | `panel/package.json` (**unica** fonte; a constante e espelho verificado) |
| `outcome` do enforcement-log | enum textual, consumido por `source` | cenario `wrong-payload` | `contracts/serve-asset-selection.md` §5 |
| Identidade de projeto | `cstk-panel` congelado na camada 1 | Cenario 9 do quickstart | `.execution.canonical_project` |
| Versao de release | tag SemVer unica; painel e seus 3 workspaces em lockstep | `validate-plugin-manifests.sh --strict` (MP-5) para os manifestos do toolkit | tag do git |

**Mapper layer**: N/A — nao ha mapeamento DB<->DTO nesta feature.
**Validacao Zod**: N/A — nenhuma borda de payload JSON e introduzida ou alterada.

## Project Structure

### Documentation (this feature)

```
docs/specs/panel-monorepo/
├── spec.md                              (existente)
├── plan.md                              (este arquivo)
├── research.md                          Phase 0 — 12 decisoes
├── data-model.md                        Phase 1 — entidades e transicoes
├── quickstart.md                        Phase 1 — 16 cenarios
└── contracts/
    └── serve-asset-selection.md         Phase 1 — contrato de selecao/integridade
```

### Source Code (repository root)

Arvore real do `cstk` (verificada), com os pontos tocados marcados:

```
.
├── .github/workflows/release.yml        [MODIFICAR] passo de empacotamento do painel
├── .gitignore                           [MODIFICAR] ancorar `/.claude` (e `/CLAUDE.md`)
├── .gitattributes                       [NOVO] export-ignore de panel/.claude e panel/.github
├── .claude/settings.local.json          [MODIFICAR] escopar hook de shellcheck
├── CHANGELOG.md                         [MODIFICAR] historico unico a partir daqui
├── README.md                            (sem mencao ao painel — nao tocar)
├── cli/
│   ├── install.sh                       (referencia de paridade: CSTK_REPO)
│   ├── README.md / README.pt-BR.md      [MODIFICAR] origem do painel
│   └── lib/
│       ├── serve.sh                     [MODIFICAR] origem + selecao + FR-009
│       ├── serve-docker.sh              (guard fail-closed — inalterado)
│       ├── trusted-hosts.sh             (allowlist — inalterada)
│       └── recall.sh                    (derivacao canonica — inalterada)
├── docs/
│   ├── constitution.md                  (1.3.0 — inalterada)
│   ├── cstk-serve.md / .pt-BR.md        [MODIFICAR] origem do painel
│   ├── agente-00c.md / .pt-BR.md        (sem mencao ao painel — nao tocar)
│   ├── cstk-panel/*-brief.md            [REVISAR] descrevem o painel como projeto externo
│   └── specs/panel-monorepo/            (artefatos desta feature)
├── plugins/cstk/
│   ├── commands/feature-00c.md          [MODIFICAR] --canonical-project
│   ├── commands/agente-00c.md           [MODIFICAR] --canonical-project
│   ├── agents/agente-00c-orchestrator.md [MODIFICAR] EXCLUDE_FEATURE (mesma entrega)
│   └── skills/agente-00c-runtime/scripts/
│       ├── pipeline.sh                  (constitution-conflict — inalterado)
│       └── state-rw.sh                  (--canonical-project — ja suportado)
├── scripts/
│   ├── build-release.sh                 (empacotador do toolkit — inalterado)
│   └── validate-plugin-manifests.sh     (lockstep MP-5 — inalterado)
├── tests/
│   ├── run.sh                           (gate de cobertura — inalterado)
│   └── cstk/
│       ├── test_serve.sh                [MODIFICAR] 3 modos + 3 cenarios novos
│       └── test_serve-docker.sh         (revalidar URLs/nomes fixados)
├── mcp/state-server/                    (precedente de projeto npm autocontido)
└── panel/                               [NOVO] subarvore importada
    ├── package.json                     workspaces, engines 20.x||22.x||23.x||24.x
    ├── package-lock.json                exigido por serve-docker.sh:356
    ├── .gitignore                       excecoes de .claude ja presentes
    ├── .github/workflows/release.yml    [REMOVER] publicacao passa ao cstk
    ├── CHANGELOG.md                     historico congelado + nota
    ├── docs/constitution.md             2.0.2 — governanca propria
    ├── docs/specs/                      8 specs proprias
    ├── .claude/                         173 arquivos versionados
    ├── apps/{server,web}/
    ├── packages/shared-types/
    └── scripts/readonly-check.sh        unico .sh do painel
```

**Structure Decision**: `panel/` como subarvore autocontida na raiz, ao lado de
`cli/`, `mcp/` e `plugins/` — decisao do operador, com precedente interno em
`mcp/state-server/` (projeto npm autocontido dentro do repo). O painel **nao**
e fundido a estrutura da raiz: mantem `package.json`, `docs/specs/`,
`docs/constitution.md` e `.gitignore` proprios (FR-002). Nenhum diretorio
existente e movido — mover `plugins/`, `cli/lib/` ou `tests/` quebraria o gate
de cobertura de `tests/run.sh`, que assume esses caminhos; **acrescentar**
`panel/` nao quebra, porque a varredura e restrita a
`plugins/cstk/skills/*/scripts/*.sh` e `cli/lib/*.sh` com `-maxdepth 1`.

## Ordem de execucao e dependencias

A ordem importa por seguranca, nao por conveniencia. Duas restricoes duras:

1. **`serve.sh` corrigido MUST preceder a primeira release que publique os dois
   pares.** Publicar primeiro exporia toda instalacao atualizada ao defeito de
   selecao posicional.
2. **FR-019**: a automacao de release do `cstk-panel` so e desativada, e o
   repositorio so e arquivado, depois de (a) release-ponte publicada pelo fluxo
   normal (tag -> workflow, nunca artefato manual) e (b) distribuicao embutida
   publicada **e verificada** pelo Cenario 1.

```
1. subtree add + .gitignore ancorado + colisoes de topo     (FR-001..FR-004, FR-006)
2. serve.sh: CSTK_PANEL_REPO validado + selecao name-bound  (FR-008, FR-012, FR-013)
   + validacao pre-extracao + wrong-payload-blocked          (FR-009)
   + testes (3 modos novos)                                  (FR-014)
        |  <-- ./tests/run.sh MUST estar verde aqui
3. release.yml: empacotar e publicar o par do painel         (FR-010, FR-011)
   + .gitattributes export-ignore + assercao de membros      (endurecimento)
4. versao unificada + lockstep dos 3 workspaces              (FR-015, FR-016)
5. ENSAIO DE RELEASE ponta-a-ponta (quickstart Cenario 1)    <-- prova de (b)
6. documentacao (6 arquivos)                                 (FR-017)
7. --canonical-project nos commands + EXCLUDE_FEATURE        (FR-020, FR-021)
8. release-ponte no cstk-panel, com banner na UI             (FR-018, FR-022)
9. desativar automacao + arquivar                            (FR-005, FR-019)
```

O passo 5 e o unico ponto do plano que **prova** a correcao no caminho real; os
passos 8 e 9 sao bloqueados por ele.

## Complexity Tracking

Nenhuma violacao de principio constitucional a justificar — todas as linhas do
Constitution Check sao PASS ou N/A.

Registra-se, por transparencia, uma **divida herdada e nao resolvida** por esta
feature: o painel nao tem CI de testes, e o `cstk` nao roda os testes de
`mcp/state-server` em nenhum workflow. A fusao herda a lacuna. A spec
(§Clarifications, Q2) decidiu explicitamente que os workflows do painel
permanecem em `panel/.github/workflows/` sem execucao automatica, como
constatacao do estado herdado — nao como nova obrigacao desta migracao.
Fechar essa lacuna e feature propria.

## Achados residuais aceitos (block-002 / dec-029)

Dois achados `high` do gate `owasp-security` **nao sao corrigidos por esta
feature**. Foram escalados ao operador e o aceite foi explicito: prosseguir,
com rastro. Esta secao e o rastro — nao um apendice de bloqueio.

**O que os dois achados sao, e por que ficam:**

| # | Achado | Onde | Issue |
|---|--------|------|-------|
| R1 | O par `<asset>` + `<asset>.sha256` prova **integridade**, nunca **proveniencia**: quem consegue publicar o asset publica o hash junto. Nao ha attestation nem assinatura. | `cli/lib/serve.sh` (`_serve_download_verify_extract`) | [#177](https://github.com/JotJunior/cstk/issues/177) |
| R2 | `curl -fsSL` segue redirect, e a allowlist de hosts e checada **apenas na URL pre-redirect**. O destino final nunca e revalidado. | `cli/lib/http.sh:50`, allowlist em `cli/lib/trusted-hosts.sh:47` | [#178](https://github.com/JotJunior/cstk/issues/178) |

**Os dois sao PRE-EXISTENTES e ortogonais a migracao.** A fusao nao cria
nenhuma das duas lacunas: elas ja governam hoje o download do toolkit. O que a
migracao muda e o **raio de dano**:

> Hoje, um comprometimento da release do `cstk-panel` atinge o painel e **nao**
> o toolkit — sao dois repositorios, duas releases, dois raios. Depois da
> fusao, **uma** release publica os dois pares de assets, e um comprometimento
> dessa release atinge **ambos**. O risco por evento nao muda; a superficie
> atingida por evento, sim.

Esse e o motivo pelo qual o aceite foi registrado com issues abertas em vez de
absorvido em silencio: o custo de R1/R2 sobe com esta feature, ainda que a
causa seja anterior a ela.

**Sobre R2, uma distincao que MUST ficar escrita:** hoje aquilo funciona por
**coincidencia de configuracao do GitHub** — o redirect de release vai para
`objects.githubusercontent.com`, que ja consta da allowlist constante
(`cli/lib/trusted-hosts.sh:47`, verificado por leitura) — e **nao** por
verificacao. Nada no codigo confere o host apos o redirect. **"Funciona hoje" e
diferente de "esta protegido"**: se o GitHub mudar o destino de redirect, o
download passa a sair de um host fora da allowlist sem que nenhum gate acuse.

**Escopo do aceite**: vale para esta feature. Nenhuma tarefa deste plano pode
citar R1 ou R2 como resolvidos, e nenhuma pode ampliar a exposicao a eles alem
do raio descrito acima. O fechamento de R1 e R2 e trabalho proprio, rastreado
nas issues #177 e #178.

## Re-check de Constitution (pos-Phase 1)

O design de Phase 1 introduziu tres coisas novas: um predicado de selecao, um
valor de enum e um teste de drift. Revalidando:

- **Principio II**: o predicado continua sendo uma condicao no `awk` existente,
  em POSIX. O teste de drift usa `awk`, nao `jq` — nenhuma dep nova, nenhum
  Bash-ism. Mantem PASS.
- **Principio IV**: o banner de FR-022 e estatico e offline-safe; nenhuma
  camada de rede foi adicionada ao design. Mantem PASS.
- **Principio I**: a mudanca de contrato (enum de `outcome`) esta documentada
  em `contracts/serve-asset-selection.md` §5, com nota de retrocompatibilidade
  verificada (o consumidor filtra por `source`, nao valida enum fechado).
  Mantem PASS.
- **Complexidade**: nenhuma camada, servico ou indirecao nova. O design remove
  uma duplicacao (`_SERVE_SUPPORTED_NODE_MAJORS`) em vez de adicionar.

**Resultado do re-check**: PASS mantido em todos os principios.
