# Research: Empacotamento do cstk como Plugin do Claude Code

Documento produzido no Phase 0 do `/plan`. Resolve os `NEEDS CLARIFICATION`
do Technical Context antes do design.

## Fontes consultadas (rastreabilidade — Constitution VI)

Toda afirmacao factual sobre o formato de plugin nesta pesquisa vem de uma
das fontes abaixo. Nenhum campo, path ou comportamento foi suposto.

| Id | Fonte | Natureza |
|----|-------|----------|
| S1 | `~/.claude/plugins/marketplaces/claude-plugins-official/.claude-plugin/marketplace.json` | Marketplace oficial da Anthropic, instalado localmente (284 entradas) |
| S2 | `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/*/.claude-plugin/plugin.json` | Manifestos reais de plugins publicados |
| S3 | `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/{hookify,claude-security,ralph-loop}/hooks/hooks.json` | `hooks.json` reais em producao |
| S4 | `~/.claude/plugins/installed_plugins.json` (version 2) | Registro nativo de plugins instalados |
| S5 | `~/.claude/plugins/known_marketplaces.json` | Registro nativo de marketplaces |
| S6 | `~/.claude/settings.json` chave `enabledPlugins` | Sinal de habilitacao |
| S7 | Repo cstk: `global/`, `scripts/build-release.sh`, `global/skills/agente-00c-runtime/hooks/` | Codigo-fonte do proprio toolkit |
| S8 | Doc oficial `plugins-reference.md` (contexto de invocacao desta execucao) | Referencia do formato |

> Onde uma afirmacao NAO pode ser sustentada por S1-S8, ela aparece
> explicitamente marcada como `[ASSUMPTION]` com task de validacao empirica
> no backlog — nunca como fato.

---

## Decision 1: Como o layout de plugin e gerado a partir do layout atual

**Contexto**: o formato de plugin exige `.claude-plugin/plugin.json` mais
`skills/`, `commands/`, `agents/`, `hooks/` na RAIZ DO PLUGIN (S8). O
catalogo do cstk hoje vive em `global/skills`, `global/commands`,
`global/agents` (S7) — um nivel que nao corresponde a nenhuma raiz de
plugin.

**Restricao decisiva descoberta na pesquisa**: `/plugin install` obtem o
conteudo a partir do **repositorio git**, no ref publicado. S1 mostra
entradas com `source` do tipo `git-subdir` (`url` + `path` + `ref` + `sha`)
e do tipo string relativa (`"./plugins/agent-sdk-dev"`), e S5 registra o
marketplace como um clone (`installLocation`). Logo, **o conteudo do plugin
precisa existir na arvore git comitada do tag** — um artefato gerado apenas
em tempo de release (que nunca e comitado) NAO e instalavel por esse
mecanismo. Isso elimina, por evidencia, a alternativa "build step gera a
arvore de plugin no release".

**Decision**: **relocar o catalogo para dentro de raizes de plugin comitadas
e apontar o build classico para o novo local** — um unico conteudo em git,
consumido pelos dois caminhos de distribuicao.

```
<repo>/
├── .claude-plugin/marketplace.json     # listagem (2 entradas)
├── plugins/
│   ├── cstk/                           # raiz do plugin core
│   │   ├── .claude-plugin/plugin.json
│   │   ├── skills/     (era global/skills)
│   │   ├── commands/   (era global/commands)
│   │   ├── agents/     (era global/agents)
│   │   └── hooks/hooks.json            # NOVO (so o registro; scripts nao se movem)
│   └── cstk-language-go/               # raiz do plugin de perfil go
│       ├── .claude-plugin/plugin.json
│       ├── skills/     (era language-related/go/skills)
│       └── hooks/      (era language-related/go/hooks)
└── scripts/build-release.sh            # passa a ler de plugins/cstk/**
```

`marketplace.json` usa `source` string relativa (`"./plugins/cstk"`),
forma verificada em S1 e usada por 53 dos 284 plugins oficiais.

**Rationale**:

1. **Fonte unica de verdade** (exigencia direta de FR-009: "sem exigir a
   manutencao de duas copias divergentes da mesma logica"). Qualquer opcao
   que mantenha duas arvores com o mesmo conteudo reintroduz exatamente a
   classe de drift que esta feature existe para eliminar.
2. **Nao quebra o caminho classico** (FR-010/SC-006): o tarball continua
   sendo produzido por `build-release.sh`; muda apenas o diretorio de
   origem que ele varre. O contrato externo (`cstk install`, `cstk update`,
   manifest, profiles) permanece identico — o operador classico nao percebe
   diferenca.
3. **Duas raizes sao inevitaveis**: a listagem tem 2 entradas ratificadas
   (`cstk`, `cstk-language-go`) e cada plugin precisa da propria raiz. Nao
   existe layout em que ambos ocupem a raiz do repo; padronizar os dois sob
   `plugins/` e mais coerente que misturar raiz-do-repo com subdiretorio.

**Alternatives considered**:

| Alternativa | Por que rejeitada |
|-------------|-------------------|
| **A. Plugin root = raiz do repo** (mover `global/skills` → `skills/`) | Acomoda apenas UM plugin; `cstk-language-go` precisaria de subdiretorio de qualquer forma. Alem disso poluiria a raiz do repo com diretorios de catalogo, colidindo com `cli/`, `tests/`, `docs/`. |
| **B. Arvore de plugin gerada no build (nao comitada)** | **Impossivel por evidencia** (S1/S5): a instalacao le do repo git no ref publicado; conteudo nao comitado nao existe para o instalador. |
| **C. Arvore de plugin duplicada e comitada (gerada por script + commit)** | Duas copias do mesmo conteudo em git. Viola o espirito de FR-009 e recria o drift que a feature combate; exigiria um gate de CI so para detectar divergencia entre copias. |
| **D. Symlinks (`plugins/cstk/skills` → `../../global/skills`)** | Git versiona symlinks, mas **nao ha evidencia em S1-S8** de que o instalador de plugin preserve/resolva symlinks ao materializar o cache. Adotar exigiria afirmar comportamento de plataforma nao documentado — vetado por Constitution VI. |

> **Custo assumido e explicitado**: a relocacao produz um diff grande
> (renomeacao de ~22 skills, 6 commands, 7 agents). E mecanico (`git mv`,
> preserva historico) e concentrado numa unica fase do backlog, mas exige
> atualizar `build-release.sh`, `profiles.txt.in` e as referencias a
> `global/` na suite de testes e na documentacao.

---

## Decision 2: Como os hooks de guarda sao registrados no plugin

**Decision**: `plugins/cstk/hooks/hooks.json` registra os hooks apontando
para os scripts **no local onde ja vivem** dentro do plugin, via
`${CLAUDE_PLUGIN_ROOT}`. Os scripts de hook NAO sao movidos nem duplicados.

Forma verificada em S3 (`claude-security`):
`"command": "sh \"${CLAUDE_PLUGIN_ROOT}/hooks/banner_hook.sh\""` — o valor
e um comando de shell com o path expandido, e pode referenciar qualquer
caminho sob a raiz do plugin.

Mapeamento a partir do snippet classico (S7,
`global/skills/agente-00c-runtime/hooks/settings.snippet.json`):

| Evento | Matcher | Script (mesmo dos dois caminhos) |
|--------|---------|----------------------------------|
| `PreToolUse` | `Bash` | `skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh` |
| `PostToolUse` | `*` | `skills/agente-00c-runtime/hooks/posttooluse-tool-call-tick.sh` |
| `PostToolUse` | `Agent` | `skills/agente-00c-runtime/hooks/posttooluse-agent-usage.sh` |

**Rationale**: o classico registra por projeto apontando para copias em
`"$CLAUDE_PROJECT_DIR"/.claude/hooks/` (S7); o plugin registra uma vez
apontando para a copia unica do catalogo. Mesmo script, mesmos exit codes,
mesma politica — muda so quem o registra e por qual path.

**`posttooluse-loose-usage.sh` fica FORA do `hooks.json` do plugin**: hoje
ele e opt-in explicito (`cstk hooks install --with-loose-usage`, snippet
separado — S7). Inclui-lo no plugin transformaria um opt-in deliberado em
comportamento default ao habilitar o plugin, alterando a postura de
privacidade sem consentimento equivalente. Fica registravel apenas pelo
caminho classico nesta feature.

**Alternatives considered**: duplicar os scripts em `plugins/cstk/hooks/`
(rejeitado — duas copias, mesmo problema da Decision 1 alternativa C);
registrar `loose-usage` junto (rejeitado — muda default de privacidade).

---

## Decision 3: Resolucao dual-path dos scripts de runtime (FR-009/FR-012)

**Levantamento empirico** (S7, contagem por `grep` nesta execucao — numero
citado na spec era aproximado; este e o medido):

| Onde | Ocorrencias | Natureza |
|------|-------------|----------|
| Arquivos `.md` (SKILL.md, agents, commands) | 38 | **Prosa/instrucao** ao LLM |
| Arquivos `.sh` — linhas de comentario | 9 | Documentacao interna |
| Arquivos `.sh` — **codigo executavel** | **15** | Resolucao real de path |
| **Total** | **62** | |

As 15 linhas executaveis concentram-se em **6 arquivos**:
`pretooluse-bash-guard.sh` (4), `posttooluse-loose-usage.sh` (4),
`posttooluse-agent-usage.sh` (2), `posttooluse-tool-call-tick.sh` (2),
`guard-hooks-status.sh` (2), `issue.sh` (1).

**Descoberta que reduz o escopo**: os 4 hooks **ja implementam uma cascata
de resolucao** (S7 — ex.: `pretooluse-bash-guard.sh` documenta "3.
`$HOME/.claude/skills/agente-00c-runtime/scripts/*` (escopo global)"), em
que `$HOME/.claude/...` e apenas UM candidato entre varios. O trabalho
portanto **nao e reescrever 62 referencias**: e **acrescentar
`${CLAUDE_PLUGIN_ROOT}` como candidato** numa cascata que ja existe.

**Decision**: helper sourceable unico — `_resolve-root.sh` — em
`skills/agente-00c-runtime/scripts/`, com a ordem de precedencia:

```
1. ${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime   (caminho plugin)
2. diretorio-irmao do proprio script (dirname $0)    (DEV / execucao in-place)
3. $HOME/.claude/skills/agente-00c-runtime           (caminho classico)
4. nenhum -> erro diagnostico acionavel              (FR-012)
```

**Rationale**: um unico helper evita replicar a cascata em 6 arquivos (a
divergencia entre copias da mesma logica ja e um modo de falha conhecido do
projeto). Plugin tem precedencia sobre classico por consistencia com o
"plugin vence" ja ratificado para dedup de hooks (FR-005).

**Tensao real identificada — FR-012 vs politica fail-open**: FR-012 exige
falha "diagnostica e acionavel, nunca silenciosa". Mas os 3 hooks de
metrica sao **fail-OPEN absoluto por desenho** (S7, cabecalho de
`posttooluse-tool-call-tick.sh`: "qualquer falha ... = exit 0 silencioso,
stdout vazio. Este hook NUNCA bloqueia"). Resolucao adotada: **FR-012 e
satisfeito pelo canal de diagnostico, nao pelo exit code** — hook de metrica
que nao resolve a raiz escreve uma linha de diagnostico no proprio sidecar
e **mantem exit 0** (nao regride a garantia de nao-interferencia);
`pretooluse-bash-guard.sh` mantem fail-CLOSED (`MECANISMO_FALHOU`, ja sua
politica). Alterar a polaridade de qualquer hook esta fora de escopo.

**Alternatives considered**: editar as 15 linhas isoladamente (rejeitado —
6 copias divergentes da mesma cascata); variavel de ambiente exportada pelo
`cstk` (rejeitado — hooks disparam sem o `cstk` no processo pai); reescrever
tambem as 38 referencias em `.md` (rejeitado nesta feature — sao instrucoes
em prosa ao LLM, resolvidas por leitura contextual, nao por `exec`; tratadas
na task de documentacao FR-013).

---

## Decision 4: Deteccao de "plugin habilitado" para dedup (FR-005)

**Decision**: deteccao **read-only** sobre os registros nativos, exigindo
instalado **E** habilitado:

1. `~/.claude/plugins/installed_plugins.json` (S4) — chave
   `"cstk@<marketplace>"` presente em `.plugins`.
2. `~/.claude/settings.json` chave `enabledPlugins` (S6) — mapa
   `"nome@marketplace" -> boolean`; considerar habilitado apenas se `true`.

**Evidencia de que os dois sinais sao necessarios** (S4 + S6): os tres
plugins registrados como instalados no ambiente auditado
(`swift-lsp`, `clangd-lsp`, `frontend-design`) aparecem em `enabledPlugins`
com valor `false`. **Instalado nao implica habilitado** — checar apenas
`installed_plugins.json` produziria falso-positivo e suprimiria os hooks
classicos de um projeto que nao tem plugin ativo (regressao direta de
SC-006).

**Rationale**: sao os unicos registros de habilitacao observaveis em S1-S8.
Leitura e estritamente nao-destrutiva — coerente com dec-010 (o diretorio
`~/.claude/plugins/` e nativo do harness e **nunca** deve ser usado como
store proprio do toolkit); ler para diagnostico nao o torna store.

**Degradacao**: arquivos ausentes/ilegiveis/malformados ⇒ tratar como
"plugin nao habilitado" e seguir pelo caminho classico. Falha de deteccao
nunca pode remover a unica camada de guarda existente.

**Alternatives considered**: escrever marcador proprio ao instalar o plugin
(rejeitado — nao existe install-hook arbitrario no formato, S8, e violaria
dec-010); inferir do `$PATH` ou de `${CLAUDE_PLUGIN_ROOT}` (rejeitado —
so existe dentro de sessao com o plugin ativo; `cstk hooks install` roda
fora dessa sessao).

---

## Decision 5: Criterio de alinhamento entre os dois caminhos (FR-008)

**Decision**: comparar **checksum de conteudo** (`hash_dir`, o mesmo
mecanismo ja usado por `cstk doctor` — S7) entre o catalogo classico em
`~/.claude/skills/<skill>` e o catalogo do plugin, cuja localizacao vem do
campo `installPath` de `installed_plugins.json` (S4).

**Evidencia empirica que sustenta a decisao ja ratificada no clarify**: em
S4, a entrada `frontend-design` tem `"version": "unknown"` e
`installPath` terminando em `/unknown`. Ou seja, **o metadado de versao do
harness nem sempre carrega valor util**; checksum de conteudo e o unico
criterio confiavel disponivel. (Esta era uma decisao tomada por precaucao
no clarify — a inspecao de S4 a confirma empiricamente.)

**Rationale**: reusa mecanismo existente, sem introduzir dependencia nova
e sem depender de metadado de plataforma nao garantido.

**Alternatives considered**: comparar `version` do `plugin.json` contra o
manifest classico (rejeitado — S2 mostra `plugin.json` sem campo `version`
em plugins oficiais como `plugin-dev`; o campo e opcional, e S4 confirma
que pode chegar como `"unknown"`).

---

## Decision 6: Publicacao da listagem em lockstep com tags SemVer (FR-003)

**Decision**: `.claude-plugin/marketplace.json` e comitado no repo e
atualizado no mesmo commit de release que ja bumpa CHANGELOG e cria a tag
`vX.Y.Z`; o campo `version` de cada entrada acompanha a tag. O workflow de
release (`release.yml`, S7) ganha um passo de **validacao** (manifesto
parseavel, `name` presente, `source` apontando para diretorio existente,
`version` == tag) — nunca um passo que gere conteudo novo.

**Rationale**: lockstep foi ratificado no clarify. Como o instalador le do
git no ref publicado (Decision 1), a tag ja e o mecanismo natural de
lockstep — nao e preciso servico externo, satisfazendo FR-011 (zero
endpoint operado pelo autor).

**[ASSUMPTION] a validar empiricamente**: se um consumidor que instalou por
`ref: main` recebe atualizacao continua em vez de lockstep. S1 mostra ambos
os usos em producao (`"ref": "v1.5.5"` em `42crunch-api-security-testing` e
`"ref": "main"` em `adobe-for-creativity`), mas nao documenta a semantica de
atualizacao de cada um. Task de validacao no backlog.

---

## Assumptions abertas (carregam task de validacao empirica obrigatoria)

| Id | Assumption | Origem | Como validar |
|----|-----------|--------|--------------|
| A1 | Habilitar o plugin basta para os hooks ficarem ativos, sem gate extra especifico para hooks | Spec §Clarifications (ja registrada) | Habilitar o plugin num projeto limpo e checar se os 3 hooks disparam sem `cstk hooks install` |
| A2 | Timing de ativacao — se exige `/reload-plugins` ou reinicio de sessao | Spec §Clarifications | Medir no mesmo experimento de A1 |
| A3 | `source` string relativa (`"./plugins/cstk"`) funciona para marketplace no proprio repo do toolkit | S1 (forma observada em 53/284 entradas oficiais, nao em repo do cstk) | Instalar o marketplace local e rodar `/plugin install cstk@cstk` |
| A4 | Semantica de atualizacao de `ref: <tag>` vs `ref: main` | Decision 6 | Publicar tag de teste e observar comportamento de update |
| A5 | O instalador preserva permissao de execucao (`+x`) dos `.sh` ao materializar o cache | Nao coberto por S1-S8 | Inspecionar `installPath` apos instalar e conferir bit `+x` dos hooks |

> A5 e critica e facil de passar batido: se o bit de execucao nao sobrevive,
> `hooks.json` deve invocar via `sh "<path>"` (forma observada em S3 no
> `claude-security`) em vez de executar o script diretamente.
