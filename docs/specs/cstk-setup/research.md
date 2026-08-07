# Research: cstk-setup (Guided Project Setup Wizard)

Documento produzido no Phase 0 do `/plan`. Resolve todos os `NEEDS
CLARIFICATION` do Technical Context antes do design.

> **Aterramento (Constitution VI)**: toda afirmacao sobre comportamento
> existente abaixo cita `arquivo:linha` verificado no repo em 2026-08-07,
> branch `feature/cstk-setup`. Lacunas nao verificaveis estao marcadas
> explicitamente como **[PROPOSTA]** (design novo, a validar na
> implementacao), nunca afirmadas como comportamento existente.

---

## Decision 1: Ponto de integracao no dispatcher do binario

**Decision**: `setup` entra no ramo generico de dispatch de `cli/cstk`,
sem tratamento especial. Concretamente: adicionar o token `setup` ao
`case` de `cli/cstk:250`, criar `cli/lib/setup.sh` definindo a funcao
`setup_main`, e acrescentar `setup` as listas de comandos validos de
`cli/cstk:217` e `cli/cstk:299` mais o help geral (`cli/cstk:136-152`) e
o `case` de help por subcomando (`cli/cstk:169-211`).

**Rationale**: o ramo generico (`cli/cstk:250-273`) ja faz tudo o que
`setup` precisa — roda `_check_bin_lib_match` (`cli/cstk:253-256`),
resolve `_lib_file="$CSTK_LIB/${_cmd}.sh"` (`cli/cstk:257`), sourceia
(`cli/cstk:265`) e deriva o nome da funcao por
`sed 's/-/_/g'` + sufixo `_main` (`cli/cstk:267`). Como `setup` nao tem
hifen nem comeca com digito, `setup_main` sai direto da convencao. Nao ha
motivo para o special-casing de `00c` (`cli/cstk:274-291`), que existe so
porque nome de funcao nao pode comecar com digito.

**Alternatives considered**:
- *Ramo dedicado no `case`* (como `serve`, `cli/cstk:248-250`): rejeitado
  — `serve` tem ramo proprio por razoes proprias; `setup` nao precisa de
  pre-processamento algum, e um ramo dedicado seria codigo morto.
- *Skill/slash-command do Claude Code*: rejeitado pela propria spec —
  FR-014 fixa "subcomando do binario CLI", decisao ja tomada no clarify
  (spec.md linha 11).

**Lacuna registrada**: sem `setup` no `case` de `cli/cstk:250`, o comando
cai no ramo `*)` de comando desconhecido (`cli/cstk:215-219` no help,
`cli/cstk:299` no dispatch) — ou seja, esquecer qualquer uma das 4 listas
produz UX inconsistente (comando funciona mas nao aparece no help, ou
vice-versa). Vira item de checklist na implementacao.

---

## Decision 2: Fonte de deteccao de status por area (FR-002 / FR-013)

**Decision**: `setup.sh` NUNCA reimplementa deteccao. Cada area delega a
uma fonte read-only ja existente, consultada fresca a cada invocacao
(FR-013 — nunca um flag persistido "setup ja rodou"):

| Area | Fonte de deteccao (read-only) | Saida consumida |
|------|-------------------------------|-----------------|
| Hooks (obrigatorios) | `global/skills/agente-00c-runtime/scripts/guard-hooks-status.sh check --projeto-alvo-path PATH --quiet` (contrato: cabecalho linhas 49-60; implementacao `_gh_cmd_check` linhas 197-262) | TSV `<arquivo>\t<present\|missing>\t<registered\|unregistered>\t<current\|stale\|unknown>`, uma linha por hook; exit 0 = os 3 present+registered+(current\|unknown), exit 1 caso contrario (inclui `stale`) |
| Hooks (loose usage, opt-in) | **[PROPOSTA]** ver Decision 3 | — |
| State backend | `config_state_backend_resolve` (`cli/lib/config.sh:94`), que delega a `state-backend.sh resolve` (`global/skills/agente-00c-runtime/scripts/state-backend.sh:234-269`) | `effective_backend=sqlite\|json` + `reason=...`; **nunca falha** (`return 0`, linha 269, "contrato de nao-falha FR-008") |
| State backend (deps) | `config_state_backend_capability` (`cli/lib/config.sh:90`) → `state-backend.sh capability` (linha 228) | disponibilidade de `sqlite3` vs minimo `_SB_MIN_SQLITE_VERSION="3.45.1"` (linha 67) |
| MCP | leitura textual de `<project>/.mcp.json` procurando a chave `cstk-state` (o alvo que `_mcp_cmd_install` escreve — `cli/lib/mcp.sh:847`, bloco JSON linhas 864-865) | presente/ausente |
| Telemetria | `global/skills/agente-00c-runtime/scripts/otel-usage.sh preflight [--endpoint URL]` (`_ou_cmd_preflight`, linha 469; flag `--endpoint` linha 473; documentado linha 545) | responde "a telemetria DESTA sessao vai ser medida?" (linha 561) |

**Rationale**: e a mesma disciplina que `guard-hooks-status.sh` documenta
para si mesmo (cabecalho linhas 88-92): "Provisionar e trabalho do
`cstk install --scope project` (unica fonte da regra); reimplementar a
copia aqui duplicaria a regra em dois lugares — mesmo motivo pelo qual o
hook PreToolUse delega a decisao a `bash-guard.sh` em vez de
reimplementa-la." FR-002 exige literalmente "usando a mesma logica de
deteccao do comando dedicado daquela area"; delegacao e a unica forma de
garantir isso sem drift.

**Alternatives considered**:
- *Rodar o comando de aplicacao em `--dry-run` para inferir status*:
  rejeitado para deteccao. `hooks install --dry-run` (`cli/lib/hooks.sh:589`)
  reporta o PLANO ("copiaria X -> Y", linhas 351-376), nao o estado atual;
  nao distingue "ja instalado" de "seria instalado". Serve para preview
  (Decision 5), nao para status.
- *Persistir um marcador `.cstk-setup-done`*: rejeitado por FR-013, que
  proibe explicitamente flag persistido — e corretamente, porque o estado
  real pode mudar por fora do wizard (alguem roda `cstk hooks install`
  sozinho, ou o catalogo evolui e a copia fica `stale`).

**Consequencia de projeto**: a dimensao `stale` do `guard-hooks-status.sh`
(3a coluna do TSV) significa que "hooks presentes e registrados" NAO
implica "configurado". O wizard MUST tratar `stale` como *nao
configurado* (oferecer aplicar), espelhando o exit 1 do proprio `check`.

---

## Decision 3: Deteccao do hook opt-in de loose usage (FR-008 / US4)

**Decision** **[PROPOSTA — a validar na implementacao]**: estender
`guard-hooks-status.sh check` com uma flag nova
`--include-loose-usage`, que acrescenta ao TSV uma 4a linha para
`posttooluse-loose-usage.sh` no MESMO formato das outras
(`<arquivo>\t<present|missing>\t<registered|unregistered>\t<current|stale|unknown>`),
e que NAO altera o exit code (o hook e opt-in; sua ausencia nunca e
anomalia). Sem a flag, o comportamento atual permanece byte-a-byte
identico.

**Rationale**: existe uma lacuna real. A lista `_GH_HOOKS`
(`guard-hooks-status.sh:104-107`) cobre exatamente os 3 hooks
obrigatorios provisionados por `apply_guard_hooks()`; o
`posttooluse-loose-usage.sh` existe no catalogo
(`global/skills/agente-00c-runtime/hooks/posttooluse-loose-usage.sh`, com
snippet separado `settings.loose-usage.snippet.json`) mas **nao e
coberto por nenhuma fonte de deteccao read-only hoje**. Como FR-008 exige
apresentar a decisao do loose usage como escolha DISTINTA — e FR-002
exige mostrar o status antes de oferecer — o wizard precisa dessa
deteccao. Colocar um `grep` ad-hoc dentro de `setup.sh` violaria a
disciplina da Decision 2 (duplicaria a regra "present + registered" em
dois arquivos). Estender a fonte canonica mantem uma unica implementacao.

**Alternatives considered**:
- *Checagem local em `setup.sh`*: rejeitada — duplica `_gh_present`
  (linha 110) e `_gh_registered` (linha 119), justamente o antipadrao que
  o cabecalho do proprio script condena.
- *Subcomando novo `guard-hooks-status.sh loose-usage-status`*:
  rejeitado — mais superficie de contrato para a mesma pergunta; a flag
  reusa o parser e o formato de saida ja existentes.
- *Nao mostrar status do loose usage, so perguntar*: rejeitado — viola
  FR-002 (status antes de oferecer) e quebra FR-003 na segunda execucao
  (perguntaria de novo algo ja configurado).

**Custo de sincronizacao (GOTCHA)**: `guard-hooks-status.sh` e
**catalogo** (skill `agente-00c-runtime`), nao runtime do binario.
Alterar esse arquivo exige `cstk install`/`cstk update` para sincronizar
`~/.claude`, enquanto `cli/lib/setup.sh` + `cli/cstk` exigem
`cstk self-update`. Esta feature toca as DUAS metades — atualizar so uma
reproduz o sintoma classico "fix funciona no repo mas nao na sessao"
(CLAUDE.md §Installed vs Source Drift). Vira item obrigatorio de
quickstart e de checklist de release.

**Degradacao**: se o `guard-hooks-status.sh` instalado for anterior a
esta feature, a flag desconhecida cai em `_gh_die_usage`
(`guard-hooks-status.sh:205`) com exit 2. O wizard MUST tratar exit 2
dessa chamada como *status indeterminado* para a sub-area loose-usage
(reportando o motivo), nunca como falha da area de hooks inteira —
coerente com FR-009 (falha de uma area nao impede as demais).

---

## Decision 4: Aplicacao por area — delegacao aos comandos dedicados

**Decision**: cada area aplica invocando o comando dedicado existente,
com os exit codes mapeados para o vocabulario de outcome do wizard:

| Area | Acao de aplicacao | Exit codes da fonte |
|------|-------------------|---------------------|
| Hooks | `hooks_main install --project-path PATH [--with-loose-usage]` (`cli/lib/hooks.sh:557`, subcomando unico `install` linha 566, flags linhas 583-593) | 0 sucesso (inclui `paste-instructed`/`hooks-only`, tratados como warning nas linhas 631-643); 1 erro (598, 608, 617, 644); 2 uso incorreto (568, 594) |
| State backend | `config_state_backend_enable_sqlite` (`cli/lib/config.sh:98`), o mesmo alvo que `cstk state enable-sqlite` delega (`cli/lib/state.sh:122-131`, repassando exit verbatim) | 0 sucesso; 1 falha; 2 uso incorreto; 3 recusado por pre-condicao — `sqlite3` ausente ou < `3.45.1` (`state-backend.sh:358-370`) |
| MCP | `cstk mcp install --project-path PATH` (`_mcp_cmd_install`, `cli/lib/mcp.sh:806-877`) | 0 criada/ja presente/dry-run; 1 erro IO/merge/catalogo; 2 uso; 3 recusa `$HOME` (linhas 831-835; contrato documentado 949-953) |
| Telemetria | **nenhuma** — area e read-only por FR-012 | — |

**Rationale**: FR-002 exige a mesma logica de deteccao do comando
dedicado; a simetria natural e que a APLICACAO tambem seja o comando
dedicado. Isso satisfaz de graca o edge case da spec (linhas 168-173):
"o wizard MUST deixar a configuracao daquela area em estado consistente
com o que rodar o comando dedicado deixaria na mesma falha" — trivialmente
verdadeiro se e literalmente o mesmo comando.

Ganho colateral em FR-003: `mcp install` ja e idempotente por construcao
(`merge_settings`, target vence — comentario `cli/lib/mcp.sh:800-802`) e
`enable-sqlite` ja e no-op quando o backend ja e sqlite
(`state-backend.sh:385-390`). A guarda de FR-003 no wizard (nao chamar
nada quando ja configurado) e portanto defesa em profundidade, nao a
unica linha de defesa.

**Alternatives considered**:
- *`setup.sh` escrever `settings.json` / `.mcp.json` / config global
  diretamente*: rejeitado — reimplementaria merge, permissoes (dir 700 /
  arquivo 600, `state-backend.sh:322-329`) e fallback sem `jq`
  (`cli/lib/mcp.sh:866-871`), triplicando regra critica.
- *Invocar via `cstk <sub>` em subprocesso*: rejeitado como default.
  `setup.sh` e sourceado pelo mesmo processo que ja resolveu `CSTK_LIB`
  (`cli/cstk:265`, `cli/cstk:305`), entao pode sourcear as libs irmas pelo
  padrao ja estabelecido `. "${CSTK_LIB:?CSTK_LIB must be set}/<lib>.sh"`
  (`cli/lib/hooks.sh:60`, `cli/lib/doctor.sh:51-59`, `cli/lib/list.sh:31-41`)
  e chamar as funcoes diretamente — sem custo de subprocesso e sem
  depender do binario estar no `PATH`. Scripts do **catalogo**
  (`guard-hooks-status.sh`, `otel-usage.sh`) nao sao sourceaveis e seguem
  como invocacao de processo.

**Restricao de isolamento (FR-009)**: como as libs sao sourceadas no
mesmo shell, uma area que falhe NAO pode derrubar o wizard. `cli/lib`
roda sob `set -eu` (Constitution II). Consequencia de projeto: toda
chamada de aplicacao MUST ser feita em contexto que neutralize o
`set -e` (`if ! fn ...; then` ou `fn ... || rc=$?`), nunca como comando
solto. Item de checklist.

---

## Decision 5: Preview (FR-004) e nao-interativo (FR-005/FR-006)

**Decision**: tres modos mutuamente resolvidos por precedencia fixa:

1. `--dry-run` (preview) — **vence sempre** (FR-006). Para cada area:
   exibe status atual + o que seria aplicado. Onde a fonte oferece dry-run
   nativo, delega (`hooks install --dry-run`, `cli/lib/hooks.sh:589`,
   plano impresso nas linhas 351-376; `mcp install --dry-run`,
   `cli/lib/mcp.sh:848`). Onde nao oferece (`enable-sqlite` nao tem flag
   de dry-run — `state-backend.sh:358-397`), o wizard imprime a intencao
   sem executar. Zero escrita, sempre.
2. `--yes` (nao-interativo) — aplica o default recomendado de cada area
   ainda nao configurada, sem prompt (FR-005).
3. interativo (default) — um prompt por area, mais o prompt aninhado do
   loose usage (FR-008).

**Nomes de flag** **[PROPOSTA]**: `--dry-run` e `--yes`. `--dry-run` e o
nome ja usado por `hooks install` (`cli/lib/hooks.sh:589`), `mcp install`
(`cli/lib/mcp.sh` contrato 949-953) e `cstk usage prune` — reusar o termo
evita um terceiro vocabulario. `--yes` **[PROPOSTA]** nao tem precedente
verificado no repo para "nao-interativo"; e escolha nova.

**Rationale**: FR-006 fixa a precedencia preview > nao-interativo. A
delegacao de preview aos dry-runs nativos e o que torna SC-003 ("100% das
mudancas de um run real sao visiveis no preview") verificavel em vez de
aspiracional: o texto do preview vem do mesmo codigo que aplica.

**Alternatives considered**:
- *`--non-interactive` em vez de `--yes`*: descartado por verbosidade;
  ambos sao invencao nova, e `--yes` casa com a semantica "aceite os
  defaults".
- *Preview reimplementado em `setup.sh`*: rejeitado — divergiria do que e
  de fato aplicado, quebrando SC-003 silenciosamente.

**Default recomendado por area em `--yes`** (FR-005/FR-015):

| Area | Default recomendado | Fundamento |
|------|---------------------|------------|
| Hooks obrigatorios | aplicar | sao "obrigatorios" por definicao (`guard-hooks-status.sh` cabecalho linhas 14-22 documenta o dano de ficarem ausentes) |
| Loose usage (opt-in) | **NAO aplicar** | opt-in explicito e garantia existente — `--with-loose-usage` e default desligado (`cli/lib/hooks.sh:513`, `543`); CLAUDE.md §"Consumo avulso": "NUNCA bundlado silenciosamente ... sem a flag" |
| State backend | aplicar (`enable-sqlite`) | recomendado da linha v6; recusa limpa com exit 3 quando `sqlite3` falta (`state-backend.sh:358-370`) |
| MCP | aplicar mesmo sem Docker | FR-015 literal (spec linhas 236-240), com aviso de Docker ausente |
| Telemetria | diagnosticar | FR-012 proibe aplicar |

O default do loose usage em `--yes` e o unico "nao aplicar" da tabela, e
e deliberado: FR-008 protege um opt-in de privacidade preexistente, e
`--yes` significa "aceite os defaults", nao "aceite tudo".

---

## Decision 6: Terminal nao-interativo e prompt y/n (FR-007)

**Decision**: no modo interativo (nem `--dry-run` nem `--yes`), o wizard
checa TTY antes de qualquer prompt e falha rapido citando as duas flags.
Reusa `require_tty` (`cli/lib/ui.sh:42-50`), que testa `[ -t 0 ]`
(linha 46), honra o bypass `CSTK_FORCE_INTERACTIVE=1` (linha 43) e emite
`log_error` + `return 1` (linhas 49-50). O helper de prompt y/n e novo:
`_setup_prompt_yn` **[PROPOSTA]**, local a `cli/lib/setup.sh`.

**Rationale**: **nao existe helper y/n generico reutilizavel no repo** —
verificado: o unico prompt y/n e inline dentro de `ui_select_interactive`
(`cli/lib/ui.sh:279-288`: `printf 'Confirmar? [y/N] '` linha 279,
`IFS= read -r` linha 282, aceita `y|Y|yes|YES|s|S|sim|SIM` linha 285).
Reusar `require_tty` (que existe) e criar so o que falta e a divisao
correta. O novo helper MUST aceitar o mesmo conjunto de respostas
afirmativas da linha 285, para o usuario nao encontrar duas gramaticas de
confirmacao diferentes dentro do mesmo binario.

O bypass `CSTK_FORCE_INTERACTIVE=1` e o que torna os cenarios
interativos testaveis sem TTY real — e o mecanismo que `install.sh:126` e
`update.sh:112` ja usam via `require_tty`.

**Alternatives considered**:
- *Promover `_setup_prompt_yn` a `ui.sh` de saida*: adiado. Extrair o y/n
  de dentro de `ui_select_interactive` para um helper compartilhado
  mudaria um caminho interativo ja estavel sem necessidade nesta feature.
  Se um terceiro consumidor aparecer, a extracao se justifica.
- *`[ -t 0 ]` direto em `setup.sh`* (como `update.sh:599`): rejeitado —
  perderia o bypass `CSTK_FORCE_INTERACTIVE` e a mensagem padronizada.

---

## Decision 7: Gate de diretorio de projeto (FR-011)

**Decision**: o wizard recusa rodar quando o diretorio alvo nao e raiz de
repositorio git, testando a existencia de `.git` como arquivo OU
diretorio (`[ -e "$dir/.git" ]`), e sai antes de qualquer escrita.

**Rationale**: e literalmente o marcador que o clarify fixou (spec.md
linha 12 e FR-011, linhas 219-225): "raiz de repositorio git (presenca de
`.git`, arquivo ou diretorio — worktrees contam); nao exige artefatos do
toolkit, para evitar circularidade com o proprio onboarding". Testar
`-e` (e nao `-d`) e o que faz worktree contar: em worktree, `.git` e um
arquivo-ponteiro, nao diretorio.

**Alternatives considered**:
- *`git rev-parse --show-toplevel`*: rejeitado — adiciona dependencia de
  `git` no PATH para uma checagem que `test -e` resolve, e resolveria
  para a raiz mesmo invocado de um subdiretorio, o que **muda a
  semantica**: FR-011 diz "raiz", nao "dentro de".
- *Exigir `.claude/` ou `docs/constitution.md`*: rejeitado
  explicitamente pela spec (FR-011, linhas 223-225) por circularidade.

**Guarda complementar herdada**: tanto `hooks install` (`cli/lib/hooks.sh:617-620`)
quanto `mcp install` (`cli/lib/mcp.sh:831-835`, exit 3) ja recusam
`--project-path` igual a `$HOME`. O gate do wizard e adicional, nao
substituto.

---

## Decision 8: Area de telemetria — diagnostico apenas (FR-012)

**Decision**: a area de telemetria roda
`otel-usage.sh preflight` (`_ou_cmd_preflight`,
`global/skills/agente-00c-runtime/scripts/otel-usage.sh:469`; dispatch
linhas 534-536) para diagnosticar, e exibe as instrucoes de ativacao
manual. Nao escreve nada, e o outcome possivel e apenas
`ja configurado` / `nao configurado (instrucoes exibidas)` / `falha`.

**Valores exibidos** — extraidos do README, nunca inventados:
`CLAUDE_CODE_ENABLE_TELEMETRY=1` (README.md:306),
`OTEL_METRICS_EXPORTER=prometheus` (README.md:307), `CSTK_OTEL_ENDPOINT`
(README.md:317 e 349), `OTEL_EXPORTER_PROMETHEUS_PORT` (README.md:348),
endpoint padrao `127.0.0.1:9464` (README.md:315), e o wrapper `claude()`
de `~/.zshrc` que sorteia porta livre (README.md:342-354).

**Rationale**: a ativacao depende de variaveis exportadas no shell do
usuario (o wrapper vive em `~/.zshrc`), fora do diretorio do projeto.
FR-012 proibe escrever fora do projeto; a spec ja antecipa isso no edge
case das linhas 174-178. Nao existe `cli/lib/otel*.sh` — verificado; a
unica superficie e o script do catalogo.

**Alternatives considered**:
- *Escrever no `~/.zshrc` do usuario*: **proibido** por FR-012. Alem
  disso colidiria com o Principio IV (zero coleta remota) na percepcao do
  usuario, e mexer no rc do shell alheio e irreversivel na pratica.
- *Escrever um `.envrc`/script no projeto*: descartado — nao ativa nada
  sozinho (o wrapper precisa envolver a invocacao do `claude`), entao
  seria configuracao morta com aparencia de configuracao viva.

**Consequencia**: a area de telemetria nunca reporta `applied`. O
vocabulario de outcome (data-model.md) precisa acomodar isso sem mentir —
ver entidade `AreaOutcome`.

---

## Decision 9: Contrato de exit code do `cstk setup`

**Decision** **[PROPOSTA]**: `0` = run completo (inclusive com areas
puladas ou ja configuradas, e inclusive `--dry-run`); `1` = pelo menos
uma area terminou em `failed`; `2` = uso incorreto (flag desconhecida);
`3` = recusa por pre-condicao (fora de raiz de repo git — FR-011; ou TTY
ausente sem `--dry-run`/`--yes` — FR-007).

**Rationale**: alinha com as constantes ja definidas no binario
(`cli/cstk:30-33`: `CSTK_EXIT_OK=0`, `CSTK_EXIT_ERROR=1`,
`CSTK_EXIT_USAGE=2`, `CSTK_EXIT_LOCK=3`) e com o contrato que
`mcp install` (`cli/lib/mcp.sh:949-953`) e `state enable-sqlite`
(`cli/lib/state.sh:26-28`) ja publicam, onde `3` significa
"recusado por pre-condicao". Reusar `3` para as duas recusas do wizard
mantem o vocabulario do binario consistente.

**Alternatives considered**:
- *Sempre exit 0 desde que o summary seja impresso*: rejeitado — tornaria
  `cstk setup` inutil em script de bootstrap/CI, que e exatamente o caso
  de uso da US3.
- *Exit code distinto por area falha*: rejeitado — FR-009 estabelece
  areas independentes; codificar qual falhou no exit multiplicaria o
  contrato sem ganho (o summary de FR-010 ja diz qual).

---

## Decision 10: Estrategia de teste

**Decision**: `tests/cstk/test_setup.sh` novo, seguindo a convencao
verificada: sourceia `tests/lib/harness.sh` e define
`CSTK_LIB="$REPO_ROOT/cli/lib"` (padrao de `tests/cstk/test_hooks.sh:11-14`),
isola `HOME` via `env HOME="$TMPDIR_TEST/home"` (padrao de
`tests/cstk/test_mcp.sh:50,58`), e expoe cenarios como funcoes
`scenario_<nome>()` descobertas por `run_all_scenarios`
(`tests/lib/harness.sh:245-251`).

O mapeamento e obrigatorio, nao opcional: `tests/run.sh:10-13` define
`cli/lib/<n>.sh -> tests/cstk/test_<n>.sh`, e `./tests/run.sh
--check-coverage` falha com exit 1 em script orfao. Hoje **nem
`cli/lib/setup.sh` nem `tests/cstk/test_setup.sh` existem** — verificado.

**Isolamento critico**: a area de state backend escreve na config
**global** `$HOME/.claude/cstk/config` (`state-backend.sh:75-76`). Sem
`HOME` sandboxado, um teste de `enable-sqlite` alteraria a configuracao
real da maquina de quem roda a suite. O `HOME` falso nao e higiene
opcional aqui — e requisito de corretude do teste.

**Rationale**: Constitution Quality Standards exige teste automatizado
para todo script novo, e o `--check-coverage` torna a regra enforced.

**Alternatives considered**:
- *Cobrir `setup` dentro de `tests/cstk/test_cstk-main.sh`*: rejeitado —
  quebraria o mapeamento de `tests/run.sh:10-13` e deixaria
  `cli/lib/setup.sh` orfao no `--check-coverage`.

**Lacuna conhecida (nao bloqueante)**: um teste que force `sqlite3`
ausente esbarra no gotcha ja registrado do projeto — stub de `PATH` nao
esconde binario de `/usr/bin`. Cenarios de "dependencia ausente" devem
ser desenhados desacoplando a deteccao do `PATH` interno, ou aceitos como
nao-cobertos com nota explicita. Decisao adiada para `create-tasks`.

---

## Decision 11: Autenticidade do registro em hooks/MCP (FR-016)

> Adicionada na revisao pos-gate `owasp-security` da fase plan (achado
> HIGH), apos resposta do operador ao bloqueio. Revisa parcialmente as
> Decisions 2 e 3, que definiram a deteccao por presenca.

**Decision**: verificar que a configuracao do projeto **invoca** o script
do catalogo, e nao apenas que **cita** seu nome. Divergencia vira o
status `divergent`, que jamais colapsa para `configured`. Implementado
como extensao aditiva na lib dona de cada area — 5a coluna TSV em
`guard-hooks-status.sh check --verify-registration` e helper read-only
`_mcp_registration_status` em `cli/lib/mcp.sh` — nunca como deteccao
propria de `setup.sh` (preserva a Decision 2).

**Problema observado** (nao hipotetico — verificado no codigo):

1. `_gh_registered` (`guard-hooks-status.sh:119-127`) e
   `grep -Fq -- "$2" "$_gh_settings"`: presenca do **basename**. O
   comentario do proprio script assume ser "condicao necessaria e
   suficiente na pratica". E necessaria, nao suficiente.
2. A deteccao de MCP desenhada na Decision 2 era a presenca da chave
   `cstk-state` no `.mcp.json`.
3. Os dois comandos de aplicacao fazem merge com **o target vencendo**:
   `jq -s '.[0] * .[1]'`, "Source primeiro, target segundo => target
   vence em conflitos" (`cli/lib/hooks.sh`); "entrada ja presente e
   equivalente => idempotente, exit 0" (`cli/lib/mcp.sh:800-802`).

Combinados: uma entrada preexistente que cite o nome e execute outro
programa sobrevive a instalacao **e** era reportada como
`already configured`. O hook em questao, `pretooluse-bash-guard.sh`, e o
bloqueio fail-closed de comandos durante execucao 00c — a falsa garantia
recairia sobre um controle de seguranca, no cenario que a feature mira
(repo recem-clonado, onde a configuracao veio junto).

**Rationale**: um wizard de onboarding cuja mensagem central e "esta area
ja esta configurada" so agrega valor se essa afirmacao for verificavel. A
alternativa de apenas reduzir o escopo da garantia no texto transfere ao
usuario um julgamento que ele nao tem como fazer — ele nao vai auditar o
`settings.json` que o wizard acabou de declarar em ordem.

**Alternatives considered**:

- *Reduzir o escopo da garantia (opcao (b) do bloqueio)*: rejeitado pelo
  operador. Manteria a superficie e trocaria a falsa garantia por um
  aviso que o usuario tende a nao ler.
- *Aceitar o risco (opcao (c))*: rejeitado pelo operador.
- *Sobrescrever a entrada divergente automaticamente*: rejeitado — o
  wizard passaria a destruir configuracao que nao entende, e o caso
  legitimo (usuario com wrapper proprio deliberado) e indistinguivel do
  hostil sem intervencao humana. Detectar e instruir preserva as duas
  situacoes.
- *Fazer da verificacao o comportamento default de
  `guard-hooks-status.sh check`*: adiado. Mudaria formato de saida e exit
  de um contrato publicado (README.md:279, prosa dos orquestradores) —
  BREAKING, exigindo bump MAJOR por Constitution I. Registrado como
  candidato para a proxima major.
- *Parsear o JSON com `jq` em vez de `grep -F` por linha*: rejeitado —
  `jq` e justamente a dependencia que costuma faltar no projeto mal
  provisionado sob diagnostico (Decision 2; comentario em
  `guard-hooks-status.sh:119-125`). O custo e a limitacao textual
  documentada (JSON minificado → `indeterminate`), aceitavel porque
  falha fechada.

**Consequencia na remediacao publicada**: como re-rodar `install` nao
substitui a entrada divergente (item 3 acima), a remediacao exibida e de
**duas etapas** — remover a entrada, depois reinstalar. Publicar apenas
"re-rode `cstk hooks install`" seria uma instrucao comprovadamente
inefetiva (Constitution VI).
