# Contracts: cstk-setup — interface de linha de comando

Contrato do subcomando `cstk setup` (novo) e das fronteiras que ele
consome.

> **Marcacao de veracidade (Constitution VI)**:
> - Blocos marcados **[PROPOSTA]** descrevem interface **nova**, ainda
>   inexistente — a validar na implementacao.
> - Blocos marcados **[EXISTENTE]** descrevem comportamento ja no repo e
>   citam `arquivo:linha` verificado em 2026-08-07. Nenhum campo, flag ou
>   exit code de bloco [EXISTENTE] foi suposto.

---

## 1. `cstk setup` **[PROPOSTA]**

**Invocacao**: `cstk setup [--dry-run] [--yes] [--project-path PATH]`
**Funcao de entrada**: `setup_main` em `cli/lib/setup.sh`
**Resolucao**: ramo generico do dispatcher — `cli/cstk:250-273`; nome da
funcao derivado por `sed 's/-/_/g'` + `_main` (`cli/cstk:267`)

### Flags

| Flag | Tipo | Default | Descricao |
|------|------|---------|-----------|
| `--dry-run` | bool | off | Preview: exibe status e o que seria aplicado, sem escrever nada (FR-004). **Precede `--yes`** (FR-006) |
| `--yes` | bool | off | Nao-interativo: aplica o default recomendado de cada area nao configurada, sem prompt (FR-005) |
| `--project-path PATH` | path | `$PWD` | Raiz do projeto-alvo. MUST ser raiz de repo git (FR-011) |

### Precedencia de modo (FR-006)

```
--dry-run presente            -> mode=preview          (nada e aplicado)
--yes presente, sem --dry-run -> mode=non-interactive
nenhum dos dois               -> mode=interactive      (exige TTY, FR-007)
```

### Saida (stdout)

Por area, na ordem fixa de FR-001 (`hooks`, `state-backend`, `mcp`,
`telemetry`): bloco com o status atual e a acao. Ao final, o
`SetupRunSummary` (FR-010) com uma linha por area:

```
<area>  <applied|already-configured|skipped|failed>  [motivo]
```

Diagnosticos e avisos vao para **stderr** (Constitution II: "Mensagens de
erro em stderr, saida de dados em stdout").

### Exit codes **[PROPOSTA]**

| Code | Significado |
|------|-------------|
| `0` | Run completo — inclui areas puladas, ja configuradas e `--dry-run` |
| `1` | Pelo menos uma area terminou em `failed` |
| `2` | Uso incorreto (flag desconhecida) |
| `3` | Recusa por pre-condicao: fora de raiz de repo git (FR-011), ou terminal nao-interativo sem `--dry-run`/`--yes` (FR-007) |

Alinhado as constantes do binario (`cli/cstk:30-33`:
`CSTK_EXIT_OK=0`, `CSTK_EXIT_ERROR=1`, `CSTK_EXIT_USAGE=2`,
`CSTK_EXIT_LOCK=3`) e ao uso de `3` como "recusado por pre-condicao" ja
publicado por `cstk mcp install` (`cli/lib/mcp.sh:949-953`) e
`cstk state enable-sqlite` (`cli/lib/state.sh:26-28`).

### Pre-condicoes

1. **FR-011** — `[ -e "$PATH/.git" ]` (arquivo OU diretorio; worktree
   conta). Falha → exit 3, **zero escrita**.
2. **FR-007** — em `mode=interactive`, TTY obrigatorio via `require_tty`
   (`cli/lib/ui.sh:42-50`, teste `[ -t 0 ]` na linha 46, bypass
   `CSTK_FORCE_INTERACTIVE=1` na linha 43). Falha → exit 3 com mensagem
   apontando `--dry-run` ou `--yes`.

---

## 2. Fronteira: area de hooks

### 2.1 Deteccao — `guard-hooks-status.sh check` **[EXISTENTE]**

**Invocacao**: `guard-hooks-status.sh check --projeto-alvo-path PATH [--quiet]`
**Arquivo**: `global/skills/agente-00c-runtime/scripts/guard-hooks-status.sh`
**Contrato**: cabecalho linhas 49-60; implementacao `_gh_cmd_check` linhas 197-262

**Saida (stdout)** — uma linha TSV por hook, 4 campos:

| Campo | Valores |
|-------|---------|
| 1 — arquivo | `pretooluse-bash-guard.sh` \| `posttooluse-tool-call-tick.sh` \| `posttooluse-agent-usage.sh` (lista `_GH_HOOKS`, linhas 104-107) |
| 2 — presenca | `present` \| `missing` |
| 3 — registro | `registered` \| `unregistered` (basename aparece em `<PAP>/.claude/settings.json`) |
| 4 — frescor | `current` \| `stale` \| `unknown` (comparacao byte-a-byte com o catalogo) |

**Exit codes**: `0` os 3 present+registered+(current\|unknown); `1` caso
contrario (**inclui `stale`**); `2` uso incorreto.

**stderr**: diagnostico + comando de remediacao, suprimido por `--quiet`.

### 2.2 Deteccao do hook opt-in — `--include-loose-usage` **[PROPOSTA]**

**Invocacao**: `guard-hooks-status.sh check --projeto-alvo-path PATH --quiet --include-loose-usage`

Extensao **aditiva** ao contrato 2.1: acrescenta uma 4a linha TSV para
`posttooluse-loose-usage.sh` no mesmo formato de 4 campos.

**Invariantes obrigatorias da extensao**:

- **NAO altera o exit code**. O hook e opt-in; sua ausencia jamais e
  anomalia. O exit continua derivado apenas dos 3 hooks de `_GH_HOOKS`.
- Sem a flag, a saida e byte-a-byte identica a atual (retro-compatibilidade).
- Runtime instalado anterior a esta feature rejeita a flag desconhecida em
  `_gh_die_usage` (`guard-hooks-status.sh:205`) com **exit 2** — o
  consumidor MUST tratar isso como `loose_usage_status=indeterminate`,
  nunca como falha da area de hooks (FR-009).

**Justificativa**: `posttooluse-loose-usage.sh` existe no catalogo
(`global/skills/agente-00c-runtime/hooks/`, com
`settings.loose-usage.snippet.json` proprio) mas nao e coberto por
nenhuma fonte de deteccao read-only hoje. Ver research.md Decision 3.

### 2.3 Aplicacao — `hooks install` **[EXISTENTE]**

**Invocacao**: `hooks_main install --project-path PATH [--catalog DIR] [--dry-run] [--with-loose-usage]`
**Arquivo**: `cli/lib/hooks.sh` — `hooks_main` linha 557; flags linhas 583-593

`install` e o **unico** subcomando aceito (linha 566; erro "use: install"
na linha 568). **Nao existe `cstk hooks status`** — a deteccao vem de 2.1.

`--with-loose-usage` e **opt-in, default desligado** (linhas 513, 543).

**Estados internos** retornados por `apply_guard_hooks` (linha 318,
chamada na linha 625; documentados nas linhas 38-42; tratados nas linhas
627-649): `merged` \| `paste-instructed` \| `hooks-only` \|
`not-applicable` \| `error`.

**Exit codes**: `0` sucesso — **inclui `paste-instructed` e `hooks-only`,
que sao apenas warnings** (linhas 631-643); `1` erro (linhas 598, 608,
617, 644); `2` uso incorreto (linhas 568, 594).

**Guarda**: recusa `--project-path` igual a `$HOME` (linhas 617-620) —
"hooks 00c sao de escopo PROJETO".

> **Consequencia de projeto**: como exit 0 abrange `paste-instructed`
> (jq ausente → bloco para colar manualmente), o wizard NAO pode
> reportar `applied` cegamente com base no exit. Deve propagar o aviso ao
> summary; ver quickstart.md Cenario 7.

---

## 3. Fronteira: area de state backend **[EXISTENTE]**

### 3.1 Deteccao — `config_state_backend_resolve`

**Funcao**: `cli/lib/config.sh:94` (delega via `_config_delegate`, linha 76,
resolvido por `_config_state_backend_script_path`, linha 52)
**Script real**: `global/skills/agente-00c-runtime/scripts/state-backend.sh`,
subcomando `resolve` (`_sb_cmd_resolve`, linhas 234-269)

**Saida (stdout)**:

| Campo | Valores |
|-------|---------|
| `effective_backend=` | `sqlite` \| `json` |
| `reason=` | texto livre (ex. `nunca-configurado`) |

**Contrato de nao-falha**: `resolve` **nunca falha** — `return 0`
incondicional na linha 269 ("contrato de nao-falha FR-008").

### 3.2 Capacidade — `config_state_backend_capability`

**Funcao**: `cli/lib/config.sh:90` → `state-backend.sh capability` (linha 228).
Versao minima de `sqlite3`: `_SB_MIN_SQLITE_VERSION="3.45.1"`
(`state-backend.sh:67`).

### 3.3 Aplicacao — `config_state_backend_enable_sqlite`

**Funcao**: `cli/lib/config.sh:98` — o mesmo alvo que
`cstk state enable-sqlite` delega (`cli/lib/state.sh:122-131`, repassando
o exit **verbatim**; `command -v` na linha 124).
**Script real**: `_sb_cmd_enable_sqlite` (`state-backend.sh:358-397`).

**Efeito**: grava `state_backend=sqlite` em `$HOME/.claude/cstk/config`
(`_SB_CONFIG_DIR` linha 75, `_SB_CONFIG_FILE` linha 76), com diretorio
`700` e arquivo `600` (linhas 322-329).

**Exit codes** (documentados em `cli/lib/state.sh:26-28` e linha 97):
`0` sucesso; `1` falha; `2` uso incorreto; `3` **recusado por
pre-condicao** — `sqlite3` ausente ou abaixo do minimo (linhas 358-370).

**Idempotencia nativa**: se ja `state_backend=sqlite`, no-op e `return 0`
(linhas 385-390).

> **Escopo GLOBAL, nao de projeto**: esta e a unica das quatro areas que
> escreve fora do diretorio do projeto — em `$HOME/.claude/cstk/config`.
> Isso e comportamento preexistente do comando dedicado, nao introduzido
> pelo wizard, e nao conflita com FR-012 (que restringe apenas a area de
> telemetria). Tem consequencia direta em teste: exige `HOME` sandboxado
> (ver quickstart.md e research.md Decision 10).

### 3.4 Diagnostico complementar — `cstk doctor --deps` **[EXISTENTE]**

**Flag**: `cli/lib/doctor.sh:214`; implementacao `_doctor_deps_run` linhas 408-474.

**Campos impressos** (linhas 464-470):

```
sqlite3: presente=%s versao=%s minima=3.45.1
jq: presente=%s versao=%s
effective_backend: %s
reason: %s
```

Seguido de `[ANOMALY] ...` (linha 472) ou `sem anomalias.` (linha 474).
**Exit codes** (linhas 85-86): `0` sem anomalia; `1` com anomalia.

Reusado pelo wizard como texto de diagnostico quando a area fica
`unavailable`.

---

## 4. Fronteira: area de MCP **[EXISTENTE]**

### 4.1 Deteccao

Presenca da chave `cstk-state` sob `mcpServers` em
`<project-path>/.mcp.json` — exatamente o alvo que `_mcp_cmd_install`
escreve (`cli/lib/mcp.sh:847`; bloco JSON linhas 864-865).

Leitura textual (sem `jq`), coerente com a mesma escolha ja feita por
`_gh_registered` (`guard-hooks-status.sh:119` e seguintes), que usa busca
textual em vez de parse justamente para nao depender de `jq` num projeto
possivelmente mal provisionado.

### 4.2 Aplicacao — `cstk mcp install`

**Funcao**: `_mcp_cmd_install` (`cli/lib/mcp.sh:806-877`)
**Efeito**: registra a entrada estatica `mcpServers.cstk-state` em
`<project-path>/.mcp.json`, com `command` apontando para `mcp-launch.sh`
resolvido do catalogo (linhas 837-840).

**Idempotencia nativa**: via `merge_settings` (target vence em conflito) —
"entrada ja presente e equivalente => idempotente, exit 0"
(comentario linhas 800-802).

**Sem `jq`**: cai em `print_paste_block` e **ainda retorna 0**
(linhas 866-871) — nao falha por ausencia de `jq`.

**Exit codes** (documentados linhas 949-953): `0` criada / ja presente /
`--dry-run`; `1` erro IO/merge ou catalogo sem `mcp-launch.sh`; `2` uso
incorreto; `3` recusa `--project-path` = `$HOME` (linhas 831-835).

### 4.3 Docker — diagnostico apenas

`status=active` (`cli/lib/mcp.sh:259`) \| `status=stopped` (linha 239) \|
`status=unavailable` (linhas 203, 250), via `_mcp_cmd_status` (linha 371).

**Confinamento**: toda invocacao funcional de `docker` vive em
`cli/lib/mcp-docker.sh` (`_mcp_docker_preflight`; cabecalho linhas 1-11
declara ser o "UNICO ponto de invocacao FUNCIONAL de docker").
`cli/lib/mcp.sh` usa `command -v docker` apenas para escolher o motivo
`docker-absent` (linhas 475-479).

**FR-015**: em `--yes`, a area MCP aplica `mcp install` **mesmo sem
Docker**, emitindo aviso claro. `setup.sh` **NAO** invoca `docker`
diretamente — no maximo `command -v docker` para o texto do aviso, mesmo
padrao de `cli/lib/mcp.sh:475-479`.

---

## 5. Fronteira: area de telemetria **[EXISTENTE]** — read-only

### 5.1 Deteccao — `otel-usage.sh preflight`

**Arquivo**: `global/skills/agente-00c-runtime/scripts/otel-usage.sh`
**Subcomando**: `preflight` — `_ou_cmd_preflight` linha 469; flag
`--endpoint URL` linha 473; documentado na linha 545; dispatch linhas
534-536. Responde "a telemetria DESTA sessao vai ser medida?" (linha 561).

Demais subcomandos existentes: `available`, `snapshot`, `delta`.

**Nao existe `cli/lib/otel*.sh`** — verificado. A unica superficie e o
script do catalogo.

### 5.2 Instrucoes exibidas (nunca escritas — FR-012)

Valores extraidos do `README.md`, secao de custo por onda:

| Variavel / valor | Fonte |
|------------------|-------|
| `CLAUDE_CODE_ENABLE_TELEMETRY=1` | README.md:306 |
| `OTEL_METRICS_EXPORTER=prometheus` | README.md:307 |
| `CSTK_OTEL_ENDPOINT` | README.md:317, 349 |
| `OTEL_EXPORTER_PROMETHEUS_PORT` | README.md:348 |
| endpoint padrao `127.0.0.1:9464` | README.md:315 |
| wrapper `claude()` em `~/.zshrc` (sorteia porta livre) | README.md:342-354 |

**FR-012**: o wizard **NAO escreve** em `~/.zshrc` nem em qualquer arquivo
fora do diretorio do projeto para esta area. Outcome possivel:
`already-configured` \| `skipped` \| `failed`. **`applied` e
inalcancavel** para telemetria.
