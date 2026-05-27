# Phase 1 — Data Model: panel-installer

Esta feature nao usa banco de dados. As "entidades" sao representacoes em filesystem
e em memoria (variaveis do helper) do estado de instalacao do painel e do release
remoto. Documentadas para ancorar contratos e testes.

---

## Entity: PainelInstalado

Representa a instalacao local do cstk-panel. Persistido no filesystem.

| Campo | Tipo | Origem / Local | Obrigatorio | Notas |
|-------|------|----------------|-------------|-------|
| `diretorio` | path absoluto | `$CSTK_PANEL_DIR` ou `~/.local/share/cstk/panel/` | sim | raiz da arvore extraida do tarball |
| `versao_tag` | string | `<diretorio>/.panel-version` (arquivo texto, 1 linha) | nao | tag GitHub do release instalado; ausente em instalacao legada/manual |
| `valido` | bool (derivado) | `[ -f "<diretorio>/package.json" ]` | sim | TRUE sse `package.json` presente e legivel na raiz (FR-002) |
| `package_json` | path | `<diretorio>/package.json` | sim (quando valido) | sinal canonico de "arvore presente" (D4) |

**Marker `.panel-version`**: arquivo texto plano de 1 linha contendo a `tag_name` do
release instalado. Escrito apos extracao bem-sucedida; lido para exibir a versao
corrente ao operador. Ausencia NAO invalida a instalacao (`valido` deriva so de
`package.json`) — apenas omite a versao no terminal.

### State transitions

```
[ausente]  --(1a invocacao: download+extract OK)-->  [valido]
[ausente]  --(download/extract falha)-->             [ausente]  (dest nao tocado)
[valido]   --(invocacao subsequente)-->              [valido]   (sem rede; reuso)
[valido]   --(--reinstall)-->                        [ausente] --(re-download)--> [valido]
[corrompido: dir existe, package.json ausente]
           --(deteccao)-->  erro + sugestao `--reinstall`  (nao sobe o painel)
[valido]   --(diretorio removido manualmente)-->     [ausente]  (tratado como 1a invocacao)
```

**Invariante de escrita atomica**: o destino (`diretorio`) so e mutado APOS extracao
bem-sucedida em tmpdir privado (`mktemp -d`) seguida de move. Falha em qualquer passo
deixa o destino INALTERADO (alinhado ao comportamento de `tarball.sh`: "mismatch/falha
nao toca dest_dir").

---

## Entity: ReleaseGitHub

Representa o release remoto consultado via GitHub API. Efemero (so existe em memoria
durante a 1a invocacao / `--reinstall`).

| Campo | Tipo | Origem | Obrigatorio | Notas |
|-------|------|--------|-------------|-------|
| `tag_name` | string | resposta JSON de `/releases/latest`, campo `tag_name` | sim | grava em `.panel-version` apos instalar |
| `tarball_url` | URL https | resposta JSON, campo `tarball_url` | sim | source tarball nativo do GitHub (host na whitelist) |
| `sha256_url` | URL https | derivada/buscada nos `assets` do release | nao | AUSENTE no release v0.1.0 (`assets: []`); quando presente, dispara verificacao (D2) |

**Fonte**: `https://api.github.com/repos/JotJunior/cstk-panel/releases/latest`.
Parse via `grep`/`sed` POSIX (sem jq no caminho serve — ver plan.md Convencoes de
Borda e research D1). `tag_name` e `tarball_url` sao campos string planos.

### Relacionamento

`PainelInstalado.versao_tag` ⟵ `ReleaseGitHub.tag_name` (na instalacao).
Apos instalar, `ReleaseGitHub` e descartado; reinvocacoes subsequentes NAO o
reconstroem (FR-002 — sem rede quando `PainelInstalado.valido`).

---

## Variaveis de configuracao (entrada do operador / ambiente)

| Variavel | Tipo | Default | Validacao | FR |
|----------|------|---------|-----------|-----|
| `--port` | inteiro TCP | **5173** | 1..65535, senao exit 2 | FR-004 (reconciliado) |
| `--host` | string | `127.0.0.1` | aceita; aviso se != 127.0.0.1 | FR-004 |
| `--reinstall` | flag bool | false | — | FR-005 |
| `CSTK_PANEL_DIR` | path | `~/.local/share/cstk/panel/` | — | FR-007 |
| `PORT` (saida → painel) | inteiro | = `--port` resolvido | exportada antes de `npm run start` | FR-003 |
