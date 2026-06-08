# Quickstart: cstk-plugins

Cenarios de teste end-to-end. O alvo e CLI POSIX sh (single-layer) — NAO ha
borda backend↔frontend, entao o cenario "Roundtrip End-to-End" do template
e **N/A** (vide nota ao final). O equivalente para esta feature e o cenario
de integridade (Scenario 2), que exercita o gate de checksum com bytes reais.

## Scenario 1: Happy path — install, ativar, listar (US1 + US2 + US3)

1. `CSTK_PLUGIN_REGISTRY=file:///path/to/local/mirror cstk plugin-add codex`
   (ou com rede: `cstk plugin-add codex`).
2. **Expected**: `~/.claude/cstk/plugins/codex/manifest...` existe; checksum
   bate; saida reporta versao instalada; exit 0.
3. `cstk plugin-list`
4. **Expected**: linha `codex  <ver>  llm  ok`; exit 0; <2s (SC-004); nenhuma
   chamada de rede (SC-006 — validavel com `--max-time 0`/sniffer ou rodando
   offline).
5. `cstk 00c <projeto> --llm codex` (ou `/feature-00c ... --llm codex`).
6. **Expected**: para skills que `codex` sobrescreve, a pipeline resolve de
   `~/.claude/cstk/plugins/codex/skills/<skill>/`; para as demais, do core
   `~/.claude/skills/`. `state.json` tem `execution.llm_plugin == "codex"`.

## Scenario 2: Checksum mismatch aborta install (US1-AS2, SC-002)

1. Preparar um bundle cujo conteudo NAO casa o `sha256` declarado no manifest
   (ex: editar 1 byte de um arquivo do bundle apos o manifest ser gerado).
2. `cstk plugin-add codex`
3. **Expected**: erro `checksum mismatch — esperado <a>, obtido <b>`; exit 1;
   `~/.claude/cstk/plugins/codex/` NAO existe (nada escrito, FR-004/FR-008);
   `registry.json` inalterado. Deteccao 100% (SC-002 — verify roda sempre
   antes de qualquer escrita).

## Scenario 3: Nome com path traversal rejeitado (Edge Case, FR-002)

1. `cstk plugin-add ../evil`
2. **Expected**: erro `nome invalido '../evil'`; exit 2; ZERO operacao de
   filesystem ou rede (rejeicao antes de tudo).

## Scenario 3b: Tar-slip rejeitado na extracao (A05/A08, plan §Security)

1. Preparar um tarball cujo manifest e valido MAS que contem uma entrada
   maliciosa (ex: `../../.claude/skills/specify/SKILL.md` ou
   `/etc/cron.d/evil`).
2. `cstk plugin-add evilbundle`
3. **Expected**: erro `tar-slip: entrada fora do staging rejeitada`; exit 1;
   NENHUM arquivo escrito fora de `mktemp -d`; store e `~/.claude/skills/`
   intactos. O guard roda ANTES da extracao real e ANTES do checksum.

## Scenario 4: `--llm` de plugin nao instalado (US2-AS3, FR-015)

1. Garantir que `ghost` NAO esta instalado (`cstk plugin-remove ghost` se
   preciso).
2. `cstk 00c <projeto> --llm ghost`
3. **Expected**: exit 1 ANTES de criar qualquer state; mensagem `Plugin
   'ghost' nao instalado — rode 'cstk plugin-add ghost' primeiro.`;
   `<projeto>/.claude/.../state.json` NAO criado.

## Scenario 5: Default `claude` = zero regressao (US2-AS2, SC-003)

1. `cstk 00c <projeto>` (sem `--llm`).
2. **Expected**: comportamento identico ao atual; `execution.llm_plugin ==
   "claude"`; todas as skills resolvidas do core; nenhum acesso ao plugin
   store.

## Scenario 6: Tampering detectado em list e na ativacao (US3-AS2, FR-005)

1. Instalar `codex` (Scenario 1).
2. Editar 1 byte de um arquivo em `~/.claude/cstk/plugins/codex/skills/...`.
3. `cstk plugin-list --verify`
4. **Expected**: linha `codex ... tampered`.
5. `cstk 00c <projeto> --llm codex`
6. **Expected**: ativacao recusada com integrity error (US2-AS4); exit 1.

## Scenario 7: list/remove offline (FR-018, SC-006)

1. Desconectar rede (ou bloquear `curl`).
2. `cstk plugin-list` e `cstk plugin-remove codex`
3. **Expected**: ambos funcionam normalmente; nenhuma chamada de rede; exit 0.

## Scenario 8: Degradacao sem `sha256sum`/`shasum` (FR-017, carve-out 1.1.0)

1. Rodar `plugin-add`/`plugin-list --verify` num PATH sem `sha256sum` nem
   `shasum`.
2. **Expected**: mensagem clara de degradacao (de `compat.sh`: "nem sha256sum
   nem shasum encontrados"); o caminho de integridade falha de forma graceful
   e documentada — NAO instala silenciosamente sem verificar. (Coberto por
   teste automatizado, condicao (a) do carve-out.)

---

> **Nota — Scenario "Roundtrip End-to-End" do template e N/A**: esta feature
> e single-layer (CLI POSIX sh + artefatos de filesystem). Nao ha payload de
> API atravessando borda backend↔frontend, logo nao ha case style snake_case
> vs camelCase a divergir. O analogo de "validacao com bytes reais" e o
> Scenario 2 (checksum com bundle real, nao mock) + Scenario 6 (tampering
> real no disco). A suite de testes POSIX (`tests/test_plugin-*.sh`) usa
> bundles fixture reais, nunca stubs de hash.
