# Quickstart: cstk-setup

Cenarios que validam a implementacao end-to-end. Todos rodam com `HOME`
sandboxado (`env HOME="$TMPDIR_TEST/home"`, padrao de
`tests/cstk/test_mcp.sh:50,58`) — obrigatorio, nao higiene opcional: a
area de state backend escreve na config **global**
`$HOME/.claude/cstk/config` (`state-backend.sh:75-76`), e sem sandbox um
teste alteraria a configuracao real da maquina.

`CSTK_LIB="$REPO_ROOT/cli/lib"` conforme `tests/cstk/test_hooks.sh:13-14`.
Prompts interativos usam o bypass `CSTK_FORCE_INTERACTIVE=1`
(`cli/lib/ui.sh:43`) para serem exercitaveis sem TTY real.

---

## Scenario 1: Happy path — projeto sem nada configurado, interativo (US1)

1. Criar diretorio temporario e `git init` (satisfaz FR-011 — `.git`
   presente).
2. `HOME` sandboxado, sem `~/.claude/cstk/config`, sem
   `.claude/settings.json`, sem `.mcp.json` no projeto.
3. Rodar `cstk setup --project-path "$PROJ"` com `CSTK_FORCE_INTERACTIVE=1`,
   alimentando stdin com respostas afirmativas para hooks e negativa para
   loose usage.
4. **Expected**:
   - As **quatro** areas sao apresentadas na ordem fixa de FR-001:
     `hooks`, `state-backend`, `mcp`, `telemetry`.
   - Cada area exibe o status atual **antes** de oferecer a acao (FR-002).
   - Apos aceitar hooks: `guard-hooks-status.sh check --projeto-alvo-path
     "$PROJ" --quiet` passa a sair **0** (antes saia 1).
   - Summary final lista as 4 areas com outcome cada (FR-010).
   - Exit `0`.

---

## Scenario 2: Idempotencia — segundo run nao muda nada (US2, SC-002)

1. Partir do estado final do Scenario 1.
2. Capturar assinatura do estado antes: `.claude/settings.json`,
   `.mcp.json`, `$HOME/.claude/cstk/config` e `.claude/hooks/` (ex.
   `find ... | sort` + hash de conteudo).
3. Rodar `cstk setup --project-path "$PROJ" --yes` de novo.
4. Comparar a assinatura depois.
5. **Expected**:
   - Assinatura **identica** — zero alteracao (FR-003, SC-002).
   - Areas ja configuradas reportadas como `already-configured`, sem
     nenhuma chamada de aplicacao.
   - Exit `0`.

> **Por que comparar conteudo e nao so mtime**: `mcp install` e idempotente
> por `merge_settings` com target vencendo (`cli/lib/mcp.sh:800-802`) e
> `enable-sqlite` e no-op quando ja sqlite (`state-backend.sh:385-390`) —
> ambos poderiam reescrever o arquivo com o mesmo conteudo sem violar
> FR-003 semanticamente. A garantia forte que queremos e que o wizard
> **nem chame** essas funcoes quando `status=configured` (invariante I1 do
> data-model). O teste deve assertar tambem a ausencia da chamada, via
> stub/contador.

---

## Scenario 3: Backend deliberadamente diferente nao e migrado a forca (US2 AC3)

1. Projeto configurado, mas com `state_backend=json` mantido de proposito
   em `$HOME/.claude/cstk/config`.
2. Rodar `cstk setup --project-path "$PROJ" --yes`.
3. **Expected**: NAO ha migracao forcada.

> **Ponto de atencao — divergencia aparente entre FR-003 e o default de
> `--yes`**: `effective_backend=json` mapeia para `not-configured`
> (data-model, secao ConfigurationArea), e o default recomendado de
> `--yes` para essa area e *aplicar* (research.md Decision 5). Isso
> aplicaria `enable-sqlite` sobre uma escolha deliberada do usuario,
> contrariando US2 AC3 (spec linhas 82-86).
>
> **Nao ha, no repo, forma de distinguir "json por escolha deliberada" de
> "json por nunca-configurado"** alem do campo `reason=` que
> `state-backend.sh resolve` emite (`state-backend.sh:234-269`; o valor
> `nunca-configurado` aparece citado em CLAUDE.md §"Backend de estado
> global"). Afirmar aqui qual conjunto exato de valores de `reason=`
> existe seria fabricacao.
>
> **Acao requerida na implementacao**: enumerar empiricamente os valores
> de `reason=` produzidos por `_sb_cmd_resolve` e definir a regra —
> proposta: so aplicar em `--yes` quando `reason` indicar ausencia de
> configuracao; qualquer `reason` que indique escolha explicita →
> `already-configured` (respeitando US2 AC3). Registrar como task de
> investigacao em `create-tasks`, nao adivinhar aqui.

---

## Scenario 4: Preview nao escreve nada (US3, FR-004, SC-003)

1. Projeto limpo (`git init`, nada configurado), `HOME` sandboxado.
2. Capturar assinatura completa do projeto **e** do `HOME` sandboxado.
3. Rodar `cstk setup --project-path "$PROJ" --dry-run`.
4. Comparar assinaturas.
5. **Expected**:
   - Zero diferenca em ambos (projeto e `HOME`) — nenhuma escrita.
   - Saida exibe, para as 4 areas, o que seria aplicado.
   - Todos os outcomes = `skipped` com motivo de preview.
   - Exit `0`.

---

## Scenario 5: Preview vence nao-interativo (FR-006)

1. Projeto limpo, assinatura capturada.
2. Rodar `cstk setup --project-path "$PROJ" --dry-run --yes` (ambas as
   flags).
3. **Expected**: comportamento identico ao Scenario 4 — `mode=preview`,
   zero escrita, exit `0`. Nenhuma area em `applied`.

---

## Scenario 6: Terminal nao-interativo sem flag falha rapido (FR-007)

1. Projeto valido (`git init`), **sem** `CSTK_FORCE_INTERACTIVE`.
2. Rodar `cstk setup --project-path "$PROJ"` com stdin redirecionado de
   `/dev/null` (sem TTY) e sem `--dry-run` nem `--yes`.
3. **Expected**:
   - Falha **imediata**, sem bloquear aguardando input.
   - Mensagem em stderr apontando explicitamente `--dry-run` ou `--yes`.
   - Exit `3` (recusa por pre-condicao).
   - Zero escrita.

---

## Scenario 7: Falha isolada de uma area nao interrompe as demais (FR-009)

1. Projeto valido, `HOME` sandboxado.
2. Induzir falha **apenas** na area de state backend — ex. tornar
   `state-backend.sh` irresolvivel para `_config_state_backend_script_path`
   (`cli/lib/config.sh:52`), ou forcar a condicao de recusa por
   `sqlite3` ausente/abaixo de `3.45.1` (`state-backend.sh:358-370`,
   exit 3).
3. Rodar `cstk setup --project-path "$PROJ" --yes`.
4. **Expected**:
   - A area `state-backend` reporta `failed` com motivo legivel citando o
     exit da fonte.
   - As areas `mcp` e `telemetry` (posteriores na ordem fixa) **ainda sao
     percorridas** e reportam seus proprios outcomes.
   - Summary lista as 4 areas (SC-005).
   - Exit `1` (houve `failed`).

> **Sub-caso obrigatorio — `jq` ausente**: `hooks install` retorna
> **exit 0** mesmo em `paste-instructed` (`cli/lib/hooks.sh:631-643`), e
> `mcp install` tambem retorna 0 caindo em `print_paste_block`
> (`cli/lib/mcp.sh:866-871`). Assertar que o wizard **nao** reporta
> `applied` silencioso nesses casos: o aviso de acao manual pendente
> deve chegar ao summary. Este e o caminho mais provavel de falso
> "tudo certo" em producao.

---

## Scenario 8: Gate de diretorio (FR-011)

1. Criar diretorio temporario **sem** `git init` (sem `.git`).
2. Rodar `cstk setup --project-path "$DIR" --yes`.
3. **Expected**:
   - Recusa com diagnostico claro.
   - Exit `3`.
   - Diretorio permanece **inalterado** — nenhum `.claude/`, nenhum
     `.mcp.json`, nenhuma config parcial (spec linhas 159-162).
4. Repetir com um **git worktree** (onde `.git` e arquivo-ponteiro, nao
   diretorio).
5. **Expected**: worktree e **aceito** (FR-011: "worktrees contam") —
   confirma que o teste e `[ -e ]` e nao `[ -d ]`.

---

## Scenario 9: Loose usage e escolha distinta (US4, FR-008)

1. Projeto limpo, modo interativo com `CSTK_FORCE_INTERACTIVE=1`.
2. Alimentar stdin: **sim** para hooks obrigatorios, **nao** para loose
   usage.
3. **Expected**:
   - Duas perguntas distintas, com explicacao propria do que a captura
     avulsa registra.
   - Os 3 hooks obrigatorios ficam instalados
     (`guard-hooks-status.sh check` → exit 0).
   - `posttooluse-loose-usage.sh` **nao** e provisionado nem registrado.
4. Rodar `cstk setup --project-path "$PROJ" --yes` num projeto limpo.
5. **Expected**: hooks obrigatorios aplicados, loose usage **nao**
   aplicado — o default de `--yes` para essa sub-area e `skip`
   (`--with-loose-usage` e opt-in default off,
   `cli/lib/hooks.sh:513,543`; CLAUDE.md: "NUNCA bundlado silenciosamente
   ... sem a flag").

---

## Scenario 10: Runtime instalado antigo — flag de deteccao desconhecida

1. Apontar `CSTK_HOOKS_CATALOG_DIR` / o `guard-hooks-status.sh` resolvido
   para uma copia **anterior** a esta feature (sem
   `--include-loose-usage`).
2. Rodar `cstk setup --project-path "$PROJ" --yes`.
3. **Expected**:
   - A chamada de deteccao do loose usage retorna exit `2`
     (`_gh_die_usage`, `guard-hooks-status.sh:205`).
   - O wizard reporta `loose_usage_status=indeterminate` com motivo, e
     **nao** trata isso como falha da area de hooks (FR-009).
   - Os hooks obrigatorios seguem detectados e aplicados normalmente.
   - Exit `0`.

---

## Scenario 11: Sincronizacao das duas metades (GOTCHA de release)

Nao e teste automatizado — e verificacao manual obrigatoria antes de
fechar a feature.

1. Editar `cli/lib/setup.sh` + `cli/cstk` (**runtime do binario**) e
   `global/skills/agente-00c-runtime/scripts/guard-hooks-status.sh`
   (**catalogo**).
2. Buildar: `./scripts/build-release.sh X.Y.Z-dev`.
3. Rodar **ambos**:
   - `cstk self-update --from "file://$PWD/dist/cstk-X.Y.Z-dev.tar.gz"`
     (binario + `cli/lib` em `~/.local`)
   - `cstk install --from "file://$PWD/dist/cstk-X.Y.Z-dev.tar.gz"`
     (catalogo em `~/.claude`)
4. `cstk doctor`
5. **Expected**: drift zero. Rodar apenas um dos dois reproduz o sintoma
   documentado em CLAUDE.md §"Installed vs Source Drift": "fix funciona no
   repo mas nao na sessao" — aqui, `cstk setup` novo chamando um
   `guard-hooks-status.sh` velho que rejeita `--include-loose-usage`.

---

## Scenario 12: Cobertura de teste registrada

1. `./tests/run.sh --check-coverage`
2. **Expected**: exit `0` — `cli/lib/setup.sh` tem
   `tests/cstk/test_setup.sh` correspondente, conforme o mapeamento de
   `tests/run.sh:10-13`. Sem o arquivo de teste, o check falha com exit 1
   (script orfao).
3. `./tests/run.sh test_setup` → todos os cenarios verdes.

---

> **Sobre o "Roundtrip End-to-End" do template**: N/A. A feature e
> single-layer (CLI POSIX sh, sem borda backend↔frontend, sem payload
> serializado entre camadas). O equivalente funcional de roundtrip aqui e
> o Scenario 2 (estado real re-lido apos escrita real, sem mock) somado ao
> Scenario 11 (a copia instalada, nao a do repo, e quem roda de fato).
