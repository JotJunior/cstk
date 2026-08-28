# Contrato: selecao e verificacao do asset do painel (`cstk serve`)

**Feature**: `panel-monorepo`
**Consumidor**: `cli/lib/serve.sh` (`_serve_download_verify_extract`)
**Cobre**: FR-008, FR-009, FR-010, FR-011, FR-012, FR-013, FR-014 (§3.3), FR-022 (§2)

> **Estado dos itens**. Marcados `[ATUAL]` = comportamento hoje observado no
> codigo, com linha citada. Marcados `[PROPOSTA]` = mudanca desenhada por esta
> feature, a validar na implementacao. Nenhuma assinatura abaixo foi inferida:
> as formas de JSON vem de `cli/lib/serve.sh` e do stub de teste
> `tests/cstk/test_serve.sh:1670-1754`, que documenta a resposta real da API.

---

## 1. Origem da release

| Item | Valor | Estado |
|---|---|---|
| Constante | `_SERVE_GITHUB_API` (`cli/lib/serve.sh:66`) | `[ATUAL]` |
| Valor atual | `https://api.github.com/repos/JotJunior/cstk-panel/releases/latest` | `[ATUAL]` |
| Valor novo | `https://api.github.com/repos/${CSTK_PANEL_REPO}/releases/latest` | `[PROPOSTA]` |
| Default novo | `CSTK_PANEL_REPO="${CSTK_PANEL_REPO:-JotJunior/cstk}"` | `[PROPOSTA]` |

Paridade com `cli/install.sh:44` (`CSTK_REPO="${CSTK_REPO:-JotJunior/cstk}"`).

`CSTK_PANEL_REPO` aceita **apenas** `owner/repo`. O host permanece fixo em
`api.github.com` por construcao da string — nunca configuravel (FR-013).

## 2. Campos consumidos da resposta da API

Forma confirmada em `tests/cstk/test_serve.sh:1682-1754` (stub construido contra a
resposta real de `api.github.com`):

| Campo | Uso | Estado |
|---|---|---|
| `tag_name` | versao instalada; gravada em `.panel-version` (`serve.sh:495`) | `[ATUAL]` |
| `tarball_url` | fallback auto-tarball quando nao ha par verificavel | `[ATUAL]` |
| `prerelease` | release com `true` e recusada | `[ATUAL]` |
| `draft` | presente na resposta | `[ATUAL]` |
| `assets[].browser_download_url` | universo de candidatos da selecao | `[ATUAL]` |

O corpo/notas da release **nao** e consumido nem exibido — fato que origina
FR-022.

## 3. Predicado de selecao do asset

### 3.1 `[ATUAL]` — posicional (`cli/lib/serve.sh:390-393`)

```
primeiro asset cuja URL termina em ".tar.gz"
  E cuja URL + ".sha256" tambem exista na MESMA release
```

Pareamento por igualdade de string completa (lookup associativo do awk), nunca
substring — disciplina anti-spoofing herdada de `trusted-hosts.sh`.

### 3.2 `[PROPOSTA]` — name-bound (nome exato derivado da tag)

Revisado apos o gate `owasp-security` (ver `research.md` Decision 12). A versao
anterior deste contrato usava **prefixo** `cstk-panel-`. Prefixo nao e a
"correspondencia inequivoca" que FR-008 exige: `cstk-panel-docs-1.0.tar.gz`
casaria e venceria por ordem da API.

```
EXPECTED = "cstk-panel-" + bare(tag_name) + ".tar.gz"    # bare = tag sem "v"

selecionar o asset em que TODAS as condicoes valem:
  (a) basename(URL), apos remover ?query e #fragment, e IGUAL a EXPECTED
  (b) URL + ".sha256" existe na MESMA release (igualdade de string completa)
```

Invariantes que MUST valer:

- **I1**: a comparacao e de **igualdade**, nunca prefixo nem substring.
  (`cstk-` e prefixo proprio de `cstk-panel-`, e `cstk-panel-` e prefixo de
  `cstk-panel-docs-`; qualquer relaxamento reabre a confusao de asset.)
- **I2**: (a) aplica-se ao **basename** apos strip de query/fragment, nao a URL
  inteira. Basename contendo `%` e rejeitado, para nao casar via
  percent-encoding. (O host ja e barrado por `_serve_check_host_allowlist`;
  I2 e defesa em profundidade.)
- **I3**: sem candidato satisfazendo (a)+(b), o comportamento e o fallback ao
  auto-tarball ja existente — **nunca** selecionar outro asset. Isto e o que
  FR-008/AC2 chama de "reconhecer a ausencia do pacote do painel como tal".
- **I4**: como EXPECTED deriva de `tag_name`, o nome fica **vinculado a versao
  da release**: um asset de painel de outra versao na mesma release nao casa.
- **I5**: `tag_name` vem da **resposta da API**, nao de fonte local, e I4 o
  tornou carga util em dois lugares (EXPECTED aqui, e o nome exigido do
  diretorio de topo em §8.3). Logo `bare(tag_name)` MUST casar
  `^[0-9A-Za-z][0-9A-Za-z.+-]*$` **antes** de qualquer derivacao; valor fora
  do formato = fail-closed para o auto-tarball, com linha em stderr. Sem I5, o
  unico campo da API que vira nome de caminho seria o unico sem validacao de
  forma — enquanto `CSTK_PANEL_REPO`, que vem de env, e validado em §7.
  (Nao ha exploracao conhecida: a comparacao de (a) e por igualdade e falha
  fechado. I5 e defesa em profundidade e paridade com §7, nao correcao de
  furo.)

### 3.3 Matriz de decisao

| Assets na release | `[ATUAL]` seleciona | `[PROPOSTA]` seleciona |
|---|---|---|
| so par `cstk-panel-*` | painel | painel |
| so par `cstk-*` (toolkit) | **toolkit (errado)** | nenhum -> auto-tarball |
| ambos, toolkit primeiro | **toolkit (errado)** | painel |
| ambos, painel primeiro | painel | painel |
| `cstk-panel-<bare>.tar.gz` sem `.sha256` | nenhum -> auto-tarball | nenhum -> auto-tarball |
| `cstk-panel-docs-<bare>.tar.gz` + par, listado antes | **esse (errado)** | nenhum -> auto-tarball |
| `cstk-panel-<outra-versao>.tar.gz` + par | esse | nenhum -> auto-tarball (I4) |

Linha 3 e o cenario que esta feature cria e que FR-014 exige provar.

## 4. Estrutura exigida do pacote (FR-010)

| Exigencia | Origem | Estado |
|---|---|---|
| Um unico diretorio de topo | `tar --strip-components 1` (`serve.sh:480`) | `[ATUAL]` |
| `package.json` na raiz extraida | `serve.sh:488` | `[ATUAL]` |
| `package-lock.json` na raiz extraida | `serve-docker.sh:356` (fail-closed) | `[ATUAL]` |

Produtor `[PROPOSTA]` (`.github/workflows/release.yml` do cstk):

```
git archive --format=tar.gz --prefix="cstk-panel-${BARE}/" \
  -o "dist/cstk-panel-${BARE}.tar.gz" HEAD:panel
sha256sum "dist/cstk-panel-${BARE}.tar.gz" > "dist/cstk-panel-${BARE}.tar.gz.sha256"
```

`HEAD:panel` empacota o conteudo da subarvore; `--prefix` cria o unico
diretorio de topo consumido pelo `--strip-components 1`.

## 5. Outcomes de integridade (`enforcement-log.jsonl`)

Escritor: `_serve_write_integrity_log OUTCOME PKG_URL EXPECTED ACTUAL BYPASS`
(`cli/lib/serve.sh:247-281`). Destino `<cwd>/.claude/enforcement-log.jsonl`,
`source:"serve-integrity"`. Best-effort: falha de escrita nunca aborta o serve.

| Outcome | Quando | Estado |
|---|---|---|
| *(nenhuma linha)* | `verified` — sucesso silencioso (`serve.sh:457`) | `[ATUAL]` |
| `unverifiable-blocked` | sem fonte verificavel, sem bypass | `[ATUAL]` |
| `unverifiable-bypassed` | sem fonte verificavel, com bypass explicito | `[ATUAL]` |
| `mismatch-blocked` | checksum divergiu | `[ATUAL]` |
| `wrong-payload-blocked` | checksum conferiu **mas** a arvore extraida nao e o painel | `[PROPOSTA]` |

Linha emitida (forma exata do `printf` em `serve.sh:275`):

```json
{"source":"serve-integrity","timestamp":"<ISO8601Z>","outcome":"wrong-payload-blocked","package_url":"<url>","expected_sha256":"<sha>","actual_sha256":"<sha>","bypass_method":null}
```

Em `wrong-payload-blocked`, `expected_sha256` e `actual_sha256` sao **iguais e
nao-nulos** — e precisamente essa igualdade que documenta o ponto de FR-009: o
checksum conferiu e ainda assim o pacote estava errado.

**Retrocompatibilidade**: o enum documentado em `serve.sh:236-238` era
`unverifiable-blocked | unverifiable-bypassed | mismatch-blocked`. O consumidor
`pretooluse-bash-guard.sh` filtra por `source`, sem validar enum fechado, entao
acrescentar valor e retrocompativel. Contrato-base:
`docs/specs/_archived/2026-07-28-enforced-guards/contracts/enforcement-log.md`.

## 6. Validacao de host (FR-013)

Inalterada. Toda URL de pacote — asset ou auto-tarball — passa por
`_serve_check_host_allowlist` (`serve.sh:407`), wrapper de `trusted_host_check`
(`cli/lib/trusted-hosts.sh`).

Allowlist (`trusted-hosts.sh:47`, constante versionada, **nao** lida de env por
design documentado nas linhas 17-22):

```
github.com codeload.github.com objects.githubusercontent.com api.github.com
```

`CSTK_PANEL_REPO` altera `owner/repo`, jamais o host. Nenhuma excecao nova.


---

## 7. `[PROPOSTA]` Validacao de `CSTK_PANEL_REPO` (FR-012/FR-013 endurecidos)

Aberto pelo gate `owasp-security` (finding High). Um `owner/repo` sem validacao
interpolado numa URL e vetor real num toolkit dirigido por agente, onde a env
var pode vir de hook, `.envrc` ou CI.

MUST, antes de qualquer uso do valor:

1. **Formato**: casar
   `^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$`. Rejeita `..`,
   `@`, `%`, espaco, barra extra, vazio. Valor invalido = erro fail-closed com
   mensagem acionavel; **nunca** cair silenciosamente no default, o que
   mascararia configuracao errada.
2. **Allowlist**: a URL composta passa por `trusted_host_check` antes do
   primeiro request — nao apenas as URLs de asset. Redundante hoje (o host e
   literal na string) e defesa em profundidade contra refatoracao futura.
3. **Anuncio**: valor diferente do default emite aviso em stderr e uma linha
   no `enforcement-log.jsonl`. Origem nao-default e evento auditavel, nao
   preferencia silenciosa.

## 8. `[PROPOSTA]` Validacao pre-extracao do tarball (FR-009 endurecido)

Aberto pelo gate `owasp-security` (finding High). Checar `package.json`
**apos** `tar -x` tem dois defeitos: (i) `package.json` presente nao significa
"e o painel" — qualquer tarball npm passa; (ii) quando a checagem roda, a
arvore hostil **ja foi escrita em disco**.

MUST, apos o checksum conferir e **antes** de extrair:

1. Listar membros com `tar -tzf`.
2. Rejeitar se houver caminho absoluto (`/...`), componente `..`, entrada de
   symlink/hardlink, ou entrada de device.
3. Rejeitar se houver mais de um diretorio de topo, ou se o unico diretorio de
   topo nao for exatamente `cstk-panel-<bare>/` (mesmo `<bare>` de §3.2, ja
   validado por I5). A ordem 2 -> 3 importa: o passo 2 rejeita `..` e caminho
   absoluto **antes** de `<bare>` ser usado em comparacao de caminho.
4. Extrair com `--no-same-owner --no-same-permissions` (nao honrar setuid/
   setgid vindos do arquivo).
5. A checagem pos-extracao de `package.json` permanece como **backstop**; o
   outcome `wrong-payload-blocked` cobre ambos os pontos de deteccao.

Qualquer rejeicao em 2/3 grava `wrong-payload-blocked` **e** emite linha
distinta em stderr: o log e best-effort e escreve em `$(pwd)/.claude`, entao um
bloqueio de seguranca nunca pode depender so dele.
