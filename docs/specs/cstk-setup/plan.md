# Implementation Plan: Guided Project Setup Wizard

**Feature**: `cstk-setup` | **Date**: 2026-08-07 | **Spec**: [spec.md](./spec.md)

## Summary

Adicionar `cstk setup`: um subcomando novo do binario CLI que percorre,
numa ordem fixa, as quatro areas de configuracao recomendadas de um
projeto — hooks obrigatorios (com o hook opt-in de captura avulsa como
escolha aninhada), backend de estado global, registro do servidor MCP de
estado, e telemetria — mostrando o status atual de cada uma antes de
oferecer aplica-la, e terminando com um sumario por area.

**Abordagem tecnica**: `cli/lib/setup.sh` e uma camada de **orquestracao
pura**. Nao implementa nenhuma deteccao nem nenhuma escrita propria: cada
area delega deteccao a uma fonte read-only existente e aplicacao ao
comando dedicado existente (research.md Decisions 2 e 4). Essa e a unica
forma de satisfazer FR-002 ("usando a mesma logica de deteccao do comando
dedicado") sem criar uma segunda implementacao que derive com o tempo.
Idempotencia (FR-003/FR-013) cai fora de graca: o status e re-apurado
vivo a cada invocacao e area ja configurada nao recebe chamada alguma.

Tres extensoes de contrato sao necessarias, todas **aditivas** e todas
alojadas na lib que ja e dona da area — nunca em `setup.sh`, para nao
criar a segunda implementacao que a abordagem existe para evitar:

1. `guard-hooks-status.sh check --include-loose-usage` — o hook opt-in
   `posttooluse-loose-usage.sh` nao tem hoje nenhuma fonte de deteccao
   read-only, embora FR-002 + FR-008 exijam mostrar seu status antes de
   perguntar. Ver research.md Decision 3.
2. `guard-hooks-status.sh check --verify-registration` — 5a coluna TSV
   que verifica se o comando de fato registrado no `settings.json` e o
   canonico do catalogo (FR-016).
3. `_mcp_registration_status` em `cli/lib/mcp.sh` — deteccao read-only
   equivalente para a chave `mcpServers.cstk-state` (FR-016).

> **Invocacao das extensoes (1) e (2) e sempre SEPARADA da baseline
> (achado SEC-03)**: `setup.sh` MUST chamar
> `guard-hooks-status.sh check --projeto-alvo-path PATH --quiet` (sem
> flags) como fonte do veredito dos 3 hooks obrigatorios, e (1)/(2) como
> chamadas adicionais **isoladas** cuja falha (runtime antigo, exit 2)
> degrada apenas a propria dimensao — `loose_usage_status` para (1),
> `mandatory_status`/`status` (via I5, para `unavailable`) para (2).
> Combinar as tres flags numa unica chamada faria um runtime antigo sem
> suporte a alguma delas perder tambem o veredito basico que ele sabe
> responder. Ver data-model.md §Fonte de `status` por area.

### Nota de seguranca: por que (2) e (3) existem

Ambas nasceram de um gate `owasp-security` na fase plan, respondido pelo
operador (spec.md §Clarifications, sessao de gate). O desenho original
apurava as duas areas por **presenca de nome**: basename do hook no
`settings.json` (`_gh_registered`, `guard-hooks-status.sh:119-127`) e
chave `cstk-state` no `.mcp.json`. Presenca de nome nao distingue um
registro legitimo de um que cita o nome e executa outro programa — e o
hook em questao, `pretooluse-bash-guard.sh`, e um controle de seguranca
(bloqueio fail-closed de comandos durante execucao 00c).

O agravante e a semantica de merge: `merge_settings` roda
`jq -s '.[0] * .[1]'` com "Source primeiro, target segundo => target
vence em conflitos" (`cli/lib/hooks.sh`), e `cstk mcp install` declara
"entrada ja presente e equivalente => idempotente, exit 0"
(`cli/lib/mcp.sh:800-802`). Uma entrada preexistente **sobrevive** a
instalacao. Sem (2) e (3), o wizard reportaria `already configured`
sobre um controle redirecionado — falsa garantia no cenario exato que a
feature mira, o repo recem-clonado.

A resposta e **deteccao**, nao sobrescrita: o wizard classifica como
`divergent`, imprime a remediacao de duas etapas (remover a entrada,
depois reinstalar — porque so reinstalar comprovadamente nao substitui) e
falha a area. Ele nunca apaga configuracao que nao reconhece.
Fail-closed: toda ambiguidade de apuracao vira `divergent`, jamais
`configured` (data-model, invariantes I5/I6).

## Technical Context

**Language/Version**: POSIX sh (`#!/bin/sh`, `set -eu`) — Constitution II
**Primary Dependencies**: nenhuma nova. `setup.sh` sourceia libs irmas pelo
padrao ja estabelecido `. "${CSTK_LIB:?CSTK_LIB must be set}/<lib>.sh"`
(`cli/lib/hooks.sh:60`, `cli/lib/doctor.sh:51-59`, `cli/lib/list.sh:31-41`)
e invoca scripts do catalogo como processo. **Nao** chama `sqlite3`
(confinado a `cli/lib/recall.sh`), **nao** chama `docker` funcionalmente
(confinado a `cli/lib/mcp-docker.sh`), **nao** exige `jq`
**Storage**: N/A — feature sem persistencia propria (FR-013 proibe flag
persistido de "setup ja rodou"). Escritas ocorrem apenas dentro dos
comandos delegados
**Testing**: harness POSIX do repo — `tests/cstk/test_setup.sh` (novo),
cenarios `scenario_<nome>()` descobertos por `run_all_scenarios`
(`tests/lib/harness.sh:245-251`); mapeamento obrigatorio de
`tests/run.sh:10-13`, enforced por `./tests/run.sh --check-coverage`
**Target Platform**: macOS/Linux, shell POSIX. Sem GNU-only (CLAUDE.md)
**Project Type**: CLI (subcomando de binario existente)
**Performance Goals**: SC-001 — decidir as 4 areas em menos de 2 min de
tempo interativo. Nao ha meta de latencia de maquina; o custo dominante e
leitura humana
**Constraints**: FR-011 (so roda em raiz de repo git); FR-012 (area de
telemetria nao escreve fora do projeto); FR-007 (falha rapida sem TTY);
Constitution II (POSIX puro, sem bashismos)
**Scale/Scope**: 1 lib nova + 1 arquivo de teste novo + edicoes pontuais
em `cli/cstk` (4 listas) + 2 extensoes aditivas de flag em
`guard-hooks-status.sh` + 1 helper read-only aditivo em `cli/lib/mcp.sh`

Zero `NEEDS CLARIFICATION` remanescentes. As tres ambiguidades originais
foram fechadas no clarify (spec.md linhas 11-13); as decisoes tecnicas
restantes estao resolvidas em research.md.

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checado apos Phase 1 — ver
§Re-check.*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (NON-NEGOTIABLE) | PASS | Feature nao-trivial entrou pela pipeline completa: `spec.md` + `clarify` (3 Q&A registradas) + este `plan.md`; `tasks.md` vem a seguir. Nao ha alteracao de contrato de skill existente, logo sem BREAKING |
| II. POSIX sh puro (NON-NEGOTIABLE) | PASS | `cli/lib/setup.sh` e `#!/bin/sh` + `set -eu`, sem arrays, `[[ ]]`, `local`, `<<<` ou `function`. **Nenhuma dep nova**: nao invoca `jq`, `sqlite3`, `docker`, `git`. A deteccao de MCP e leitura textual (`grep -F`), mesma escolha que `_gh_registered` (`guard-hooks-status.sh:119`) ja faz explicitamente para nao depender de `jq`. Ver §Registro de dependencias |
| III. Formato canonico de skill | N/A | Nao e skill — FR-014 fixa subcomando de CLI. Nao ha `SKILL.md` envolvido |
| IV. Zero coleta remota (NON-NEGOTIABLE) | PASS | Ver §Analise dedicada abaixo — as duas superficies suspeitas (area de telemetria, hook de captura avulsa) sao 100% locais |
| V. Profundidade sobre adocao | PASS | A feature reduz retrabalho real (substitui conhecimento tribal de 4 comandos por um ponto de entrada), nao gera visibilidade. Nenhuma superficie nova de configuracao foi inventada — so orquestracao do que existe |
| VI. Veracidade de dados (NON-NEGOTIABLE) | PASS | Todo comportamento existente afirmado nos artefatos cita `arquivo:linha` verificado. Interfaces novas estao marcadas **[PROPOSTA]** em `contracts/cli-setup.md`, distintas de **[EXISTENTE]**. Onde faltou fonte (Scenario 3 do quickstart: valores de `reason=` do `state-backend.sh resolve`), a lacuna foi **registrada como investigacao**, nao preenchida por suposicao |

### Analise dedicada — Principio IV (zero coleta remota)

A feature toca duas superficies que, pelo nome, parecem colidir com
"nenhuma skill faz requisicao de rede para endpoint de telemetria":

1. **Area de telemetria (OTel)**. O que existe no repo e um exporter
   **Prometheus local** em `127.0.0.1:9464` (README.md:315), consumido
   por `otel-usage.sh` na propria maquina. Nao ha endpoint do autor, nao
   ha upload. Alem disso o wizard **nao ativa nada** — FR-012 restringe a
   area a diagnosticar (`otel-usage.sh preflight`, `otel-usage.sh:469`) e
   exibir instrucoes. A decisao de ativar continua inteiramente do
   usuario, no shell dele.
2. **Hook opt-in de captura avulsa**. Grava em sidecar local
   (`~/.claude/cstk/loose-usage/`) e no `knowledge.db` local. E opt-in
   explicito (`--with-loose-usage` default off, `cli/lib/hooks.sh:513,543`),
   e o wizard **preserva** esse opt-in: FR-008 exige pergunta separada, e
   o default em `--yes` e **nao aplicar** (research.md Decision 5) —
   unica area cujo default recomendado e "nao". Logs e artefatos
   permanecem no filesystem local, como o Principio IV exige.

**Veredito**: PASS. O wizard nao introduz nenhuma requisicao de rede; ao
contrario, torna explicita ao usuario uma escolha que hoje esta enterrada
em documentacao.

### Registro de dependencias (Principio II, carve-outs 1.1.0 e 1.3.0)

`cli/lib/setup.sh` **nao aciona nenhum carve-out**: nao introduz
dependencia opcional nem obrigatoria. As deps que aparecem
transitivamente ja estao cobertas por carve-outs anteriores e
permanecem confinadas onde ja estavam:

| Dep | Onde e usada | Cobertura |
|-----|--------------|-----------|
| `jq` | dentro de `hooks install` / `mcp install`, com fallback `print_paste_block` que retorna 0 (`cli/lib/hooks.sh:631-643`, `cli/lib/mcp.sh:866-871`) | carve-out 1.1.0 (opcional com fallback), preexistente |
| `sqlite3` | dentro de `enable-sqlite` (`state-backend.sh`), com recusa limpa exit 3 quando ausente (linhas 358-370) | carve-out 1.3.0 (camada de estado transacional), preexistente |
| `docker` | dentro de `cli/lib/mcp-docker.sh` (unico ponto funcional, cabecalho linhas 1-11) | preexistente; `setup.sh` no maximo usa `command -v docker` para texto de aviso, mesmo padrao de `cli/lib/mcp.sh:475-479` |

## Project Structure

### Documentation (this feature)

```
docs/specs/cstk-setup/
├── spec.md
├── plan.md                  # This file
├── research.md              # Phase 0 output — 10 decisions
├── data-model.md            # Phase 1 output — estruturas em memoria
├── quickstart.md            # Phase 1 output — 12 cenarios
└── contracts/
    └── cli-setup.md         # Phase 1 output — contrato CLI + 4 fronteiras
```

### Source Code (repository root)

Paths verificados no repo em 2026-08-07. `[NOVO]` = arquivo a criar;
`[EDIT]` = arquivo existente a alterar; demais sao consumidos sem
alteracao.

```
cli/
├── cstk                                    [EDIT] 4 pontos — ver tabela
└── lib/
    ├── setup.sh                            [NOVO] setup_main + orquestracao
    ├── common.sh                           log_info/log_warn/log_error (19/23/27), is_tty (31)
    ├── ui.sh                               require_tty (42-50)
    ├── config.sh                           config_state_backend_{capability,resolve,enable_sqlite} (90/94/98)
    ├── hooks.sh                            hooks_main (557), apply_guard_hooks (318)
    ├── mcp.sh                              [EDIT] + _mcp_registration_status (FR-016); _mcp_cmd_install (806-877), _mcp_cmd_status (371), _mcp_runtime_script_path (127-146)
    ├── mcp-docker.sh                       _mcp_docker_preflight — nao invocado por setup.sh
    ├── doctor.sh                           _doctor_deps_run (408-474)
    └── state.sh                            state_main (103-149) — referencia de contrato
global/skills/agente-00c-runtime/
├── scripts/
│   ├── guard-hooks-status.sh               [EDIT] flags --include-loose-usage e --verify-registration (ambas aditivas)
│   ├── state-backend.sh                    resolve (234-269), enable-sqlite (358-397)
│   └── otel-usage.sh                       preflight (469)
└── hooks/
    ├── posttooluse-loose-usage.sh          alvo da nova deteccao
    └── settings.loose-usage.snippet.json   snippet separado (opt-in)
tests/
├── run.sh                                  mapeamento (10-13) + --check-coverage
├── lib/harness.sh                          run_all_scenarios (245-251)
└── cstk/
    └── test_setup.sh                       [NOVO] cenarios do quickstart.md
```

**Pontos de edicao em `cli/cstk`** (todos os quatro sao obrigatorios —
esquecer um produz UX inconsistente, ver research.md Decision 1):

| Local | Mudanca |
|-------|---------|
| `cli/cstk:250` | adicionar `setup` ao `case` do ramo generico de dispatch |
| `cli/cstk:136-152` | adicionar `setup` a lista de comandos do help geral |
| `cli/cstk:169-211` | adicionar ramo `setup)` ao `case` de help por subcomando |
| `cli/cstk:217` e `cli/cstk:299` | incluir `setup` nas listas de comandos validos das mensagens de erro |

**Structure Decision**: `setup` entra pelo ramo **generico** do
dispatcher, sem ramo dedicado. O ramo generico ja resolve
`$CSTK_LIB/setup.sh` (`cli/cstk:257`), sourceia (linha 265) e deriva
`setup_main` pela convencao `sed 's/-/_/g'` + `_main` (linha 267). O
special-casing de `00c` (linhas 274-291) existe apenas porque nome de
funcao nao pode comecar com digito — nao se aplica. Um ramo dedicado
seria codigo morto.

## Convencoes de Borda

**N/A — single-layer.** A feature e um subcomando CLI em POSIX sh puro:
nao ha borda backend↔frontend, nao ha DB, nao ha broker, nao ha payload
serializado atravessando camadas. Nenhum mapper, nenhum schema
compartilhado, nenhuma validacao de case style aplicavel.

A unica fronteira real e **processo ↔ processo** (`setup.sh` consumindo
stdout/exit de scripts do catalogo), e ela ja e governada por contratos
textuais explicitos, documentados em `contracts/cli-setup.md`:

| Fronteira | Formato | Fonte da verdade |
|-----------|---------|------------------|
| `setup.sh` ↔ `guard-hooks-status.sh` | TSV, 4 campos por linha | cabecalho de `guard-hooks-status.sh:49-60` |
| `setup.sh` ↔ `state-backend.sh` (via `config.sh`) | `chave=valor` (`effective_backend=`, `reason=`) | `_sb_cmd_resolve`, `state-backend.sh:234-269` |
| `setup.sh` ↔ `hooks.sh` / `mcp.sh` | funcao sourceada + exit code | contratos em `cli/lib/hooks.sh:526-535`, `cli/lib/mcp.sh:949-953` |
| `setup.sh` ↔ `otel-usage.sh` | texto de diagnostico + exit | `_ou_cmd_preflight`, `otel-usage.sh:469-561` |
| `setup.sh` ↔ `mcp.sh` (registro) | palavra unica em stdout (`configured`/`divergent`/`not-configured`) | `_mcp_registration_status` [PROPOSTA], `contracts/cli-setup.md` §4.1 |

**Disciplina equivalente ao "case style"** para esta feature: o
vocabulario de status (`configured` / `not-configured` / `divergent` /
`unavailable`) e de outcome (`applied` / `already-configured` /
`skipped` / `failed`) e **fechado e declarado uma unica vez** em
`data-model.md`, e vem literalmente de FR-002, FR-016 e FR-010. Nenhuma
area pode inventar um valor fora desse conjunto — e a mesma classe de bug que o template alerta (dois lados
falando dialetos diferentes do mesmo dado), transposta para CLI.

## Re-check de Constitution (pos-Phase 1)

Revalidacao apos o design estar completo:

- **Complexidade introduzida**: uma lib nova de orquestracao e uma flag
  aditiva. Nenhuma camada, nenhum servico, nenhum formato de dado novo.
  O design REDUZ superficie conceitual (4 comandos → 1 ponto de entrada)
  em vez de aumenta-la.
- **Principio II segue integro**: o design explicitamente rejeitou
  `git rev-parse` (research.md Decision 7), reescrita direta de
  `settings.json`/`.mcp.json` (Decision 4) e parse com `jq` (Decision 2) —
  em todos os casos escolhendo a alternativa POSIX ou a delegacao.
- **Principio VI segue integro apos o design**: o Phase 1 *encontrou* uma
  lacuna factual (valores de `reason=` do `resolve`) e a registrou como
  investigacao no quickstart Scenario 3, em vez de inventar o conjunto de
  valores. Esse e o comportamento que o principio exige.
- **Risco novo identificado, mitigado por processo**: a feature toca as
  duas metades da instalacao (runtime do binario **e** catalogo),
  exigindo `cstk self-update` **e** `cstk install`. Mitigado pelo
  quickstart Scenario 11 como verificacao manual obrigatoria.
- **Revisao de seguranca aplicada (gate `owasp-security`, achado HIGH)**:
  o design pos-gate incorpora FR-016 (autenticidade do registro,
  fail-closed), FR-017 (rotulo de escrita global) e FR-018 (nao expor
  override de catalogo). Nenhum dos tres introduz dependencia, camada ou
  formato novo — sao uma coluna TSV aditiva, um helper read-only e uma
  flag deliberadamente ausente. Principio II intacto (a verificacao e
  `grep -F` por linha, sem `jq`); Principio VI intacto (a remediacao
  publicada foi corrigida contra a semantica real do merge em vez de
  repetir a instrucao intuitiva que nao surte efeito).

- **Re-review de seguranca pos-hardening (gate `owasp-security`, sem
  HIGH/CRITICAL, 7 achados MEDIUM/LOW SEC-01..SEC-07)**: os 3 achados que
  alteravam contrato/data-model foram corrigidos nesta mesma revisao,
  ANTES de `create-tasks`, para nao gerar retrabalho de tarefas ja
  quebradas por FASE:
  - **SEC-01** (MEDIUM, linha-isca decorativa satisfazia a regra de linha
    canonica de `--verify-registration`): `contracts/cli-setup.md` §2.3
    agora exige tambem o token `"command"` na mesma linha, e declara
    explicitamente que posicionamento estrutural sob `PreToolUse`/
    `matcher` NAO e verificado (residual aceito, mesma classe do limite
    de JSON minificado).
  - **SEC-02** (MEDIUM, mapeamento de `indeterminate` sem destino no enum
    fechado gerava fail-open para `configured`): `data-model.md`
    invariante I5 agora enumera `indeterminate` → `unavailable`
    explicitamente (nunca herda o exit 0/1 da chamada baseline), mesmo
    caminho ja descrito para o exit 2 do quickstart Scenario 15 variante
    4.
  - **SEC-03** (MEDIUM, combinar `--include-loose-usage` e
    `--verify-registration` na mesma chamada regride runtime antigo):
    `data-model.md` linha `hooks` da tabela de fontes agora exige 3
    chamadas SEPARADAS — baseline sem flags (fonte real de
    `configured`/`not-configured`), `--verify-registration` isolada
    (so escala para `divergent`/`unavailable`) e `--include-loose-usage`
    isolada (so alimenta `loose_usage_status`).
  - **SEC-04..SEC-07** (MEDIUM/LOW restantes, sem impacto em
    contrato/data-model): registrados para virar tarefas explicitas no
    `create-tasks` em vez de fechados aqui — `--yes` nao deve gravar
    config global sem opt-in equivalente ao do loose-usage (SEC-04);
    candidatos de `mcp-launch.sh` em `_mcp_registration_status` devem se
    restringir ao sufixo `/skills/agente-00c-runtime/scripts/
    mcp-launch.sh` **existente em disco** (SEC-05); stdout vazio de
    `_mcp_registration_status` nunca e resposta valida, deve virar
    indeterminado (SEC-06); o summary deve declarar o escopo real da
    verificacao — hooks obrigatorios verificados, demais entradas do
    `settings.json` nao auditadas (SEC-07).

**Veredito**: todos os MUST (I, II, IV, VI) seguem PASS. Nenhum novo
carve-out necessario.

## Complexity Tracking

Nao aplicavel — Constitution Check sem violacoes, nenhuma excecao
solicitada, nenhum carve-out novo acionado.

## Riscos e pontos de atencao para `create-tasks`

Levantados no Phase 1, a converter em tarefas:

1. **`reason=` do `state-backend.sh resolve` nao enumerado** — bloqueia a
   regra de US2 AC3 (nao migrar backend deliberadamente diferente).
   Tarefa de investigacao empirica ANTES de codificar o default de `--yes`
   para a area de state backend. Ver quickstart Scenario 3.
2. **`set -e` e isolamento de falha (FR-009)** — libs sourceadas rodam no
   mesmo shell sob `set -eu`. Toda chamada de aplicacao MUST ser
   neutralizada (`if ! fn; then` ou `fn || rc=$?`). Uma unica chamada
   solta derruba o wizard inteiro e viola FR-009 silenciosamente.
3. **Exit 0 nao significa `applied`** — `hooks install` e `mcp install`
   retornam 0 em `paste-instructed` (jq ausente). Mapear para um outcome
   que carregue o aviso ao summary, senao o usuario le "tudo certo" com
   acao manual pendente. Caminho mais provavel de falso positivo em
   producao.
4. **Sincronizacao das duas metades** — checklist de release deve exigir
   `cstk self-update` **e** `cstk install` + `cstk doctor` drift zero.
5. **Teste de "dependencia ausente"** — esbarra no gotcha conhecido do
   projeto: stub de `PATH` nao esconde binario de `/usr/bin`. Desenhar
   desacoplando a deteccao do `PATH` interno, ou aceitar como
   nao-coberto com nota explicita.
6. **Nome de flag `--yes`** — sem precedente verificado no repo para
   "nao-interativo". Confirmar com o operador antes de congelar o
   contrato publico (research.md Decision 5).
7. **Falso-positivo de `divergent` no MCP (FR-016)** — o `command`
   gravado e o path resolvido no momento da instalacao
   (`cli/lib/mcp.sh:840`), e `_mcp_runtime_script_path` (linhas 127-146)
   tem tres camadas de resolucao. Comparar contra uma so gera
   `divergent` espurio em maquina de dev. A regra e aceitar o **conjunto**
   das tres camadas (contrato §4.1). Testar explicitamente os dois lados:
   entrada escrita a partir do repo e verificada via `~/.claude`
   (**nao** divergente) e entrada apontando para fora do catalogo
   (**divergente**).
8. **`settings.json` minificado** — a verificacao de registro e por
   linha. JSON numa unica linha impede atribuir a mencao ao basename e
   MUST resolver para `indeterminate` → nunca `configured` (I5). Cenario
   de teste obrigatorio: o caso minificado nao pode passar por
   `already-configured`.
9. **Remediacao precisa ser testada, nao so impressa** — o teste de
   `divergent` deve assertar que o wizard **nao chamou** `hooks install`
   / `mcp install` (I6) e que o texto exibido inclui a etapa de remocao.
   Instruir apenas "re-rode o install" seria instrucao comprovadamente
   inefetiva (merge com target vencendo).
10. **5a coluna e o exit sob `--verify-registration`** — a extensao muda
    o exit para `1` em divergencia **apenas** quando a flag e passada.
    Teste de retro-compatibilidade obrigatorio: sem a flag, saida
    byte-a-byte e exit identicos aos atuais, para nao quebrar
    `tests/test_guard-hooks-status.sh` nem os consumidores existentes.
