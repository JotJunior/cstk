# Implementation Plan: Empacotamento do cstk como Plugin do Claude Code

**Feature**: `claude-plugin-packaging` | **Date**: 2026-08-08 | **Spec**: [spec.md](./spec.md)

## Summary

Publicar o catalogo do cstk (22 skills, 6 commands, 7 agents, hooks de
guarda) como **plugin nativo do Claude Code**, instalavel por
`/plugin install cstk@cstk`, eliminando a copia manual e o drift entre repo
e instalacao — sem alterar em nada o caminho classico (`cstk install`/
`cstk update`), que permanece o unico canal do binario.

**Abordagem tecnica** (derivada da pesquisa, `research.md` Decision 1): o
instalador de plugin le do **repositorio git no ref publicado** — logo o
conteudo do plugin precisa existir na arvore comitada, o que elimina a
opcao "gerar a arvore no build". Para nao criar duas copias do mesmo
conteudo (que reintroduziria o drift que a feature combate), o catalogo e
**relocado** para raizes de plugin comitadas (`plugins/cstk/`,
`plugins/cstk-language-go/`) e o build classico passa a ler dali. **Um unico
conteudo em git, dois caminhos de distribuicao.**

Os hooks nao sao movidos nem duplicados: um `hooks.json` no plugin aponta,
via `${CLAUDE_PLUGIN_ROOT}`, para os mesmos scripts do catalogo. A
compatibilidade dual-path do runtime resolve-se com **um** helper de
resolucao, nao com 62 edicoes dispersas — os 4 hooks ja possuem cascata de
resolucao; ganham mais um candidato.

## Technical Context

**Language/Version**: POSIX sh (Constitution II); JSON para os manifestos
**Primary Dependencies**: nenhuma nova. `jq` segue como dependencia opcional com fallback (amendment 1.1.0)
**Storage**: filesystem. Registros nativos do harness em `~/.claude/plugins/` sao **lidos, nunca escritos** (dec-010)
**Testing**: `./tests/run.sh` (harness POSIX, ~1100 cenarios) + validacao empirica manual dos cenarios 1-3 do `quickstart.md`
**Target Platform**: Claude Code CLI, Desktop e cloud (via `enabledPlugins`)
**Project Type**: CLI tool + catalogo distribuivel
**Performance Goals**: N/A — nao ha caminho quente. Deteccao de plugin adiciona no maximo 2 leituras de arquivo por invocacao de `doctor`/`hooks install`
**Constraints**: caminho classico **inalterado** (FR-010/SC-006); zero coleta remota (FR-011); polaridade fail-open/fail-closed dos hooks preservada
**Scale/Scope**: 2 entradas de marketplace; 22 skills + 6 commands + 7 agents relocados; 15 linhas de codigo de resolucao de path em 6 arquivos; 3 arquivos do CLI tocados

**NEEDS CLARIFICATION restantes**: 0.
**Assumptions abertas**: 5 (A1-A5, `research.md`), todas com cenario de
validacao empirica no `quickstart.md` e task obrigatoria no backlog.

## Constitution Check

*GATE: passou antes do Phase 0. Re-checado apos Phase 1 (secao §Re-check).*

| Principio | Status | Notas |
|-----------|--------|-------|
| **I. SDD recursivo** (NON-NEGOTIABLE) | PASS | Feature entrou pela pipeline completa (specify → clarify → plan). Relocacao de catalogo altera paths de contrato → exige nota BREAKING no CHANGELOG + bump MAJOR |
| **II. POSIX sh puro, zero dep externa** (NON-NEGOTIABLE) | PASS (com amendment) | `_resolve-root.sh` e POSIX sh puro, sem deps. `plugin-detect.sh` le JSON e usa `jq` sob o **amendment 1.1.0**: (a) funciona sem a ferramenta — ausencia ⇒ exit 2 (indeterminado) ⇒ caminho classico, resultado correto com UX degradada; (b) fallback coberto por teste (Scenario 7); (c) `jq` ja e dependencia opcional estabelecida no `cli/lib/` |
| **III. Formato canonico de skill** | N/A | Nenhuma skill nova; nenhum `SKILL.md` muda de conteudo. Skills apenas mudam de diretorio |
| **IV. Zero coleta remota** (NON-NEGOTIABLE) | PASS | Distribuicao 100% pelo proprio repo git (FR-011). Nenhum endpoint de telemetria/analytics. `loose-usage` deliberadamente **fora** do `hooks.json` do plugin para nao converter opt-in de privacidade em default |
| **V. Profundidade > metricas de adocao** | PASS | Feature ataca causa-raiz documentada (drift + hooks nao provisionados), nao metrica de adocao |
| **VI. Veracidade de dados** (NON-NEGOTIABLE) | PASS | Todo schema de plugin/marketplace/hooks extraido de arquivos reais (S1-S6). Cinco lacunas nao cobertas por fonte estao marcadas `[ASSUMPTION]` (A1-A5) com validacao empirica obrigatoria — nenhuma afirmada como fato |

**Nota de governanca**: a relocacao `global/` → `plugins/cstk/` altera o
contrato de paths do repo. Por Principio I, exige `spec.md` (existe), bump
de versao e **nota BREAKING** no CHANGELOG.

## Project Structure

### Documentation (this feature)

```
docs/specs/claude-plugin-packaging/
├── spec.md
├── plan.md                              # This file
├── research.md                          # Phase 0
├── data-model.md                        # Phase 1
├── quickstart.md                        # Phase 1
└── contracts/
    ├── plugin-artifacts.md              # Phase 1
    └── cli-plugin-awareness.md          # Phase 1
```

### Source Code (repository root)

Estado **atual** (verificado):

```
cstk/
├── cli/{cstk,lib/*.sh,install.sh}
├── global/{skills/(22),commands/(6),agents/(7)}
├── language-related/go/{skills,hooks}
├── mcp/state-server/
├── scripts/{build-release.sh,profiles.txt.in}
├── tests/{run.sh,cstk/}
└── docs/
```

Estado **alvo**:

```
cstk/
├── .claude-plugin/marketplace.json          # NOVO — 2 entradas
├── plugins/
│   ├── cstk/
│   │   ├── .claude-plugin/plugin.json       # NOVO
│   │   ├── hooks/hooks.json                 # NOVO (registro; scripts nao se movem)
│   │   ├── skills/     <- git mv global/skills
│   │   ├── commands/   <- git mv global/commands
│   │   └── agents/     <- git mv global/agents
│   └── cstk-language-go/
│       ├── .claude-plugin/plugin.json       # NOVO
│       ├── skills/     <- git mv language-related/go/skills
│       └── hooks/      <- git mv language-related/go/hooks
├── cli/lib/plugin-detect.sh                 # NOVO
├── scripts/build-release.sh                 # MODIFICADO (le de plugins/cstk/**)
└── (cli/, mcp/, tests/, docs/ inalterados na estrutura)
```

**Structure Decision**: raizes de plugin **comitadas** sob `plugins/`, com
`marketplace.json` na raiz apontando por `source` string relativa (forma
verificada em 53 das 284 entradas oficiais reais). Escolhida por ser a unica que
preserva **fonte unica de verdade** (FR-009) sendo simultaneamente
instalavel pelo mecanismo nativo. Alternativas e o motivo de cada rejeicao
estao em `research.md` Decision 1.

## Convencoes de Borda

A feature nao tem borda backend↔frontend. Tem, porem, uma borda real de
**empacotamento**: a arvore comitada no git versus a arvore materializada
no cache do harness. Declarar a fonte da verdade de cada artefato e o
analogo util aqui.

| Artefato | Fonte da verdade | Consumidor | Validacao |
|----------|------------------|------------|-----------|
| Conteudo do catalogo (skills/commands/agents) | `plugins/cstk/**` no git | Plugin (direto) **e** tarball classico (via build) | `diff -r` contra `installPath` (quickstart §3) |
| Registro de hooks — plugin | `plugins/cstk/hooks/hooks.json` | Harness ao habilitar o plugin | HK-1: paridade de eventos/matchers com o snippet classico |
| Registro de hooks — classico | `skills/agente-00c-runtime/hooks/settings.snippet.json` | `cstk hooks install` | idem |
| Versao publicada | Tag git `vX.Y.Z` | `marketplace.json` `.plugins[].version` | MP-5 no CI de release |
| Sinal "plugin habilitado" | `installed_plugins.json` + `settings.json.enabledPlugins` | `doctor`, `hooks install`, `setup` | Read-only; ambos exigidos |
| Alinhamento entre caminhos | `hash_dir` do conteudo | `cstk doctor` | **Nunca** o campo `version` (S4: pode vir `"unknown"`) |

**Mapper layer**: N/A — nao ha transformacao de dados; os dois caminhos
consomem os **mesmos bytes**. E precisamente essa ausencia de mapper que
torna a fonte unica obrigatoria: qualquer duplicacao viraria um mapper
implicito mantido a mao.

**Case style**: os manifestos usam `camelCase` nas chaves
(`enabledPlugins`, `installPath`, `lastUpdated`) — convencao **do harness**,
observada em S4/S5/S6, nao uma escolha desta feature.

## Ordem de implementacao sugerida

Sequenciada para manter a suite verde a cada passo e derrubar as
assumptions o quanto antes.

| Fase | Conteudo | Por que nesta ordem |
|------|----------|---------------------|
| 1 | **Spike de validacao empirica** (A1-A5) com plugin minimo descartavel | Derruba as 5 assumptions **antes** do trabalho caro. Se A1 for falsa, SC-002 muda e o escopo precisa ser reavaliado |
| 2 | `_resolve-root.sh` + adocao nos 6 arquivos (15 linhas) | Independente da relocacao; deixa o runtime dual-path-ready com a suite verde |
| 3 | Relocacao (`git mv`) + `build-release.sh` + refs em tests/docs | Mudanca grande e mecanica, isolada numa fase |
| 4 | Manifestos (`plugin.json` ×2, `marketplace.json`, `hooks.json`) + gate de CI (MP-1..MP-6) | Depende do layout da fase 3 |
| 5 | `plugin-detect.sh` + dedup em `hooks install`/`setup` + `doctor` | Depende dos manifestos para ter o que detectar |
| 6 | Documentacao (README, CLAUDE.md, CHANGELOG com nota BREAKING) — FR-007/FR-013 | Descreve o estado final ja estabilizado |

> A fase 1 e um **gate**, nao uma formalidade: e a unica coisa que separa
> "o plugin ativa os hooks automaticamente" de uma afirmacao nao verificada.
> O resultado dela pode alterar o restante do plano.

## Modelo de integridade por caminho de distribuicao (gate owasp — F1)

O gate de seguranca apontou uma **assimetria real** entre os dois caminhos.
Ela nao e um defeito a corrigir (os mecanismos sao de camadas diferentes),
mas **nao pode ser descrita como equivalencia**.

| Garantia | Caminho classico | Caminho plugin |
|----------|------------------|----------------|
| Verificacao de integridade | `sha256` do tarball, **fail-closed** (`serve-integrity`) | Pin por `gitCommitSha` registrado pelo harness |
| Origem confiavel | Allowlist fixa `CSTK_TRUSTED_RELEASE_HOSTS` (match exato, nao-overridable) | Repo git declarado no marketplace + confianca do harness |
| Transporte | `http://` **rejeitado** | HTTPS do provedor git |
| Consentimento | Comando explicito do operador | Tela "Will install" + dialogo de confianca |
| Quem aplica | Codigo do proprio cstk | Harness do Claude Code |

**Consequencia para a spec**: a Delta Requirement FR-017 de
`guards-defense-in-depth` afirma que o caminho plugin entrega "o mesmo
conjunto de garantias de seguranca". Pelo levantamento acima isso e
**impreciso**: as garantias sao **comparaveis em forca, porem distintas em
mecanismo e em responsavel**. A documentacao (FR-007/FR-013) MUST descrever
a tabela acima em vez de afirmar equivalencia — afirmar garantia que o
toolkit nao aplica seria, ele proprio, uma violacao do Principio VI.

> Registrado como **MEDIUM** (nao HIGH): o caminho plugin **nao** e
> desprotegido — e protegido por um mecanismo diferente, com pin de commit e
> consentimento explicito. O risco e de **comunicacao** (operador supor
> garantia inexistente), nao de exposicao direta.

**Sugestao de ajuste de spec** (nao aplicada aqui — `plan` nao edita
`spec.md`): reescrever a Delta FR-017 trocando "o mesmo conjunto de
garantias" por "garantias equivalentes em efeito, com mecanismos e
responsaveis distintos, documentados por caminho".

## Complexity Tracking

Sem violacoes de constitution a justificar. Registrados aqui os dois custos
deliberadamente aceitos:

| Custo aceito | Por que necessario | Alternativa simples rejeitada porque |
|--------------|--------------------|--------------------------------------|
| Diff grande de relocacao (`global/` → `plugins/cstk/`) | Unico layout que e simultaneamente instalavel pelo mecanismo nativo e de fonte unica | Manter `global/` + copia comitada = duas copias divergentes, exatamente o drift que a feature existe para eliminar (FR-009) |
| Deteccao de plugin lendo registros nativos do harness | Sao os unicos sinais de habilitacao observaveis (S4/S6); nao existe install-hook para gravar marcador proprio (S8) | Marcador proprio em `~/.claude/plugins/` violaria dec-010 (diretorio nativo, nunca store do toolkit) |

## Re-check pos-Phase 1

Design revisado apos os artefatos de Phase 1:

- **Complexidade nova**: 2 arquivos novos de codigo (`_resolve-root.sh`,
  `plugin-detect.sh`), zero servico novo, zero dependencia nova, zero flag
  nova de CLI. Dentro do orcamento.
- **Principio II**: reconfirmado — o uso de `jq` na deteccao permanece sob
  o amendment 1.1.0 com fallback testado (quickstart §7).
- **Principio IV**: reconfirmado — a decisao de manter `loose-usage` fora do
  `hooks.json` do plugin (research.md D2) **fortalece** o principio: sem
  ela, habilitar o plugin ligaria captura de consumo por default.
- **Principio VI**: reconfirmado — nenhuma afirmacao de plataforma sem
  fonte; A1-A5 explicitas com validacao empirica agendada na fase 1.
- **FR-012 × fail-open**: tensao identificada e resolvida no contrato
  (`plugin-artifacts.md` §Artefato 5) sem inverter a polaridade de nenhum
  hook. Registrada aqui por ser a decisao de design menos obvia do plano.

**Resultado**: PASS. Nenhuma violacao MUST; Complexity Tracking sem entradas
de violacao.

## Artefatos

| Arquivo | Status |
|---------|--------|
| `docs/specs/claude-plugin-packaging/plan.md` | Criado |
| `docs/specs/claude-plugin-packaging/research.md` | Criado |
| `docs/specs/claude-plugin-packaging/data-model.md` | Criado |
| `docs/specs/claude-plugin-packaging/contracts/plugin-artifacts.md` | Criado |
| `docs/specs/claude-plugin-packaging/contracts/cli-plugin-awareness.md` | Criado |
| `docs/specs/claude-plugin-packaging/quickstart.md` | Criado |
