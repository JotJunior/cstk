# Contract: helper `cli/lib/serve.sh`

Helper POSIX sh que implementa o subcomando `cstk serve`. Despachado por `cli/cstk`
no padrao `. "$CSTK_LIB/serve.sh"; serve_main "$@"`.

## Requisitos de conformidade (Principio II)

- Shebang nao aplicavel (sourced); arquivo POSIX sh puro, sem Bash-isms.
- `set -eu` herdado do contexto do `cstk` (ou re-afirmado no topo do source guard).
- Mensagens de erro em stderr; UX/dados em stdout; exit codes 0/1/2.
- Deps OPCIONAIS confinadas a este arquivo: `npm`, `node` (runtime do painel).
  `curl` e usado SOMENTE via `http.sh` (reuso, nao referencia direta aqui).

## Funcao publica

### `serve_main "$@"`

Ponto de entrada. Convencao de dispatch: `cli/cstk` chama `serve_main` apos sourcear
o arquivo (nome derivado de `serve` → `serve_main`).

**Argumentos**: as flags do contrato CLI (`--port`, `--host`, `--reinstall`, `--help`).

**Retorno (exit)**: 0 sucesso, 1 erro geral, 2 uso incorreto (ver cli-serve.md).

**Sequencia logica**:
1. Parse de flags (POSIX `while`/`case`/`shift`). Valida `--port` (1-65535 ⇒ senao
   exit 2). Resolve `--host` (aviso se != 127.0.0.1).
2. Pre-req check: `command -v curl` e `command -v npm` (ausente ⇒ mensagem + exit 1).
3. Resolve `panel_dir` = `${CSTK_PANEL_DIR:-$HOME/.local/share/cstk/panel}`.
4. Se `--reinstall`: `rm -rf -- "$panel_dir"`.
5. Deteccao: `[ -f "$panel_dir/package.json" ]`?
   - NAO ⇒ instalar (passos 6-9).
   - SIM ⇒ pular para 10 (reuso, sem rede).
6. Consulta GitHub API `/repos/JotJunior/cstk-panel/releases/latest`; extrai
   `tag_name` + `tarball_url` (grep/sed). Falha ⇒ mensagem + exit 1.
7. Download via `http_download "$tarball_url" "$tmp/archive.tar.gz"` (tmpdir privado).
8. Integridade best-effort: se asset `.sha256` presente, baixar+verificar via
   `sha256_file`; mismatch ⇒ exit 1; ausente ⇒ AVISO e prossegue (FR-008).
9. Extrai em tmpdir (`tar -xzf ... --strip-components 1`), `npm install`, move atomico
   para `panel_dir`, grava `.panel-version` com `tag_name`. Falha em qualquer passo ⇒
   destino inalterado + exit 1.
10. Resolve `PORT=<porta>`; `export PORT`; `cd "$panel_dir"`; instala `trap` para
    SIGINT/SIGTERM (kill no filho + mensagem); executa `npm run start` em foreground.

## Helpers internos reutilizados (sourced via `$CSTK_LIB`)

| Helper | Origem | Uso |
|--------|--------|-----|
| `http_download <url> <dest>` | `cli/lib/http.sh` | baixar tarball e (se houver) `.sha256` |
| `http_check_url <url>` | `cli/lib/http.sh` | (opcional) HEAD na API antes de baixar |
| `sha256_file <path>` | `cli/lib/compat.sh` | calcular checksum local (integridade best-effort) |

> `cli/lib/tarball.sh::download_and_verify` NAO e reutilizavel: exige `sha256_url` e
> aborta na ausencia; o cstk-panel nao publica `.sha256`. `serve.sh` implementa fluxo
> de download proprio (best-effort), reusando apenas `http_download`/`sha256_file`.

## Variaveis de ambiente

| Variavel | Direcao | Default | Notas |
|----------|---------|---------|-------|
| `CSTK_PANEL_DIR` | entrada | `~/.local/share/cstk/panel` | override do dir de instalacao (testes) |
| `CSTK_LIB` | entrada | (resolvido por `cstk`) | dir das libs para sourcear `http.sh`/`compat.sh` |
| `PORT` | saida (export) | = `--port` (5173) | entregue ao `npm run start`; SEMPRE exportada |

## Testabilidade (sem rede real)

`tests/cstk/test_serve.sh` cobre:
- parse de flags + validacao de porta (exit 2 em porta invalida);
- prereq ausente: stub de PATH sem `curl` / sem `npm` ⇒ exit 1 + mensagem;
- primeira invocacao: `CSTK_PANEL_DIR` em tmpdir + stub de `curl` (serve tarball-fixture
  local) + stub de `npm` (no-op) ⇒ `panel_dir` populado + `.panel-version` gravado;
- invocacao subsequente: `panel_dir` ja com `package.json` ⇒ NENHUMA chamada de rede
  (stub de `curl` que falha o teste se invocado);
- corrompido: `panel_dir` existe sem `package.json` ⇒ exit 1 + sugestao `--reinstall`.
