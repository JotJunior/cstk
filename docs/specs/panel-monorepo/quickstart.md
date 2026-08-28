# Quickstart / Cenarios de Teste: panel-monorepo

**Feature**: `panel-monorepo` | **Data**: 2026-08-28

> **O cenario que mais importa e o 1.** Uma suite verde nao prova esta feature:
> os testes exercitam a selecao de asset contra stubs de `curl`, nao contra uma
> release real produzida pelo workflow real. O equivalente ao "roundtrip
> empirico" aqui e o ensaio de release ponta-a-ponta. Um plano que so afirme
> "os testes cobrem" nao prova o caminho que mais importa.

---

## Cenario 1 — Ensaio de release ponta-a-ponta (PROVA PRINCIPAL)

**Cobre**: FR-008, FR-010, FR-011, FR-014, FR-018, FR-019, SC-001
**Tipo**: manual, uma vez, antes de qualquer arquivamento (FR-019)

1. Em branch de trabalho, com `panel/` ja importado e `serve.sh` ja corrigido,
   criar uma tag de teste (ex. `v9.6.0-rc.1`) e empurra-la.
2. Aguardar o `release.yml` concluir.
3. **Expected**: a release publica **quatro** artefatos de pacote:
   `cstk-<bare>.tar.gz`, `cstk-<bare>.tar.gz.sha256`,
   `cstk-panel-<bare>.tar.gz`, `cstk-panel-<bare>.tar.gz.sha256` (mais
   `cli/install.sh`).
4. Apontar o serve para essa release e rodar a atualizacao:
   `CSTK_PANEL_REPO=<owner/repo-de-teste> cstk serve --update`
5. **Expected (a)**: a saida informa o download do asset **do painel** — a URL
   impressa por `serve.sh:399` contem `cstk-panel-`, nunca `cstk-<bare>`.
6. **Expected (b)**: outcome `verified` — nenhuma linha nova em
   `.claude/enforcement-log.jsonl` (sucesso e silencioso por desenho).
7. **Expected (c)**: `.panel-version` contem a tag da release do **cstk**.
8. **Expected (d)**: a arvore extraida contem `apps/server/`, `apps/web/`,
   `packages/shared-types/`, `package.json` e `package-lock.json` na raiz.

> **Nota sobre tag de teste com sufixo**: `release.yml:102-104` marca
> `--prerelease` para tags com sufixo SemVer, e o `serve` recusa
> `prerelease:true`. Portanto o ensaio MUST usar tag **sem** sufixo, ou marcar
> a release de teste como nao-prerelease manualmente antes do passo 4. Ignorar
> isso produz um falso negativo que parece bug de selecao.

**Criterio de falha que importa**: se (a) falhar mas (b) passar, o defeito
original se reproduziu — carimbo de integridade sobre o pacote errado.

---

## Cenario 2 — Selecao com os dois pares na mesma release (automatizado)

**Cobre**: FR-008, FR-014, SC-001
**Onde**: `tests/cstk/test_serve.sh`, novo modo em `_stub_curl_release_assets`
(bloco existente ~1670-1755, que ja tem `ok` / `no-sibling` / `bad-sha` /
`evil-host`)

1. Novo modo `both-pairs`: `assets[]` lista o par do toolkit
   (`cstk-9.9.9.tar.gz` + `.sha256`) **antes** do par do painel
   (`cstk-panel-9.9.9.tar.gz` + `.sha256`).
2. Rodar `_serve_download_verify_extract`.
3. **Expected**: `curl-urls.log` registra o download de `cstk-panel-9.9.9.tar.gz`
   e **nao** o de `cstk-9.9.9.tar.gz`.
4. **Expected**: instalacao conclui com outcome `verified`.

A ordem invertida no passo 1 e essencial: com o painel primeiro, o codigo
antigo tambem passaria, e o teste nao provaria nada.

---

## Cenario 3 — Release so com o pacote do toolkit (error case)

**Cobre**: FR-008 (User Story 2, cenario de aceite 2), Edge Case "release sem pacote de painel"

1. Novo modo `toolkit-only`: `assets[]` tem apenas o par `cstk-*`.
2. Rodar o download.
3. **Expected**: nenhum asset e selecionado; o fluxo cai no auto-tarball
   (comportamento pre-existente), e **nao** baixa `cstk-9.9.9.tar.gz`.
4. **Expected**: o resultado e o outcome de nao-verificavel ja existente, nao
   um `verified` sobre o pacote do toolkit.

---

## Cenario 4 — Checksum confere mas o payload nao e o painel (error case)

**Cobre**: FR-009
**Onde**: `tests/cstk/test_serve.sh`

1. Novo modo `wrong-payload`: asset `cstk-panel-9.9.9.tar.gz` com `.sha256`
   **correto**, mas o tarball servido nao contem `package.json` na raiz apos
   `--strip-components 1`.
2. Rodar o download.
3. **Expected**: instalacao falha (exit != 0).
4. **Expected**: `.claude/enforcement-log.jsonl` ganha **uma** linha com
   `"source":"serve-integrity"` e `"outcome":"wrong-payload-blocked"`, em que
   `expected_sha256` e `actual_sha256` sao **iguais e nao-nulos**.

O passo 4 e o que distingue esta feature do estado atual: hoje o mesmo input
falha silenciosamente do ponto de vista da auditoria.

---

## Cenario 5 — Versionamento de `panel/.claude/` sobrevive a migracao

**Cobre**: FR-003, SC-003

> Este cenario testa a coisa certa. Contar arquivos rastreados apos o import
> **passaria verde mesmo sem o fix** — `git subtree add` traz os arquivos ja
> rastreados, porque `.gitignore` nao governa merge de tree (sonda empirica,
> `research.md` Decision 4 / dec-020). O dano e prospectivo.

1. Apos o `git subtree add`, contar: `git ls-files panel/.claude | wc -l`.
2. **Expected**: mesmo total de antes da migracao (173 no momento da medicao).
3. Criar um arquivo novo: `echo x > panel/.claude/probe.md`.
4. `git add panel/.claude/probe.md`
5. **Expected**: **aceito**. Se recusado com "The following paths are ignored
   by one of your .gitignore files: panel/.claude", o ajuste de `.gitignore`
   nao foi aplicado.
6. `mkdir -p .claude && echo y > .claude/probe.md && git add .claude/probe.md`
7. **Expected**: **recusado** — a raiz continua ignorando `.claude`, como hoje.
   Se aceito, a ancoragem foi ampla demais e passou a versionar o `.claude` do
   toolkit.
8. Limpar os arquivos de sonda.

---

## Cenario 6 — Historico preservado

**Cobre**: FR-001, SC-002

1. `git log --follow -- panel/package.json | tail -5`
2. **Expected**: commits anteriores a migracao, com autoria e datas originais.
3. `git blame panel/apps/server/src/lib/project-root.ts | head -3`
4. **Expected**: atribuicao a commits do historico do painel, nao ao commit de
   subtree.

---

## Cenario 7 — Suites verdes, sem regressao

**Cobre**: FR-014, SC-004, SC-005

1. `./tests/run.sh` na raiz.
2. **Expected**: verde. E o gate bloqueante de `release.yml:77`; inclui
   `test_serve.sh` e `test_serve-docker.sh`, que fixam URLs e nomes.
   **Baseline medido antes da migracao** (commit `90c0417`, dec-025):
   `./tests/run.sh cstk/test_serve.sh` => `PASS: 74  FAIL: 0  ERROR: 0
   ORPHANS: 0`; `./tests/run.sh cstk/test_serve-docker.sh` => `PASS: 53`.
   FR-014 exige comparar contra **74** (e **53**), nao contra o numero
   citado no plano-insumo (55) — a diferenca esconderia 19 cenarios numa
   regressao.
3. `./tests/run.sh --check-coverage`
4. **Expected**: sem orfaos. O gate varre apenas
   `plugins/cstk/skills/*/scripts/*.sh` e `cli/lib/*.sh` (`-maxdepth 1`);
   acrescentar `panel/` nao introduz script nao coberto.
5. `cd panel && npm test && npm run typecheck && npm run build`
6. **Expected**: verde, como projeto autocontido, sem depender de nada da raiz.

---

## Cenario 8 — Governanca dupla sem falso conflito

**Cobre**: FR-007, User Story 1 / AC4

1. `pipeline.sh constitution-conflict --projeto-alvo-path <repo> --feature-dir <repo>/docs/specs/<f>`
2. **Expected**: `status: pre-skill-alert` (exit 2) — identico ao de hoje,
   nunca `exit 1` (CONFLITO).
3. `pipeline.sh constitution-conflict --projeto-alvo-path <repo>/panel --feature-dir <repo>/panel/docs/specs/<f>`
4. **Expected**: `status: pre-skill-alert` (exit 2).
5. **Expected**: em nenhum dos dois a constituicao do outro projeto aparece na
   saida.

---

## Cenario 9 — Identidade `cstk-panel` preservada

**Cobre**: FR-020, FR-021, SC-007

1. Rodar uma feature-00c curta com PAP = `<repo>/panel` e
   `--canonical-project cstk-panel`.
2. Verificar na knowledge.db que as linhas novas tem `project = 'cstk-panel'`.
3. **Expected**: `project = 'cstk-panel'`, nunca `panel`.
4. **Expected**: o state da execucao vive em
   `<repo>/panel/.claude/feature-00c-state/<short>/`, e nao aparece nada novo
   em `<repo>/.claude/feature-00c-state/`.
5. Abrir o painel e navegar as execucoes do projeto `cstk-panel`.
6. **Expected**: as 7 execucoes historicas continuam resolvendo (sem orfaos,
   sem identidade duplicada).

---

## Cenario 10 — Guard fail-closed do Docker

**Cobre**: FR-010, User Story 2 / AC4

1. `cstk serve --docker` sobre o tarball do Cenario 1.
2. **Expected**: build prossegue — `package-lock.json` presente na raiz
   extraida satisfaz o guard de `serve-docker.sh:356`; `npm ci` roda.
3. **Expected**: nenhuma degradacao para `npm install`.

---

## Cenario 11 — Drift de majors de Node

**Cobre**: Decision 5 de `research.md`

1. Rodar o teste de drift novo.
2. **Expected**: verde — `panel/package.json` `engines.node` =
   `"20.x || 22.x || 23.x || 24.x"` casa com
   `_SERVE_SUPPORTED_NODE_MAJORS="20 22 23 24"`.
3. Alterar temporariamente `engines.node` do painel (ex. remover `24.x`).
4. **Expected**: teste **falha**, apontando os dois arquivos.
5. Reverter.

---

## Cenario 12 — Aviso de transicao visivel

**Cobre**: FR-018, FR-022, SC-006

1. Instalar o painel na versao da release-ponte do repositorio `cstk-panel`.
2. Abrir a UI.
3. **Expected**: aviso visivel e persistente informando a mudanca de local e a
   acao necessaria (`cstk self-update`).
4. Desconectar a rede e recarregar.
5. **Expected**: o aviso continua visivel — e estatico, nao depende de fetch
   (Principio IV).


---

## Cenario 13 — Override de origem e allowlist de host (error case)

**Cobre**: FR-012, FR-013, `contracts/serve-asset-selection.md` §7

1. `CSTK_PANEL_REPO=meu-fork/cstk cstk serve --update`
2. **Expected**: consulta `https://api.github.com/repos/meu-fork/cstk/releases/latest`;
   aviso em stderr informando origem nao-default; uma linha correspondente no
   `enforcement-log.jsonl`.
3. `CSTK_PANEL_REPO='../../etc' cstk serve --update`
4. **Expected**: erro fail-closed de formato invalido. **Nao** pode cair
   silenciosamente no default — isso mascararia configuracao errada.
5. `CSTK_PANEL_REPO='evil.com/x' cstk serve --update`
6. **Expected**: a barra faz o valor casar o formato `owner/repo`, mas o host da
   URL composta continua sendo `api.github.com` por construcao. Confirmar que
   nenhuma requisicao sai para `evil.com`.
7. Sem a variavel definida.
8. **Expected**: default `JotJunior/cstk`, sem aviso, sem linha de log.

---

## Cenario 14 — Lockstep de versao entre painel e toolkit

**Cobre**: FR-015, FR-016, User Story 3 / cenarios de aceite 1 e 2

1. Apos um ciclo de release da tag `vX.Y.Z`.
2. **Expected**: `panel/package.json` tem `version` = `X.Y.Z`.
3. **Expected**: os tres workspaces (`apps/server`, `apps/web`,
   `packages/shared-types`) tem a **mesma** `X.Y.Z`, sem divergencia entre si.
4. **Expected**: `panel/package-lock.json` reflete as mesmas versoes.
5. **Expected**: os 3 arquivos de versao do toolkit
   (`.claude-plugin/marketplace.json` e os 2 `plugin.json`) tambem em `X.Y.Z` —
   `validate-plugin-manifests.sh --strict` (MP-5) ja e gate bloqueante do
   `release.yml` para esses.

---

## Cenario 15 — Nenhum documento afirma origem externa

**Cobre**: FR-017, SC-008

1. `git ls-files '*.md' | grep -v '^docs/specs/_archived/' | xargs grep -l 'cstk-panel'`
2. **Expected**: os arquivos retornados sao **apenas** os de mencao historica
   legitima — `CHANGELOG.md` (entradas passadas), o artigo datado, e
   `panel/**` (o proprio projeto). Nenhum documento afirma, em tempo presente,
   que o painel e obtido de um repositorio externo separado.
3. Inspecionar `docs/cstk-serve.md`, `docs/cstk-serve.pt-BR.md`,
   `cli/README.md`, `cli/README.pt-BR.md`.
4. **Expected**: descrevem a origem como as releases do proprio repositorio
   unificado.
5. **Expected**: `CHANGELOG.md` **nao** foi reescrito — reescrever historico
   seria falsificacao, nao correcao (`research.md` Decision 11).

---

## Cenario 16 — Tarball nao carrega configuracao de agente

**Cobre**: endurecimento de `research.md` Decision 12 (escopo do `git archive`)

1. `tar -tzf dist/cstk-panel-<bare>.tar.gz | grep -c '\.claude/'`
2. **Expected**: `0` — `export-ignore` via `.gitattributes` mantem
   `panel/.claude/` versionado no repositorio mas **fora** do pacote
   distribuido.
3. `tar -tzf dist/cstk-panel-<bare>.tar.gz | grep -c '\.github/'`
4. **Expected**: `0`.
5. `tar -tzf dist/cstk-panel-<bare>.tar.gz | awk -F/ '{print $1}' | sort -u | wc -l`
6. **Expected**: `1` — um unico diretorio de topo, `cstk-panel-<bare>/`.

---

## Cenario 17 — `tag_name` malformado (fail-closed) (error case)

**Cobre**: FR-023
**Onde**: `tests/cstk/test_serve.sh`, novo modo em `_stub_curl_release_assets`

1. Novo modo `bad-tag-name`: a resposta stubada da API de releases traz
   `tag_name` fora do formato esperado apos `bare()` (ex. `v1.2/evil` ou
   `v1 2.3`, contendo `/` ou espaco).
2. Rodar `_serve_download_verify_extract`.
3. **Expected**: fail-closed para o auto-tarball pre-existente — nenhum asset
   do painel (nem do toolkit) e selecionado por correspondencia de nome
   vinculada a essa tag.
4. **Expected**: uma linha em stderr citando o formato esperado
   (`^[0-9A-Za-z][0-9A-Za-z.+-]*$`).

Um cenario que passasse com ou sem a validacao de I5 nao provaria nada — este
cenario so passa se o fail-closed de fato disparar diante do `tag_name`
malformado (`contracts/serve-asset-selection.md` §3.2 I5).

---

## Cenario 18 — Colisao de nomes de topo preservada (FR-004)

**Cobre**: FR-004

1. Antes da migracao, listar os arquivos de topo homonimos existentes em
   ambos os projetos: `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md` (se
   existir), workflow de CI.
2. Apos o `git subtree add`, confirmar que ambas as versoes existem sob paths
   distintos: `./README.md` (raiz, intacto) e `panel/README.md` (painel,
   intacto) — mesma verificacao para `CHANGELOG.md` e os demais arquivos
   homonimos.
3. **Expected**: nenhum dos dois foi sobrescrito; o conteudo de cada lado
   permanece identico ao pre-migracao.
4. **Expected**: `panel/.github/workflows/` nao colide com
   `.github/workflows/` da raiz — paths distintos, sem merge de conteudo.

---

## Cenario 19 — Historico de mudancas: congelado vs. unico (FR-006)

**Cobre**: FR-006

1. Apos o `git subtree add` (FASE 1) e a nota do cabecalho de
   `panel/CHANGELOG.md` (FASE 2, task 2.3.1 — movida de 0.3.2), verificar que
   `panel/CHANGELOG.md` mantem as entradas anteriores a migracao intactas,
   sem reescrita — mesmo principio ja aplicado ao `CHANGELOG.md` da raiz no
   Cenario 15.
2. Apos o primeiro release pos-migracao que tambem toque o painel, confirmar
   que a nova entrada foi adicionada ao `CHANGELOG.md` da raiz do
   repositorio unificado, e **nao** a `panel/CHANGELOG.md`.
3. **Expected**: `panel/CHANGELOG.md` permanece congelado a partir da
   migracao — zero entradas novas nele; `CHANGELOG.md` da raiz passa a ser a
   unica fonte de novas entradas que tambem tocam o painel.
