# Contract: Consciencia de plugin no binario cstk

Mudancas de comportamento no CLI **existente**. Superficie atual verificada
em `cli/lib/doctor.sh` e `cli/lib/hooks.sh` (fonte S7).

> **Principio de compatibilidade (FR-010/SC-006)**: nenhum subcomando muda
> de comportamento quando o plugin **nao** esta habilitado. Todo o
> comportamento novo e condicionado a deteccao positiva.

## Helper compartilhado: deteccao de plugin

**Local**: `cli/lib/plugin-detect.sh` `[PROPOSTA]`
**Consumidores**: `doctor.sh`, `hooks.sh`, `setup.sh`.

| Funcao | stdout | Exit |
|--------|--------|------|
| `plugin_enabled <nome>` | — | `0` = instalado **e** habilitado; `1` = nao; `2` = indeterminado |
| `plugin_install_path <nome>` | path absoluto | `0` ok; `1` nao encontrado |
| `plugin_hooks_present <nome>` | — | `0` = `<installPath>/hooks/hooks.json` existe e e legivel; `1` = nao |

### Habilitado NAO implica funcional (finding de seguranca F4, MEDIUM)

`plugin_enabled` prova apenas **intencao** registrada (instalado + `true` em
`enabledPlugins`). Nao prova que o conteudo foi materializado e que os hooks
existem: `installPath` pode apontar para diretorio removido, instalacao
parcial, ou versao sem `hooks/hooks.json`.

**Consequencia se ignorado**: `cstk hooks install` pularia o provisionamento
classico ("plugin vence") enquanto o plugin, na pratica, nao registra hook
nenhum — deixando o projeto **sem nenhuma camada de guarda**, silenciosamente.
E o pior resultado possivel do dedup, e vem justamente do caminho feliz.

**Regra**: o skip do provisionamento classico MUST exigir as **tres**
condicoes — instalado **e** habilitado **e** `plugin_hooks_present == 0`.
Faltando a terceira, `hooks install` **provisiona normalmente** e emite
aviso de inconsistencia. Duplicacao e detectavel e remediavel por `doctor`;
ausencia total de guarda nao e detectavel pelo operador.

### Fontes lidas (read-only — nunca escritas)

| Sinal | Arquivo `[REAL]` | Campo |
|-------|------------------|-------|
| Instalado | `~/.claude/plugins/installed_plugins.json` | `.plugins["<nome>@<mkt>"][].installPath` |
| Habilitado | `~/.claude/settings.json` | `.enabledPlugins["<nome>@<mkt>"] == true` |

**Ambos sao exigidos.** Evidencia: em S4/S6 os 3 plugins instalados estao
com `enabledPlugins == false` — instalado nao implica habilitado.

### Degradacao (obrigatoria)

| Situacao | Resultado |
|----------|-----------|
| Arquivo ausente | exit 1 (nao habilitado) |
| JSON malformado / `jq` ausente | exit 2 (indeterminado) |
| Exit 2 em qualquer consumidor | Trata como **nao habilitado** e segue o caminho classico |

> Falha de deteccao **nunca** pode suprimir a camada classica de guardas —
> isso removeria a unica protecao presente. Assimetria deliberada:
> falso-negativo custa uma duplicacao detectavel por `doctor`;
> falso-positivo custa um projeto **sem nenhuma guarda**.

## `cstk hooks install` (FR-005)

**Superficie atual `[REAL]`**: `cstk hooks install [--scope global|project]
[--dry-run] [--with-loose-usage]`. **Nenhuma flag nova.**

| Condicao | Comportamento |
|----------|---------------|
| `plugin_enabled` == 0 **e** `plugin_hooks_present` == 0 | **MUST NOT** registrar o snippet classico em `settings.json`. Emite aviso explicando que o plugin ja provê os hooks e, se houver registro classico pre-existente, orienta a remocao |
| `plugin_enabled` == 0 **mas** `plugin_hooks_present` != 0 | **Provisiona normalmente** + aviso de inconsistencia (plugin habilitado sem `hooks.json` materializado) — F4 |
| `plugin_enabled` != 0 | Comportamento **identico** ao atual |

**Exit code**: `0` no caso de skip (nao e erro — e o estado desejado).
**Copia de scripts**: no caso de skip, os scripts **nao** sao copiados para
`.claude/hooks/` (sem copia, sem registro — evita orfaos).

## `cstk setup` (FR-005)

Mesma regra do `hooks install`: quando o plugin esta habilitado, a etapa de
provisionamento de hooks e pulada com aviso; as demais etapas do setup
seguem inalteradas.

## `cstk doctor` (FR-007, FR-008)

**Superficie atual `[REAL]`**: `--scope`, `--fix`, `--deps`. **Nenhuma flag
nova** — o relatorio de alinhamento entra na saida padrao, condicionado a
deteccao (mantendo SC-006: quem nao usa plugin nao ve ruido novo).

### Secao nova: `Distribution Paths`

Emitida **apenas** quando o plugin e detectado como habilitado.

| `status` | Condicao | Saida | Exit |
|----------|----------|-------|------|
| `classic-only` | plugin nao habilitado | secao omitida | inalterado |
| `plugin-only` | so plugin | informativa | `0` |
| `aligned` | ambos, `hash_dir` igual | `OK: catalogo classico e plugin alinhados` | `0` |
| `diverged` | ambos, hash diferente | Aponta **qual** difere + remediacao | `1` |
| `duplicated-hooks` | plugin habilitado **e** snippet classico no `settings.json` do projeto | Reporta duplicacao + remediacao | `1` |
| `undetermined` | registros ilegiveis | Aviso; degrada para `classic-only` | `0` |

### Criterio de alinhamento

`hash_dir` do conteudo (mecanismo ja existente no doctor, S7), comparando
`~/.claude/skills/<skill>` contra `<installPath>/skills/<skill>`.

**MUST NOT** usar o campo `version` do registro nativo como criterio:
S4 mostra `"version": "unknown"` numa entrada real. Decisao ratificada no
clarify e confirmada empiricamente (research.md Decision 5).

### Remediacao (texto acionavel — FR-007)

| Status | Remediacao emitida |
|--------|--------------------|
| `diverged` (classico stale) | `cstk update` |
| `diverged` (plugin stale) | `/plugin update cstk@cstk` |
| `duplicated-hooks` | Remover o bloco de hooks do cstk de `<projeto>/.claude/settings.json` (o plugin ja os provê) |

## `cstk update` / `cstk self-update` (FR-007)

**Sem mudanca funcional.** Apenas mensagem de escopo quando o plugin e
detectado, para o operador nunca supor que um comando atualizou o que
pertence ao outro mecanismo:

```
Nota: o catalogo tambem esta disponivel via plugin do Claude Code
(habilitado neste ambiente). `cstk update` atualiza a instalacao
CLASSICA em ~/.claude; o catalogo do plugin e atualizado pelo
mecanismo nativo de plugins. Rode `cstk doctor` para comparar.
```

`cstk self-update` continua sendo o unico caminho do binario (FR-006) — o
formato de plugin nao instala binario persistente no PATH (`bin/` entra no
PATH **apenas durante a sessao**, S8).

## Matriz de nao-regressao (SC-003 / SC-006)

| Cenario | Esperado |
|---------|----------|
| Sem plugin, tudo como hoje | Zero diferenca observavel em qualquer subcomando |
| Plugin habilitado, `cstk recall`/`usage`/`mcp`/`session` | Funcionam identicamente |
| Plugin habilitado, `hooks install` | Skip com aviso, exit `0` |
| Plugin habilitado + registro classico pre-existente | `doctor` reporta `duplicated-hooks` com remediacao |
| `installed_plugins.json` corrompido | Degrada para classico; nenhum comando falha |
