# Quickstart: Empacotamento do cstk como Plugin do Claude Code

Cenarios que validam a implementacao end-to-end. Os cenarios 1-3 sao
**empiricos e obrigatorios**: sao eles que convertem as assumptions A1-A5 de
`research.md` em fato observado (ou em bug). Nenhum deles pode ser
declarado como passado por inspecao de codigo.

## Scenario 1: Habilitar o catalogo sem copia manual (happy path — SC-001)

1. Num ambiente limpo (sem `~/.claude/skills/` do cstk), adicionar o
   marketplace: `/plugin marketplace add JotJunior/cstk`
2. Instalar: `/plugin install cstk@cstk`
3. Habilitar o plugin e iniciar uma sessao num projeto qualquer
4. Invocar uma skill do catalogo (ex.: pedir um `specify`)
5. **Expected**: a skill dispara normalmente; nenhum passo de copia foi
   executado; `~/.claude/skills/` do cstk continua inexistente.

> Valida **A3** (`source` string relativa funciona para marketplace no
> proprio repo do toolkit).

## Scenario 2: Hooks ativos sem provisionamento por projeto (SC-002 — valida A1/A2/A5)

1. Com o plugin habilitado (Scenario 1), abrir um projeto que **nunca**
   rodou `cstk hooks install`
2. Confirmar que `<projeto>/.claude/settings.json` **nao** tem bloco de
   hooks do cstk
3. Iniciar execucao `agente-00c`/`feature-00c` nesse projeto
4. Rodar um comando `Bash` que o `bash-guard` deve bloquear (ex.: `sudo`)
5. Fechar uma onda e ler `tool_calls` no state
6. **Expected**:
   - o comando e bloqueado (PreToolUse ativo)
   - `tool_calls > 0` na onda (PostToolUse ativo) — o inverso do bug
     historico de contagem zerada
   - nenhum passo manual foi necessario

**Se falhar, registrar QUAL das assumptions caiu** — o resultado negativo e
tao valioso quanto o positivo:

| Sintoma | Assumption derrubada | Acao |
|---------|---------------------|------|
| Hooks so ativam apos `/reload-plugins` ou reinicio | **A2** (timing) | Documentar o passo em FR-013; reavaliar SC-002 |
| Harness pede consentimento extra especifico para hooks | **A1** | Atualizar spec §Clarifications: a assumption era falsa |
| Hook nao executa por permissao negada | **A5** (bit `+x`) | Confirmar que `sh "<path>"` (HK-3) resolve |

## Scenario 3: Roundtrip empirico do artefato instalado (analogo do roundtrip end-to-end)

> A feature nao tem borda backend↔frontend; o roundtrip equivalente e
> **arvore comitada → arvore materializada no cache**, que expoe drift de
> empacotamento que nenhum teste de unidade pega.

1. Instalar o plugin (Scenario 1)
2. Localizar o `installPath` real:
   `jq -r '.plugins["cstk@cstk"][].installPath' ~/.claude/plugins/installed_plugins.json`
3. Comparar a arvore materializada contra `plugins/cstk/` do repo no mesmo
   ref: `diff -r plugins/cstk "<installPath>"`
4. Conferir os bits de execucao:
   `find "<installPath>" -name '*.sh' ! -perm -u+x`
5. **Expected**: zero divergencia de conteudo; nenhum `.sh` sem `+x` **ou**,
   se houver, confirmacao de que `hooks.json` invoca via `sh "<path>"`
   (HK-3) e os hooks funcionam mesmo assim.

## Scenario 4: Dedup — plugin vence (FR-005)

1. Projeto com hooks classicos ja provisionados (`cstk hooks install --scope project`)
2. Habilitar tambem o plugin cstk
3. Rodar `cstk doctor`
4. Rodar `cstk hooks install --scope project` de novo
5. **Expected**:
   - `doctor` reporta `duplicated-hooks` com remediacao acionavel (exit 1)
   - `hooks install` **nao** registra o snippet, emite aviso e sai `0`
   - apos aplicar a remediacao, uma acao bloqueavel dispara **uma unica vez**

## Scenario 5: Alinhamento entre os dois caminhos (SC-004)

1. Ambiente com instalacao classica **e** plugin habilitado, mesma versao
2. `cstk doctor` → **Expected**: `aligned`, exit 0
3. Forcar divergencia (ex.: `cstk update` para uma versao mais nova que a do plugin)
4. `cstk doctor` → **Expected**: `diverged`, apontando **qual** caminho
   difere + remediacao correspondente, exit 1

## Scenario 6: Nao-regressao do caminho classico (SC-006 — error case invertido)

1. Ambiente **sem** plugin (so instalacao classica)
2. Rodar `cstk doctor`, `cstk hooks install`, `cstk update`, `cstk recall`,
   `cstk usage`, `cstk mcp status`
3. Rodar a suite: `./tests/run.sh`
4. **Expected**: comportamento e saidas **identicos** ao estado anterior a
   esta feature; nenhuma secao `Distribution Paths`; suite verde.

## Scenario 7: Degradacao com registros nativos ilegiveis (error case)

1. Plugin habilitado; corromper `~/.claude/plugins/installed_plugins.json`
   (ex.: gravar `{` truncado) num **ambiente descartavel**
2. Rodar `cstk doctor` e `cstk hooks install --scope project --dry-run`
3. **Expected**: nenhum comando falha com stack/erro fatal; deteccao
   degrada para "nao habilitado"; `hooks install` **provisiona** o caminho
   classico (falso-negativo seguro — jamais deixar o projeto sem guarda);
   `doctor` reporta `undetermined` como aviso, exit 0.

## Scenario 8: Resolucao dual-path do runtime (FR-009/FR-012)

1. Invocar `state-rw.sh --help` (ou outro script do runtime) nos 3 modos:
   (a) com `CLAUDE_PLUGIN_ROOT` setado; (b) in-place no repo; (c) via
   `~/.claude/skills/` classico
2. Desfazer os 3 (env vazia + fora do repo + sem `~/.claude/skills/`) e
   invocar um hook de metrica e o `pretooluse-bash-guard.sh`
3. **Expected**:
   - (1) resolve nos 3 modos
   - (2) hook de **metrica**: diagnostico registrado, **exit 0** (fail-open
     preservado); `bash-guard`: bloqueia com `MECANISMO_FALHOU` (fail-closed
     preservado)
   - em nenhum caso ha falha silenciosa lendo path incorreto
