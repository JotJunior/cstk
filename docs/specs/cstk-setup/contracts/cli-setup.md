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

**Flags deliberadamente ausentes (FR-018)**: nao ha `--catalog` nem
qualquer equivalente, e nenhuma variavel de override de catalogo e
repassada aos comandos delegados. Ver §2.4.

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
<area>  <applied|already-configured|skipped|failed>  [escopo]  [motivo]
```

- `[escopo]` marca `global` apenas na area `state-backend` (FR-017); as
  demais sao de escopo projeto e nao recebem marca.
- Area com `status=divergent` aparece como `failed`, com `[motivo]`
  carregando a remediacao de duas etapas (§4.1, data-model).

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

   > **`.git` e marcador de onboarding, NAO fronteira de confianca.** O
   > teste responde "isto parece a raiz de um projeto?", evitando que um
   > `cstk setup` disparado no diretorio errado espalhe `.claude/` e
   > `.mcp.json` por ali. Ele **nao** atesta procedencia: `.git` e
   > trivialmente criavel, e um repo clonado de terceiro passa no teste
   > por construcao — e e exatamente o cenario que a feature mira. Toda
   > garantia de seguranca desta feature vem de FR-016 (verificar o que
   > esta registrado) e FR-018 (nao redirecionar a origem do catalogo);
   > nenhuma vem de FR-011. Endurecer FR-011 exigindo artefato do toolkit
   > foi rejeitado no clarify por circularidade, e nao daria a garantia
   > que FR-016 da.
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

> **Limite conhecido da coluna 3** (motiva 2.3, FR-016): `_gh_registered`
> (`guard-hooks-status.sh:119-127`) e busca textual do **basename** —
> `grep -Fq -- "$2" "$_gh_settings"`. O comentario no proprio script
> assume que "a presenca do basename e condicao necessaria e suficiente
> na pratica". Ela e **necessaria**, mas nao suficiente: um `settings.json`
> que cite o basename e execute outro programa marca `registered`. A
> coluna 4 protege o **conteudo** do arquivo em `.claude/hooks/`, nunca o
> **comando registrado**.

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

### 2.3 Verificacao de autenticidade do registro — `--verify-registration` **[PROPOSTA]**

**Invocacao**: `guard-hooks-status.sh check --projeto-alvo-path PATH --quiet --verify-registration`

Segunda extensao **aditiva** ao contrato 2.1, exigida por FR-016.
Acrescenta uma **5a coluna** TSV a cada linha:

| Valor | Significado |
|-------|-------------|
| `canonical` | Toda mencao ao basename no `settings.json` esta na forma canonica do snippet |
| `divergent` | Ha mencao ao basename que **nao** esta na forma canonica |
| `indeterminate` | Nao foi possivel atribuir o registro (hook nao registrado, `settings.json` ausente, ou layout que impeca a atribuicao por linha) |

**Forma canonica** — literal do catalogo, nao suposto
(`global/skills/agente-00c-runtime/hooks/settings.snippet.json`, e
`settings.loose-usage.snippet.json` para o hook opt-in):

```
"$CLAUDE_PROJECT_DIR"/.claude/hooks/<basename>
```

**Regra de decisao** (POSIX puro, sem `jq` — mesma restricao de 2.1):
toda linha do `settings.json` que contenha o basename MUST tambem conter
o fragmento canonico **e** o token literal `"command"` (a chave JSON,
com aspas). Existindo ao menos uma linha com o basename sem o fragmento
canonico, ou sem o token `"command"`, → `divergent`.

> **Correcao pos-gate (achado SEC-01, MEDIUM)**: a regra original exigia
> so basename+fragmento na mesma linha, satisfazivel por uma **linha-isca
> decorativa** — ex. um `"description"` ou comentario JSON informal que
> cite o basename e cole o fragmento canonico ao lado de um `"command"`
> real apontando para outro programa, em linhas diferentes do pretty-print
> do `merge_settings`. Exigir o token `"command"` na MESMA linha reduz o
> caso a exigir que a linha-isca seja, ela propria, uma atribuicao
> `"command": ...` — que e o unico lugar onde `merge_settings`
> (`jq` pretty-print, uma chave por linha) de fato emite o path executado.
>
> **Limite aceito, declarado (nao verificado textualmente)**: esta regra
> continua sendo co-ocorrencia textual por linha, nao parse de JSON. Ela
> **nao verifica posicionamento estrutural** — isto e, nao confirma que a
> linha `"command"` encontrada esta de fato dentro do objeto de hook
> correto sob `PreToolUse`/`matcher` esperado (poderia, em tese, estar sob
> uma chave nao-relacionada com o mesmo par `"command"` + fragmento
> coincidindo por acaso, ou um objeto de hook malformado que o
> `merge_settings` ainda assim aceitou). Elevar a essa garantia exigiria
> `jq` ou um parser real, fora do orcamento desta extensao pelo mesmo
> motivo do "Limite textual declarado" abaixo (minificacao). Residual
> aceito porque o objetivo desta extensao e fechar o caso de decoy mais
> barato de forjar (linha solta com o basename), nao alcancar paridade com
> parse estrutural.

**Invariantes obrigatorias da extensao**:

- Sem a flag, a saida e byte-a-byte identica a atual e o exit code e o de
  2.1 — retro-compatibilidade total com os consumidores existentes
  (README.md:279 e a prosa dos orquestradores).
- **Com** a flag, `divergent` em qualquer hook de `_GH_HOOKS` faz o exit
  ser `1` (mesma classe de "nao esta provisionado corretamente"). Isso e
  seguro porque a flag e opt-in: nenhum consumidor atual a passa.
- Runtime instalado anterior rejeita a flag em `_gh_die_usage`
  (`guard-hooks-status.sh:205`) com **exit 2**. O consumidor MUST tratar
  como `indeterminate` — e, por I5 do data-model, `indeterminate`
  **nesta chamada** (5a coluna) resolve `ConfigurationArea{hooks}.status`
  (e `mandatory_status`) para `unavailable` — nunca `configured`, e
  distinto de `divergent` (que exige confirmacao positiva de nao-canonico,
  nao mera impossibilidade de verificar). Ver data-model.md §invariante I5
  e §Nota `unavailable`.
- **Esta chamada e SEPARADA da chamada baseline** (§2.1, sem flags) e da
  chamada de `--include-loose-usage` (§2.2) — nunca as tres combinadas
  numa unica invocacao. Combina-las faria um runtime antigo que rejeita
  **qualquer uma** das flags (exit 2 em `_gh_die_usage`) perder tambem o
  veredito basico dos 3 hooks obrigatorios, que aquele runtime SABE
  responder. Ver data-model.md §Fonte de `status` por area, linha
  `hooks` (achado SEC-03).
- A verificacao e **read-only**, como todo o script (cabecalho: "READ-ONLY
  por construcao").

**Limite textual declarado**: a regra e por linha, e vale para o layout
que o proprio `merge_settings` produz (`jq` pretty-print). Um
`settings.json` minificado numa unica linha impede a atribuicao por linha
→ `indeterminate` (nunca `canonical`). Elevar a verificacao a parse real
exigiria `jq`, que o script deliberadamente nao usa por ser a dependencia
que costuma faltar justamente no projeto mal provisionado sob diagnostico
(comentario em `guard-hooks-status.sh:119-125`).

> **Nota de escopo**: promover esta verificacao a comportamento **default**
> (sem flag) beneficiaria tambem os orquestradores, mas mudaria formato de
> saida e exit code de um contrato publicado — BREAKING, exigindo bump
> MAJOR por Constitution I. Fica registrado como candidato para a proxima
> major, fora desta feature.

### 2.4 Aplicacao — `hooks install` **[EXISTENTE]**

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

> **FR-018 — os dois knobs de catalogo, e o que cada um faz**:
>
> | Knob | Quem le | Efeito |
> |------|---------|--------|
> | `--catalog DIR` (flag) | `hooks install` — default `${HOME}/.claude` (`cli/lib/hooks.sh:575`; origem dos hooks em `:612`) | redireciona **de onde o hook e copiado** |
> | `CSTK_HOOKS_CATALOG_DIR` (env) | apenas `guard-hooks-status.sh` (`:136-137`; cabecalho: "so para teste/diagnostico") | redireciona **a copia de referencia** da comparacao `current`/`stale` |
>
> `setup.sh` **nao expoe flag equivalente, nao repassa `--catalog` e nao
> define `CSTK_HOOKS_CATALOG_DIR`**. Expor o primeiro daria a um comando
> copiado de um README de terceiro o poder de provisionar um
> `pretooluse-bash-guard.sh` arbitrario com aparencia de instalacao
> oficial.
>
> O segundo e **herdado do ambiente** — nao ha como "nao repassar" uma
> variavel exportada sem apaga-la, e apaga-la quebraria diagnostico
> legitimo. Como um `CSTK_HOOKS_CATALOG_DIR` apontando para um diretorio
> arbitrario faz a dimensao `current`/`stale` medir contra a referencia
> errada, o comportamento exigido e **declarar, nao confiar**: detectada a
> variavel no ambiente, a area de hooks anuncia que a verificacao usou
> referencia nao-padrao e **nao** reporta `configured` com base nela.
> Note que ela nao afeta a verificacao de registro de §2.3 — a forma
> canonica ali e uma constante, nao lida do catalogo.
>
> Testes que precisem de catalogo alternativo devem invocar
> `hooks install` / `guard-hooks-status.sh` diretamente, nao via
> `cstk setup`.

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
>
> **FR-017 — rotulo obrigatorio na UI**: o usuario invoca `cstk setup`
> com um `--project-path` na mao e a expectativa razoavel de que esta
> configurando **aquele projeto**. Esta area quebra essa expectativa: o
> efeito e da maquina inteira. O wizard MUST, antes de aplicar **e** em
> `--dry-run`, nomear o alvo real (`$HOME/.claude/cstk/config`) e dizer
> que a mudanca vale para **todos os projetos**. As outras tres areas sao
> de escopo projeto e MUST NOT carregar esse rotulo — rotular tudo
> igualmente destreinaria o usuario a le-lo. O `SetupRunSummary` repete a
> marca de escopo na linha desta area.

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

### 4.1 Deteccao — `_mcp_registration_status` **[PROPOSTA]**

**Funcao**: `_mcp_registration_status PROJECT_PATH` em `cli/lib/mcp.sh`
(lib **dona** da area — mantem a deteccao junto do comando dedicado,
como FR-002 exige, em vez de uma segunda implementacao em `setup.sh`)
**Saida (stdout)**: `configured` \| `divergent` \| `not-configured`
**Exit**: `0` sempre (consulta respondida, nao veredito) — mesmo contrato
de nao-falha de `state-backend.sh resolve` (linha 269)

Leitura textual (sem `jq`), coerente com a mesma escolha ja feita por
`_gh_registered` (`guard-hooks-status.sh:119` e seguintes), que usa busca
textual em vez de parse justamente para nao depender de `jq` num projeto
possivelmente mal provisionado.

**Regra de decisao** (FR-016 — a presenca da chave nao basta):

| Condicao | Resultado |
|----------|-----------|
| `<project-path>/.mcp.json` ausente, ou sem mencao a `cstk-state` | `not-configured` |
| `cstk-state` presente **e** o `command` registrado e um dos paths candidatos de `mcp-launch.sh` do catalogo | `configured` |
| `cstk-state` presente e o `command` aponta para outro lugar, ou nao e atribuivel | `divergent` |

**Paths candidatos** — o conjunto que `_mcp_runtime_script_path`
(`cli/lib/mcp.sh:127-146`) produziria, nas tres camadas que ele consulta,
**todas** aceitas:

1. `command -v mcp-launch.sh` (PATH)
2. `$CSTK_LIB/../../global/skills/agente-00c-runtime/scripts/mcp-launch.sh` (repo)
3. `$HOME/.claude/skills/agente-00c-runtime/scripts/mcp-launch.sh` (catalogo instalado)

> **Por que o conjunto, e nao so o primeiro hit**: `_mcp_cmd_install`
> grava o path **resolvido no momento da instalacao** (`cli/lib/mcp.sh:840`,
> interpolado no bloco JSON). Um `.mcp.json` escrito por uma invocacao a
> partir do repo e depois verificado por uma invocacao a partir de
> `~/.claude` produziria paths diferentes para a **mesma** instalacao
> legitima. Comparar apenas contra o primeiro hit geraria `divergent`
> falso-positivo rotineiro em maquina de desenvolvimento. Aceitar as tres
> camadas preserva a propriedade que importa: o comando aponta para um
> `mcp-launch.sh` **do catalogo do toolkit**, nao para um programa
> arbitrario.

**Nao remedia sozinho**: `_mcp_cmd_install` faz merge com o target
vencendo ("entrada ja presente e equivalente => idempotente, exit 0",
linhas 800-802). Uma entrada divergente **sobrevive** a um novo
`cstk mcp install` — por isso `divergent` mapeia para `failed` com
remediacao em duas etapas (remover a entrada, depois reinstalar), nunca
para uma tentativa cega de aplicacao. Ver `data-model.md`, regras de
derivacao de `AreaOutcome`.

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
