# Implementation Plan: Retomada da Oferta de Leva Paralela do Roadmap

**Feature**: `roadmap-wave` | **Date**: 2026-08-18 | **Spec**: [spec.md](./spec.md)

## Summary

Hoje a oferta de leva paralela do roadmap so existe no instante em que
uma execucao `/agente-00c` termina em modo roadmap — o gatilho literal e
`.execution.termination_reason == concluido_roadmap`
(`plugins/cstk/commands/agente-00c.md:893`, §6.ter). Perdida essa janela,
nao ha caminho automatizado para recalcular a fronteira e relancar.

Esta feature adiciona um **segundo ponto de entrada**: o slash command
`/roadmap-wave`, invocavel a qualquer momento sobre qualquer projeto com
roadmap valido. Ele **nao reimplementa** calculo de fronteira, oferta,
teto nem lancamento — consome os mesmos helpers ja entregues
(`roadmap-frontier.sh`, `parallel-launch.sh`) e delega o fluxo de 9
passos a `agente-00c.md` §6.ter por referencia, exatamente como
`agente-00c-resume.md` §9.ter ja faz.

O unico codigo novo e um subcomando POSIX `parallel-launch.sh
resolve-offer`, que tira da prosa e coloca em codigo testavel a regra de
modo nao-interativo (FR-012/FR-013/FR-014) — replicando o precedente
`delivery-tier.sh resolve-initial`, criado exatamente porque um spike
headless flagrou um agente sobrepondo a regra escrita em prosa.

## Technical Context

**Language/Version**: POSIX `sh` (`#!/bin/sh`, `set -eu`) para o helper;
Markdown para a prosa do command
**Primary Dependencies**: nenhuma nova. Consome `roadmap-frontier.sh`,
`roadmap-status.sh`, `parallel-launch.sh`, `cstk session start`, `tmux`
(opcional, com caminho degradado ja contratado)
**Storage**: N/A — feature sem estado persistente (ver `data-model.md`
§"Nota de escopo")
**Testing**: harness POSIX proprio (`./tests/run.sh`); grep estatico para
prosa de command, execucao real para o helper
**Target Platform**: macOS/Linux, dentro do harness Claude Code
**Project Type**: cli / toolkit de skills+commands
**Performance Goals**: N/A (interacao humana, uma invocacao por vez)
**Constraints**: Constitution II (POSIX puro, sem `jq` em script de
skill); Constitution VI (zero fabricacao)
**Scale/Scope**: 1 arquivo de command novo, 1 subcomando novo, 2 arquivos
de teste tocados, 1 arquivo de teste novo

## Constitution Check

*GATE: passou antes do Phase 0. Re-checado apos Phase 1 (ver §Re-check).*

| Principio | Status | Notas |
|---|---|---|
| I. SDD recursivo (NON-NEGOTIABLE) | PASS | feature entrou por `specify` → `clarify` (3 Q&A) → `plan`; `spec.md` + `tasks.md` em `docs/specs/roadmap-wave/`. Command novo = mudanca de contrato ⇒ exige bump de versao + CHANGELOG (previsto na FASE 4) |
| II. POSIX sh puro, zero dep externa (NON-NEGOTIABLE) | PASS | `resolve-offer` e POSIX puro, sem `jq`; saida `chave=valor` justamente para ser parseavel sem `jq` (contract §3.3) |
| III. Formato canonico de skill | N/A | nao ha skill nova. O artefato novo e um **command**, cuja convencao (frontmatter `description`/`argument-hint`/`allowed-tools`) foi verificada nos 6 commands atuais |
| IV. Zero coleta remota (NON-NEGOTIABLE) | PASS | tudo local: le `docs/roadmap.md`, cria worktrees locais. Nenhuma chamada de rede |
| V. Profundidade > metricas de adocao | PASS | feature elimina retrabalho manual (relancar leva a mao), nao adiciona superficie de adocao |
| VI. Veracidade de dados (NON-NEGOTIABLE) | PASS | todo valor deste plano tem `path:linha` ou output observado; o que nao existe esta marcado `[PROPOSTA — a validar na implementacao]`; INV-5 do contrato proibe reforcar avisos do roadmap como conflito confirmado |

## Project Structure

### Documentacao (feature dir) — paths reais

```
docs/specs/roadmap-wave/
├── spec.md          # ja existente (14 FRs, 3 clarifications)
├── plan.md          # este arquivo
├── research.md      # Phase 0 — 7 decisoes
├── data-model.md    # Phase 1
├── quickstart.md    # Phase 1 — 18 cenarios (C18 acrescentado na task 1.3.4)
└── contracts/
    └── roadmap-wave-command.md   # Phase 1 [PROPOSTA]
```

### Codigo — arvore real do repo, com os pontos de toque

```
plugins/cstk/
├── commands/                      # 6 arquivos hoje
│   ├── agente-00c.md              # LEITURA (§6.ter e a fonte DRY) — nao alterar
│   ├── agente-00c-resume.md       # LEITURA (§9.ter e o precedente de reuso)
│   └── roadmap-wave.md            # NOVO  [PROPOSTA]
└── skills/
    ├── review-features/scripts/
    │   ├── roadmap-frontier.sh    # ALTERADO (dec-031): contencao real de path
    │   │                          # em --exclude-active-from-repo, antes de
    │   │                          # git -C (revisa a marcacao original
    │   │                          # "nao alterar" — o defeito e do proprio
    │   │                          # helper, seu contrato ja exige a checagem)
    │   └── roadmap-status.sh      # dependencia indireta — nao alterar
    └── agente-00c-runtime/scripts/
        └── parallel-launch.sh     # ALTERADO: + subcomando resolve-offer

tests/
├── test_parallel-launch.sh                    # ALTERADO: + cenarios de resolve-offer
├── test_command-spawn-roadmap-wave.sh         # NOVO (grep estatico da prosa)
├── test_command-prompt-noninteractive-lint.sh # gate automatico por glob — nao alterar
├── test_doc-subcommands.sh                    # gate automatico por glob — nao alterar
└── run.sh                                     # ALTERADO: case-label do teste novo

README.md, README.pt-BR.md                     # ALTERADOS: contagem 6 → 7 commands
CHANGELOG.md                                   # ALTERADO: entrada da versao
```

**Structure Decision**: o subcomando novo mora em `parallel-launch.sh`
(mesma familia, mesmo contrato) em vez de num script proprio. Motivo
verificado: a "regra de ouro" do `CLAUDE.md` exige `test_<nome>.sh` para
todo `.sh` novo, gateada por `./tests/run.sh --check-coverage`;
`tests/test_parallel-launch.sh` ja existe (25 cenarios) e absorve os
casos novos sem criar arquivo orfao.

## Convencoes de Borda

**N/A — single-layer.** Nao ha borda backend↔frontend, DB↔backend nem
broker↔consumer nesta feature. A unica fronteira e
command (Markdown/prosa) ↔ helper POSIX, e ela ja tem convencao fixada
no contrato §3.3: saida `chave=valor` em stdout, diagnostico em stderr,
exit `0`/`2` — o mesmo formato dos demais helpers de runtime, escolhido
para dispensar `jq` (Constitution II).

## Portoes de empacotamento e release — verificado, nao suposto

Varredura feita nesta onda sobre o que um command novo dispara:

| Alvo | Impacto | Evidencia |
|---|---|---|
| `tests/test_doc-counts.sh` | **nenhum** — so conta skills | `:28-29` `SKILLS_DIR=".../plugins/cstk/skills"`; `:31-33` unica contagem e de skills |
| `tests/cstk/test_build-release.sh` | **nenhum** — o `17` hardcoded e de skills do profile `sdd` | `:175-187` |
| `tests/cstk/test_quickstart-e2e.sh` | **nenhum** — idem | `:207-226` |
| `scripts/profiles.txt.in` | **nenhum** — commands instalam sem filtro de profile | `:31`, `:43` |
| `scripts/build-release.sh` | **nenhum** — empacota commands por glob `*.md` | `:170-184` |
| `.claude-plugin/marketplace.json`, `plugins/cstk/.claude-plugin/plugin.json` | **nenhum** — nao listam commands individualmente | inspecao direta |
| `tests/cstk/fixtures/regen.sh` | **opcional** — fixtures sao gitignored e so regeneram se ausentes | `test_quickstart-e2e.sh:38-42` |
| `README.md` / `README.pt-BR.md` | **OBRIGATORIO** — texto "6 commands" | `README.md:101,346`; `README.pt-BR.md:102,307,348` |
| `tests/run.sh::_is_internal_test` | **OBRIGATORIO se criar teste novo** — labels sao literais, **sem** glob | `:246-300` (um `case`-label por teste) |
| `tests/test_command-prompt-noninteractive-lint.sh` | **gate automatico** por glob de diretorio | `:34`, `:45-46` |
| `tests/test_doc-subcommands.sh` | **gate automatico** — subcomando citado deve existir | `:33` |
| `tests/test_state-db-migrate.sh` (proibicao M6) | o command nao pode mencionar `state-db-migrate` | `:534-535` |
| `docs-site/hooks/gen_pages.py` | pagina gerada por glob; exige frontmatter `description` | `:509-513`; CI tolera crescimento (`publish-site.yml:110`, `-ge 5`) |

## Fases de implementacao

### FASE 1 — Helper `resolve-offer` (base de tudo)

Implementar o subcomando em `parallel-launch.sh` conforme contract §3 +
cenarios C8-C11 em `tests/test_parallel-launch.sh`. **Precede a FASE 2
por dependencia dura**: `tests/test_doc-subcommands.sh:33` reprova
qualquer command que cite subcomando inexistente.

### FASE 2 — Command `/roadmap-wave`

Criar `plugins/cstk/commands/roadmap-wave.md`: frontmatter, parse de
argumentos (contract §1), chamada a `resolve-offer`, mapeamento
exit→mensagem (contract §4) e **delegacao por referencia** a
`agente-00c.md` §6.ter. Toda pergunta ao operador com clausula de
nao-interatividade no mesmo bloco (gate C12).

**Bloqueante nesta fase** (gate `owasp-security`, contract §5): o command
MUST conter (a) o rotulo UNTRUSTED sobre a saida do
`roadmap-frontier.sh` injetada no turno (F1), (b) a declaracao da
premissa de confianca do projeto-alvo + a proibicao de derivar o path de
conteudo lido (F3, INV-6), (c) o nome do projeto-alvo resolvido dentro da
declaracao de blast radius (F3), e (d) o eco explicito de
`source`/`launch`/`max` resolvidos (F4).

### FASE 3 — Testes de prosa

Criar `tests/test_command-spawn-roadmap-wave.sh` (C14, assercoes
positivas + negativa de nao-duplicacao) e registrar o `case`-label em
`tests/run.sh::_is_internal_test` com existence-guard ao command,
espelhando `run.sh:269-276`.

### FASE 4 — Docs e release

Atualizar contagem de commands nos dois READMEs, entrada de CHANGELOG
com o link de referencia no rodape (gotcha ja documentado no
`CLAUDE.md`), e rodar `./tests/run.sh` completo.

## Cenarios de teste mapeados aos Success Criteria

Ver `quickstart.md` §"Mapa cenario → Success Criteria" (C1-C14).
Resumo: SC-001→C1; SC-002→C2/C3/C4; SC-003→C6/C7; SC-004→C5/C9/C10.

## Re-check de constitution (pos-design)

Nenhum principio mudou de status apos o design. O design **reduz**
superficie em vez de aumenta-la: zero estado novo, zero dependencia
nova, um unico subcomando adicionado a um script existente e um command
que delega em vez de duplicar. Constitution I continua PASS com a
ressalva ja registrada: por alterar o contrato publico do toolkit
(command novo), a entrega exige bump de versao + CHANGELOG.

## Complexity Tracking

> Sem violacoes de constitution — secao intencionalmente vazia.

## Riscos conhecidos

| Risco | Mitigacao |
|---|---|
| Prosa do command ser sobreposta pelo agente em modo nao-interativo (precedente real do spike de 2026-08-15) | regra vive em `resolve-offer` (codigo), nao so na prosa; lint C12 cobre a prosa |
| Divergencia futura entre §6.ter e o novo command | reuso por referencia + assercao negativa em C14 (o command NAO pode conter copia dos 9 passos) |
| Teste novo virar "orfao" no orphan-check | `run.sh::_is_internal_test` usa labels literais sem glob — FASE 3 inclui o registro explicito |
| Operador supor que o teto e fronteira de seguranca | a declaracao de blast radius de §6.ter e reusada tal-e-qual (requisito de blast radius da feature irma `roadmap-parallel-launch`, `agente-00c.md:958-965`) |
| Projeto-alvo parametrizavel apontado para repo hostil ⇒ `git -C` executa codigo via `.git/config` | contract §5.3: premissa de confianca declarada no command + INV-6 (path nunca derivado de conteudo lido) **+ mitigacao tecnica real no helper (dec-031, task 1.3)**: `roadmap-frontier.sh` passa a validar que `--exclude-active-from-repo` resolve para dentro da raiz do repo coordenador ANTES de `git -C`, nao so a rejeicao sintatica de `..` (`roadmap-frontier.sh:121-136`). Herdado por todo consumidor do helper (`resolve-offer`/`emit`, `agente-00c.md` §6.ter, uso manual) |
| Prosa do roadmap de terceiro carregando diretiva de injecao | contract §5.1: rotulo UNTRUSTED obrigatorio ao injetar a saida no turno |
| `--max` scriptado com valor absurdo em modo nao-interativo | contract §3.2: faixa `1..8`, fail-closed acima |
