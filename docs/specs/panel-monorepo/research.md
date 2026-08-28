# Research: panel-monorepo

**Feature**: `panel-monorepo`
**Data**: 2026-08-28
**Insumo primario**: plano de migracao aprovado pelo operador
(`~/.claude/plans/typed-snacking-diffie.md`), com mapa de acoplamento,
6 decisoes fechadas, passos, verificacao e riscos assumidos.

> **Nota de proveniencia (Constitution VI).** Todo fato afirmado abaixo tem
> fonte citada em codigo do repositorio-alvo ou em sonda empirica executada
> durante esta onda. Onde o plano-insumo e a sonda divergiram, prevalece a
> sonda e a divergencia esta registrada como Decisao auditavel (dec-020).
>
> **Numeros derivados de git** nao existem como literal em nenhum arquivo — sao
> resultado de comando. Comandos exatos, para qualquer leitor re-derivar (todos
> executados em `/Users/jot/Projects/_lab/Jot/misc/cstk-panel` em 2026-08-28,
> exceto o ultimo):
>
> | Numero | Comando |
> |---|---|
> | 248 commits | `git rev-list --count HEAD` |
> | 499 arquivos rastreados | `git ls-files \| wc -l` |
> | 173 sob `.claude/` | `git ls-files .claude \| wc -l` |
> | 1 arquivo `.sh` | `git ls-files '*.sh'` |
> | 0 `CLAUDE.md` | `git ls-files '*CLAUDE.md'` |
> | 8 specs do painel | `ls docs/specs` |
> | 18 specs do toolkit | `ls -1 docs/specs \| grep -vx _archived \| grep -vx current` (no repo `cstk`; inclui a propria `panel-monorepo`) |
>
> O total bruto de arquivos sob `.claude/` no filesystem e muito maior que 173:
> `.gitignore` do painel exclui `.claude/agente-00c-state/state-history/` e
> `.lock/`. Contar arquivos do filesystem **nao** substitui `git ls-files` aqui.

---

## Decisoes ja fechadas pelo operador (NAO reabertas aqui)

As seis escolhas abaixo vieram da tabela "Decisoes do operador" do plano
aprovado. Elas tocam eixos que, em execucao autonoma, exigiriam bloqueio
humano — e ja o tiveram, na forma da aprovacao explicita do plano. O Phase 0
as CONSOME, nao as re-decide.

| Tema | Decisao do operador |
|---|---|
| Versionamento | Unificado — painel salta de 0.34.1 para 9.x |
| Historico | Preservar os 248 commits via `git subtree` |
| Layout | `panel/` na raiz, ao lado de `cli/`, `mcp/`, `plugins/` |
| Identidade na knowledge.db | `cstk-panel` preservado via `--canonical-project` |
| `.claude/` do painel | Preservar os arquivos versionados, ajustando o `.gitignore` |
| Transicao | Release-ponte final no `cstk-panel`, depois arquivar |

---

## Decision 1 — Selecao do asset do painel por nome, nao por posicao

**Decision**: alterar a selecao de asset em `cli/lib/serve.sh` para exigir que
o basename da URL comece com `cstk-panel-` **e** termine em `.tar.gz`, alem do
sibling `.sha256` exato ja exigido hoje. Sem candidato do painel, cair no
auto-tarball (fallback atual), nunca em outro asset.

**Rationale**: a selecao hoje e posicional. `cli/lib/serve.sh:390-393`:

```awk
{ seen[$0] = 1; url[NR] = $0 }
END {
  for (i = 1; i <= NR; i++)
    if (url[i] ~ /\.tar\.gz$/ && (url[i] ".sha256") in seen) { print url[i]; exit }
}
```

O predicado e "primeiro `.tar.gz` com sibling `.sha256`" — nao ha template de
nome. O `release.yml` do cstk (linhas 105-110) ja publica
`cstk-${BARE}.tar.gz` + `.sha256`. Publicar tambem o par do painel na mesma
release faz o `exit` disparar no primeiro par encontrado, que pode ser o do
toolkit.

A falha resultante e a pior classe possivel: o checksum do toolkit **confere**
(outcome `verified`), e `verified` e deliberadamente silencioso — `serve.sh:457`
comenta "outcome=verified: sucesso silencioso, SEM linha no enforcement-log".
Só entao a extracao falha em `serve.sh:488` ("package.json ausente apos
extracao"). Carimbo de integridade sobre o pacote errado, sem rastro.

**Alternatives considered**:

- *Publicar o painel numa release separada / repositorio separado*: derrota o
  proposito da migracao (FR-011 exige mesma release versionada).
- *Ordenar os assets no upload para o painel vir primeiro*: depende de ordem
  da API do GitHub, que nao e contratual. Frageis por construcao.
- *Match por substring `panel`*: rejeitado pela mesma disciplina anti-spoofing
  ja documentada em `serve.sh:383-386` ("Pareamento por igualdade de string
  completa (lookup associativo do awk), nunca substring"). Um asset chamado
  `cstk-panel-tools-1.0.tar.gz` casaria. O predicado usa prefixo de **basename**
  ancorado, nao substring de URL.

**Cuidado de implementacao**: `cstk-` e prefixo de `cstk-panel-`. O predicado
MUST ser `cstk-panel-`, senao o tarball do toolkit casa tambem.

---

## Decision 2 — Falha pos-extracao deixa de ser silenciosa (FR-009)

**Decision**: quando o pacote selecionado passa no checksum mas a arvore
extraida nao contem os marcadores do painel, gravar uma linha no
`enforcement-log.jsonl` com outcome novo `wrong-payload-blocked`, antes de
retornar erro.

**Rationale**: FR-009 exige que a confirmacao de checksum anterior nao seja
reportada como confirmacao suficiente de que o pacote correto foi obtido. Hoje
o caminho e mudo: `verified` nao loga (`serve.sh:457`) e o erro de extracao
(`serve.sh:487-492`) so vai a stderr. Um operador que investigue depois nao
tem evidencia de que a verificacao recaiu sobre o pacote errado.

O escritor ja existe e e best-effort por contrato:
`_serve_write_integrity_log OUTCOME PKG_URL EXPECTED ACTUAL BYPASS`
(`serve.sh:247-281`), gravando em `<cwd>/.claude/enforcement-log.jsonl` com
`source:"serve-integrity"`.

**Alternatives considered**:

- *Reusar `mismatch-blocked`*: mentiria. O hash conferiu; o que falhou foi a
  selecao. Poluir o enum degradaria a auditoria de integridade real.
- *Nao logar, so melhorar a mensagem de stderr*: stderr nao persiste; FR-009
  fala em nao reportar sucesso como suficiente, o que pede rastro durave.

**Impacto de contrato**: o enum de `outcome` para `source:"serve-integrity"`
era `unverifiable-blocked | unverifiable-bypassed | mismatch-blocked`
(`serve.sh:236-238`). Passa a incluir `wrong-payload-blocked`. Delta
documentado em `contracts/serve-asset-selection.md`. O consumidor
(`pretooluse-bash-guard.sh`) le linhas por `source`, nao valida enum fechado —
adicionar valor e retrocompativel.

---

## Decision 3 — `CSTK_PANEL_REPO` como override, sob a mesma allowlist

**Decision**: introduzir `CSTK_PANEL_REPO="${CSTK_PANEL_REPO:-JotJunior/cstk}"`
e compor a URL da API a partir dele, substituindo a constante hardcoded.

**Rationale**: `serve.sh:66` hoje e
`_SERVE_GITHUB_API="https://api.github.com/repos/JotJunior/cstk-panel/releases/latest"`
— hardcoded e sem escape. A assimetria e real e verificavel: `cli/install.sh:44`
usa `CSTK_REPO="${CSTK_REPO:-JotJunior/cstk}"` e `cli/lib/install.sh:21`
documenta "$CSTK_REPO override permite apontar para um fork". FR-012 pede
paridade.

Note-se que o valor **default muda de repositorio** nesta feature
(`JotJunior/cstk-panel` -> `JotJunior/cstk`), porque o painel passa a ser
publicado nas releases do proprio toolkit (FR-011).

**FR-013 (host confiavel)**: nenhuma excecao e criada. A URL composta passa
pelos mesmos `_serve_check_host_allowlist` ja invocados (`serve.sh:407`), que
delegam a `trusted_host_check` de `cli/lib/trusted-hosts.sh`. A allowlist e
constante versionada, deliberadamente NAO lida de env
(`trusted-hosts.sh:47`: `CSTK_TRUSTED_RELEASE_HOSTS="github.com
codeload.github.com objects.githubusercontent.com api.github.com"`; linhas
17-22 explicam que alargar via env var e vetado). Logo `CSTK_PANEL_REPO`
permite trocar o **owner/repo**, jamais o **host** — que e exatamente a
propriedade que FR-013 exige.

**Alternatives considered**:

- *Permitir URL completa via env*: abriria bypass de host se a validacao fosse
  esquecida em algum caminho. Restringir a `owner/repo` mantem o host fixo por
  construcao.

---

## Decision 4 — Ancorar `.claude` na raiz (`/.claude`), com rationale corrigido

**Decision**: alterar `.gitignore` da raiz, linha 3, de `.claude` para
`/.claude`. O `panel/.gitignore` (que ja tem as excecoes do painel nas linhas
22-26) passa a governar `panel/.claude/` sem interferencia da raiz.

**Rationale (CORRIGIDO — dec-020)**: o plano-insumo afirma que "sem ajuste, o
subtree desversiona os 173 arquivos em silencio". **Sonda empirica contradiz.**

Sonda executada em repositorio scratch reproduzindo a topologia (repo `main`
com `.claude` ignorado + repo `sub` com `.claude` rastreado):

| Passo | Resultado observado |
|---|---|
| `git subtree add --prefix=panel sub main` | `git ls-files panel/.claude` = **2/2 rastreados** |
| `git check-ignore -v panel/.claude/tracked-one.md` | nao casa (tracked ocultos sem `--no-index`) |
| `git check-ignore -v --no-index <mesmo>` | `.gitignore:3:.claude` — o padrao **casa** |
| `git add panel/.claude/novo.md` (arquivo NOVO) | **recusado**: "The following paths are ignored ... panel/.claude" |

Motivo: `.gitignore` governa arquivos **nao rastreados**. O `subtree add` e um
merge de tree — os blobs entram pelo indice, nao por varredura do working dir.
Portanto **nao ha perda no import**.

O dano e **prospectivo**: qualquer arquivo novo criado sob `panel/.claude/`
depois da migracao e recusado pelo `git add`, e a convencao do painel (que
versiona deliberadamente state e relatorios de execucao — 165 arquivos sob
`.claude/feature-00c-state/`, 3 sob `.claude/agente-00c-state/`, mais
`settings.json`) para de valer em silencio.

Isso muda o **criterio de verificacao**: contar 173 arquivos apos o import
passaria verde mesmo sem o fix. A verificacao correta e tentar adicionar um
arquivo novo sob `panel/.claude/` (ver `quickstart.md` Cenario 5).

Fix validado na mesma sonda:

| Apos `/.claude` ancorado | Resultado |
|---|---|
| `git add panel/.claude/novo.md` | **aceito** |
| `git add .claude/x.md` (raiz) | recusado — raiz segue ignorada, como hoje |

**Alternatives considered**:

- *`!panel/.claude/` como negacao na raiz*: git nao re-inclui conteudo de um
  diretorio ja excluido; exigiria negar tambem o diretorio pai. Ancorar e mais
  simples e mais legivel.
- *`git add -f` pontual*: exige disciplina humana a cada arquivo — precisamente
  o modo de falha silenciosa que se quer evitar.

**Achado colateral (latente, nao ativo)**: `.gitignore` raiz linha 4 e
`CLAUDE.md`, tambem nao-ancorado, e portanto casaria `panel/CLAUDE.md`.
Verificado que o painel **nao** rastreia nenhum `CLAUDE.md` hoje
(`git ls-files '*CLAUDE.md'` = 0), entao nao ha perda atual. Ancorar para
`/CLAUDE.md` na mesma edicao e barato e fecha a armadilha antes que alguem
crie o arquivo. Os demais padroes nao-ancorados (`dist/`, `tmp/`, `.idea`,
`.DS_Store`) sao inofensivos: o painel ignora os mesmos caminhos e nao rastreia
nenhum arquivo que case (`git ls-files | grep -E '(^|/)(dist|tmp)/'` = vazio).

---

## Decision 5 — `_SERVE_SUPPORTED_NODE_MAJORS`: espelho verificado, nao divida

**Decision**: manter a constante em `cli/lib/serve.sh:127` e adicionar um teste
de drift em `tests/cstk/` que le `panel/package.json` (campo `engines.node`)
com `awk` POSIX e falha se a faixa divergir da constante.

**Rationale**: hoje sao duas fontes para o mesmo fato, e o proprio codigo pede
sincronizacao manual (`serve.sh:124-127`: "Atualizar em sincronia quando o
painel mudar a faixa. Constante fixa, NAO overridable via env"). A duplicacao
existia porque o painel estava **noutro repositorio** — nao havia como
verificar. O monorepo remove essa impossibilidade.

Derivar a faixa em runtime foi rejeitado: exigiria parse de JSON no caminho
quente do `serve`, e o carve-out de dependencia obrigatoria da constitution
1.3.0 e explicitamente restrito a camada de estado transacional
(`state.db`/`agente-00c-runtime`), com a clausula (a) "Confinamento de camada:
nenhuma outra parte do toolkit (skills de documentacao, CLI de catalogo,
hooks) pode exigir a ferramenta como pre-requisito". `cli/lib/serve.sh` esta
fora do carve-out.

O teste de drift entrega o valor sem o custo: uma fonte de verdade (o painel) e
um espelho **verificado por gate bloqueante**, em `awk` POSIX, sem dep nova e
sem alterar o caminho de execucao. Hoje os valores ja coincidem
(`panel/package.json` -> `engines.node = "20.x || 22.x || 23.x || 24.x"`;
constante -> `"20 22 23 24"`), entao o teste nasce verde.

**Compatibilidade com o gate de cobertura**: `tests/run.sh:152-168` mapeia
`plugins/cstk/skills/<skill>/scripts/<n>.sh -> tests/test_<n>.sh` e
`cli/lib/<n>.sh -> tests/cstk/test_<n>.sh`, varrendo `cli/lib` com
`-maxdepth 1`. Um teste novo sob `tests/cstk/` e coberto pela lista de
excecoes ja existente para testes granulares por aspecto (linhas 188-202).

---

## Decision 6 — Aviso de transicao FR-022: estatico, embutido, zero rede

**Decision**: o aviso vive como elemento estatico no bundle do painel publicado
na release-ponte do repositorio `cstk-panel`. Nenhuma consulta de rede.

**Rationale**: FR-022 nasceu de um fato verificado — `cstk serve` consome
apenas `tag_name` e `tarball_url` da API e nunca exibe corpo/notas da release
ao operador, entao aviso so em release notes e invisivel a quem roda
`--update`.

A solucao nao pode, porem, violar o Principio IV (Zero Coleta Remota,
NON-NEGOTIABLE), cujo MUST veta "requisicao de rede para endpoint de
telemetria, analytics, feature-flag remoto" e limita fetches HTTP a skills
"inerentemente de rede". Um dashboard local read-only nao e.

Banner estatico embutido satisfaz "visivel e persistente a partir da
release-ponte" com zero rede e funciona offline.

**Alternatives considered**:

- *Feature-flag remoto*: vetado nominalmente pelo Principio IV.
- *Consultar a API de releases a partir da UI*: fetch nao inerente ao proposito
  + falha offline + reintroduz o acoplamento que a migracao remove.
- *Quebrar deliberadamente o start do painel para forcar visibilidade*: ja
  rejeitado na fase clarify (registrado em `spec.md` §Clarifications) por
  quebrar ferramenta que o operador nao pediu para quebrar.

---

## Decision 7 — FR-007 nao exige mudanca de codigo

**Decision**: nenhuma alteracao em `pipeline.sh`. A ausencia de falso conflito
de governanca e propriedade estrutural do detector, e sera coberta por teste de
regressao, nao por implementacao.

**Rationale**: `_pl_cmd_constitution_conflict`
(`plugins/cstk/skills/agente-00c-runtime/scripts/pipeline.sh:677-700`) compara
exatamente dois caminhos:

```sh
_root="$_pap/docs/constitution.md"
_feat="$_fd/constitution.md"
```

Ambos derivados do `--projeto-alvo-path` (PAP) e do `--feature-dir` (FD)
passados na chamada. O detector **nunca varre subdiretorios** procurando outras
constituicoes. Consequencias, por caminho de execucao:

| Execucao | `_root` | `_feat` | Resultado |
|---|---|---|---|
| PAP = raiz do repo, FD = `docs/specs/<f>` | `docs/constitution.md` (1.3.0) | `docs/specs/<f>/constitution.md` (ausente) | `pre-skill-alert` — igual a hoje |
| PAP = `panel/`, FD = `panel/docs/specs/<f>` | `panel/docs/constitution.md` (2.0.2) | ausente | `pre-skill-alert` — igual a hoje |

A constituicao do painel nunca entra no campo de visao de uma execucao da raiz,
nem vice-versa. `exit 1` (CONFLITO) exige `_has_root=1 && _has_feat=1`, o que
nenhum dos dois caminhos produz. FR-007 e satisfeito por construcao.

**Verificacao**: as duas constituicoes coexistem sem colisao de path
(`docs/constitution.md` 1.3.0 na raiz; `panel/docs/constitution.md` 2.0.2). Os
conjuntos de specs sao disjuntos hoje: 18 diretorios em `docs/specs/` do cstk
(excluindo `_archived/` e `current/`),
8 em `docs/specs/` do painel (`cstk-panel`, `dashboard-refactor`,
`decision-map-panel`, `new-schema`, `panel-schema-v3`, `session-tail`,
`state-watchers-and-docs`, `tema-claro-menu-retratil`) — intersecao vazia, e
sob `panel/` nem precisariam ser disjuntos.

---

## Decision 8 — Identidade `cstk-panel` via `--canonical-project`

**Decision**: execucoes de pipeline restritas ao painel rodam com PAP =
`<repo>/panel` e passam `--canonical-project cstk-panel`.

**Rationale**: a identidade de projeto nao e o repositorio git. E
`recall_derive_canonical` (`cli/lib/recall.sh`), em 3 camadas documentadas no
proprio cabecalho da funcao:

1. campo congelado `.execution.canonical_project` do state (FR-003 daquela
   feature);
2. resolucao git ao vivo — **somente quando `.git` e ARQUIVO** (indicador de
   worktree): `basename(dirname(git rev-parse --git-common-dir))`;
3. fallback: `basename(TARGET_PROJECT_PATH)`.

Sem a flag, uma execucao com PAP = `<repo>/panel` cairia na camada 3 (o
`.git` do monorepo e diretorio, nao arquivo) e produziria `panel` — identidade
nova, orfa das 7 execucoes historicas. Com a flag, a camada 1 congela
`cstk-panel` e a continuidade se mantem.

A flag ja existe e e suportada por `state-rw.sh` (`init`/`bootstrap`, opcao
`--canonical-project NAME`, com validacao de que `--session-name` a exige).
O que falta e os commands a passarem fora do caso worktree.

**Anti-eco (regra dura)**: `agente-00c-orchestrator.md` deriva
`EXCLUDE_FEATURE` da mesma expressao canonica. Os dois pontos MUST mudar na
mesma entrega — contrato `ingest-derivation.md` §4.

**FR-021 (isolamento de estado)**: satisfeito sem codigo novo.
`.claude/feature-00c-state/` e resolvido pelo PAP; com PAP = `<repo>/panel`, os
states do painel ficam em `panel/.claude/` e os do cstk na raiz. Isso importa
para `_hook-active-exec.sh`, que resolve **uma** execucao ativa por diretorio
de escopo com teto `_HAE_MAX_DIRS=100`. Precedente do proprio toolkit:
`cli/lib/session.sh` exclui `feature-00c-state` das copias de sessao porque
"copiar states do checkout principal confundia a precedencia do
pretooluse-guard".

---

## Decision 9 — Formato do pacote: `git archive HEAD:panel`

**Decision**: gerar o tarball do painel com
`git archive --format=tar.gz --prefix="cstk-panel-${BARE}/" -o dist/cstk-panel-${BARE}.tar.gz HEAD:panel`,
como passo novo do `.github/workflows/release.yml` do cstk.

**Rationale**: tres exigencias do consumidor convergem para essa forma exata.

1. `tar -xzf ... --strip-components 1` (`serve.sh:480`) exige **um unico**
   diretorio de topo. `--prefix="cstk-panel-${BARE}/"` entrega exatamente um.
2. `serve.sh:488` exige `package.json` na raiz da arvore extraida.
   `HEAD:panel` empacota o **conteudo** da subarvore, entao
   `panel/package.json` vira `cstk-panel-<bare>/package.json`, que apos o strip
   e a raiz.
3. `serve-docker.sh:356` e fail-closed sem `package-lock.json` na raiz da
   arvore extraida: `RUN test -f package-lock.json || { ... exit 1; }`, com o
   comentario explicito de que "o build nunca degrada silenciosamente para
   `npm install` (reprodutibilidade)". O painel tem `package-lock.json`
   rastreado na raiz do seu projeto, logo ele viaja.

Confirmado que o painel e projeto npm autocontido com workspaces
(`package.json`: `"workspaces": ["apps/*", "packages/*"]`,
`"engines": {"node": "20.x || 22.x || 23.x || 24.x", "npm": ">=10.0.0"}`) e
`package-lock.json` de 302 KB na raiz. O `apps/` real e `apps/server` +
`apps/web`, mais `packages/shared-types`.

**Alternatives considered**:

- *`tar -czf` sobre o diretorio de trabalho*: incluiria `node_modules/`,
  `dist/` e artefatos locais. `git archive` respeita o indice.
- *Reusar `scripts/build-release.sh`*: e o empacotador do **toolkit**, com
  outra arvore e outro determinismo. Misturar os dois acopla os empacotadores.

**Nota sobre prerelease**: `release.yml:102-104` marca `--prerelease` para tags
com sufixo SemVer, e o `serve` recusa releases `prerelease:true`. Logo
prereleases do toolkit nao expoem painel. Aceito e ja registrado como Edge Case
na spec — nao e lacuna desta migracao.

---

## Decision 10 — Hook local: exposicao real e menor do que o plano supunha

**Decision**: escopar apenas o hook de `shellcheck`; o hook de testes nao
precisa de mudanca por causa do painel (mas esta obsoleto por outro motivo).

**Rationale**: o plano-insumo trata os dois hooks de
`.claude/settings.local.json` como "roda `./tests/run.sh` e `shellcheck` por
prefixo de path". Leitura do arquivo real mostra comportamentos distintos:

| Hook | Matcher real | Alcanca `panel/`? |
|---|---|---|
| testes | `"$REPO"/global/skills/*/scripts/*.sh` e `"$REPO"/cli/lib/*.sh` | **Nao** — nenhum arquivo do painel casa |
| shellcheck | `*.sh` (sem prefixo de repo algum) | **Sim** — e ja alcanca qualquer `.sh` de qualquer projeto hoje |

Ou seja: o hook de testes ja e inofensivo para o painel; e o de shellcheck ja
era irrestrito **antes** da migracao — nao e regressao introduzida por ela.

O impacto pratico e pequeno e mensuravel: o painel rastreia **1** arquivo `.sh`
(`scripts/readonly-check.sh`). Ainda assim, a clarificacao ja registrada na
spec (§Clarifications, Q1) decidiu excluir `panel/**` do dispatch, e a
implementacao e barata.

**Achado colateral**: o primeiro branch do hook de testes aponta para
`"$REPO"/global/skills/...`, e `global/skills` **nao existe** neste repositorio
(as skills vivem em `plugins/cstk/skills/`). Esse branch esta morto hoje,
independente da migracao. Fica registrado como observacao para o operador; nao
e escopo desta feature corrigi-lo, e nenhuma task o assume.

---

---

## Decision 11 — Inventario de documentacao: lista verificada, nao a do insumo

**Decision**: FR-017/SC-008 miram a lista obtida por `grep`, nao a do
plano-insumo.

**Rationale**: o plano-insumo (Parte 3, passo 9) afirma que "6 arquivos afirmam
que o download vem de `JotJunior/cstk-panel`" e lista
`docs/cstk-serve.{md,pt-BR.md}`, `cli/README.{md,pt-BR.md}`, `README.md`,
`docs/agente-00c.{md,pt-BR.md}`. Verificacao contradiz a composicao (dec-023):

```
git ls-files '*.md' | grep -v '^docs/specs/' | xargs grep -l 'cstk-panel'
```

| Arquivo | No insumo? | Menciona de fato? | Acao |
|---|---|---|---|
| `docs/cstk-serve.md` | sim | sim | **[MODIFICAR]** |
| `docs/cstk-serve.pt-BR.md` | sim | sim | **[MODIFICAR]** |
| `cli/README.md` | sim | sim | **[MODIFICAR]** |
| `cli/README.pt-BR.md` | sim | sim | **[MODIFICAR]** |
| `README.md` | sim | **nao** (0 hits) | nao tocar |
| `docs/agente-00c.md` | sim | **nao** (0 hits) | nao tocar |
| `docs/agente-00c.pt-BR.md` | sim | **nao** (0 hits) | nao tocar |
| `CHANGELOG.md` | nao | sim | nao reescrever — e historico |
| `docs/artigo-linkedin-cstk-orquestracao.md` | nao | sim | nao reescrever — e artigo datado |
| `docs/cstk-panel/backend-brief.md` | nao | sim | **[REVISAR]** |
| `docs/cstk-panel/frontend-brief.md` | nao | sim | **[REVISAR]** |

Seguir o insumo faria a task de documentacao editar tres arquivos sem nenhuma
mencao e ignorar quatro que mencionam. SC-008 ("zero documentos ainda descrevem
o painel como distribuido de um repositorio externo separado") fecharia
falso-verde.

**Criterio de aceite operacional para SC-008**: o `grep` acima, apos a
migracao, so pode retornar arquivos cuja mencao seja **historica** (`CHANGELOG.md`,
artigo datado, specs arquivadas sob `docs/specs/_archived/`) — nunca uma
afirmacao em tempo presente sobre onde o painel e obtido. Reescrever historico
de CHANGELOG seria falsificacao, nao correcao.

---

## Decision 12 — Endurecimentos vindos do gate `owasp-security`

**Decision**: incorporar ao design, ainda na fase `plan`, tres correcoes
apontadas pelo gate; escalar ao operador duas questoes que extrapolam o escopo
desta feature.

**Rationale**: o gate rodou sobre `plan.md`, `research.md`,
`contracts/serve-asset-selection.md` e `spec.md`, mais o codigo real de
`serve.sh`, `trusted-hosts.sh` e `serve-docker.sh`. Verdito: 0 critical,
4 high, 5 medium, 3 low.

### Incorporado nesta feature (design corrigido)

| Origem | Correcao | Onde |
|---|---|---|
| High — gate de wrong-payload | `package.json` pos-extracao nao prova "e o painel", e roda depois de a arvore hostil ja estar em disco. Passa a haver validacao da lista de membros (`tar -tzf`) ANTES de extrair, mais `--no-same-owner --no-same-permissions` | `contracts/...` §8 |
| High — `CSTK_PANEL_REPO` | valor sem validacao de formato, sem passar pela allowlist, e sem anuncio quando difere do default | `contracts/...` §7 |
| Medium — prefixo nao e inequivoco | `cstk-panel-` casaria `cstk-panel-docs-*`. Passa a ser igualdade com nome exato derivado de `tag_name` | `contracts/...` §3.2 |

O terceiro item merece destaque: FR-008 pede "correspondencia **inequivoca** de
nome". Prefixo satisfaz "por nome, nao por posicao", mas nao satisfaz
"inequivoca". A leitura do gate esta correta e o contrato foi ajustado — nome
exato `cstk-panel-<bare>.tar.gz`, vinculado a versao da release (invariante I4).

### Escalado ao operador (fora do escopo desta feature)

| Origem | Questao | Por que nao decido aqui |
|---|---|---|
| High — proveniencia do artefato | o `.sha256` vive no mesmo dominio de confianca do asset; nao ha assinatura nem attestation. Quem publica release (ou um Actions run comprometido) obtem `verified` e, na sequencia, `npm ci` — execucao de codigo | E o modelo de confianca **pre-existente** de toda a distribuicao do toolkit. Mas esta feature **amplia** o alcance: a mesma release passa a carregar toolkit e painel, unificando o raio de dano. Adotar attestation/assinatura e mudanca de politica de release, nao detalhe de implementacao |
| High — redirecionamentos | `cli/lib/http.sh` usa `curl -fsSL`, que segue redirect, e a allowlist e checada apenas na URL pre-redirect, nunca em `url_effective` | Defeito **pre-existente**, em arquivo que esta feature nao toca. Corrigir aqui seria escopo alheio; ignorar sem registro seria pior |

Ambos viram BloqueioHumano nesta onda (Principio de seguranca como MUST na
tabela de gates: finding `high` em gate de seguranca exige decisao do operador).

### Registrado, nao acionado nesta feature

Os demais medium/low (escopo do `git archive` incluindo `panel/.claude/`;
parsing de `browser_download_url` fora de `assets[]`; `prerelease`/`draft` via
`grep`+`head -1` sem fail-closed; ausencia de anti-rollback contra
`.panel-version`; binding fraco do nome no arquivo `.sha256`) sao reais e
concretos, mas nenhum e **introduzido** por esta migracao. Ficam anotados aqui
para virarem feature propria de endurecimento do `cstk serve`, e a decisao de
prioriza-los e do operador.

Uma excecao merece nota: o escopo do `git archive` **e** introduzido aqui —
`HEAD:panel` empacota tudo que esta rastreado, incluindo os 173 arquivos de
`panel/.claude/` que a Decision 4 deliberadamente mantem versionados. Isso
distribuiria configuracao de agente a toda instalacao. Mitigacao barata e
dentro do escopo: `export-ignore` via `.gitattributes` para `panel/.claude`,
`panel/.github` e testes, mais assercao da lista de membros no passo "Verify
build artifacts" do workflow. Incorporado ao plano de tarefas.

---

## Riscos assumidos (herdados do plano aprovado, revalidados)

| Risco | Estado apos verificacao |
|---|---|
| Ordenacao: `serve.sh` corrigido so chega via `cstk self-update` | Confirmado. Mitigado pela release-ponte (FR-018/FR-019). |
| Suite do painel fora do CI | Confirmado: `panel/.github/workflows/` tem apenas `release.yml`; nao ha workflow de teste. A spec (§Clarifications Q2) registra como estado herdado, nao nova obrigacao. |
| Hook local com `REPO` hardcoded | Reavaliado — exposicao menor que a suposta (Decision 10). |
| Duas constituicoes convivendo | Confirmado seguro por construcao (Decision 7). `feature-00c-preflight.sh` congela hash+versao por execucao, o que protege mas trava retomada se o arquivo trocar no meio. |

