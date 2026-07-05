# Quickstart / Cenarios de Teste: panel-installer

Cenarios criticos do `cstk serve`, em formato passo → **Expected**. Os testes em
`tests/cstk/test_serve.sh` exercitam estes fluxos sem rede real (mocks via
`CSTK_PANEL_DIR` + stubs de `curl`/`npm` no PATH).

---

## Cenario 1 — Primeira invocacao: baixa e roda (P1, FR-001/FR-003)

1. Garantir que `~/.local/share/cstk/panel/` (ou `$CSTK_PANEL_DIR`) NAO existe.
2. Rodar `cstk serve`.
3. Sistema consulta `api.github.com/.../releases/latest`, baixa o tarball, extrai,
   roda `npm install`, grava `.panel-version`.
4. Sistema exporta `PORT=5173` e executa `npm run start`.

**Expected**:
- terminal mostra "baixando release mais recente...", a tag baixada, aviso de
  integridade indisponivel, e por fim "iniciando painel em http://127.0.0.1:5173".
- `<panel-dir>/package.json` presente; `<panel-dir>/.panel-version` contem a `tag_name`.
- processo permanece em foreground; exit 0 ao Ctrl+C.

---

## Cenario 2 — Invocacao subsequente: reusa sem rede (P2, FR-002)

1. Com `<panel-dir>/package.json` ja presente (de uma instalacao previa).
2. Rodar `cstk serve`.

**Expected**:
- ZERO requisicoes a `api.github.com`/`objects.githubusercontent.com` (no teste, o stub
  de `curl` falha o cenario se for invocado).
- terminal mostra "usando painel ja instalado (<tag>)" e "iniciando painel em
  http://127.0.0.1:5173".
- tempo ate acessivel visivelmente menor (sem download).

---

## Cenario 3 — Runtime ausente (P1 edge, FR-006)

1. Remover `npm` do PATH (no teste: PATH apontando para dir sem `npm`).
2. Rodar `cstk serve`.

**Expected**:
- stderr: "cstk serve: npm nao encontrado no PATH. Instale o Node.js (https://nodejs.org)."
- exit 1. NENHUM download iniciado (falha cedo, antes de tocar a rede).
- Analogo para `curl` ausente (mensagem especifica de `curl`).

---

## Cenario 4 — Download falha / integridade invalida (P1 edge, FR-008)

### 4a — Rede indisponivel
1. Forcar `http_download` a falhar (no teste: stub de `curl` retornando erro de rede).
2. Rodar `cstk serve` (sem instalacao previa).

**Expected**: mensagem de erro de rede (de `http.sh`) + "cstk serve: falha ao baixar o
release." + exit 1. Destino `<panel-dir>` NAO criado/alterado.

### 4b — Integridade invalida (quando `.sha256` presente em release futuro)
1. Servir um tarball cujo checksum nao bate com o `.sha256` (no teste: fixture).
2. Rodar `cstk serve`.

**Expected**: "cstk serve: checksum MISMATCH do release; abortando sem instalar." +
exit 1. Destino inalterado.

### 4c — Sem `.sha256` (caso atual, v0.1.0)
1. Release sem asset `.sha256`.
2. Rodar `cstk serve`.

**Expected**: AVISO "verificacao de integridade indisponivel (release sem asset
.sha256)" e a instalacao PROSSEGUE (FR-008). exit 0 ao subir.

---

## Cenario 5 — Porta e host customizados (P3, FR-004)

1. Rodar `cstk serve --port 8080`.

**Expected**: `PORT=8080` exportado; terminal confirma "http://127.0.0.1:8080".

2. Rodar `cstk serve --host 0.0.0.0`.

**Expected**: AVISO de que `--host` e ignorado (backend fixo em 127.0.0.1); painel sobe
em 127.0.0.1 mesmo assim. exit 0.

3. Rodar `cstk serve --port 70000`.

**Expected**: stderr "porta invalida '70000': deve ser inteiro entre 1 e 65535." +
exit 2.

4. Rodar `cstk serve --port 8080 --host 0.0.0.0` (combinacao).

**Expected**: porta 8080 aplicada + aviso de host; exit 0.

---

## Cenario 6 — Reinstalacao forcada (P4, FR-005)

1. Com instalacao existente em `<panel-dir>`.
2. Rodar `cstk serve --reinstall`.

**Expected**: `<panel-dir>` removido, release mais recente re-baixado e re-instalado,
`.panel-version` atualizado, painel sobe normalmente. exit 0.

---

## Cenario 7 — Instalacao corrompida (P2 edge)

1. `<panel-dir>` existe mas SEM `package.json` (extracao parcial / arquivos faltando).
2. Rodar `cstk serve` (sem `--reinstall`).

**Expected**: stderr "instalacao em <dir> parece corrompida (package.json ausente).
Rode: cstk serve --reinstall" + exit 1. Painel NAO sobe.

---

## Cenario 8 — Roundtrip End-to-End (borda CLI ↔ Node)

> Borda single-escalar (env var `PORT`), nao ha payload estruturado. O roundtrip
> verifica que a porta resolvida na CLI chega ao painel.

1. Rodar `cstk serve --port 5199` com painel ja instalado (ambiente real, manual).
2. Apos "iniciando painel em http://127.0.0.1:5199", em outro terminal:
   `curl -fsS http://127.0.0.1:5199/` (ou endpoint de health do painel).

**Expected**: o backend responde na porta 5199 (a env var `PORT` exportada pelo
`cstk serve` foi honrada pelo `process.env['PORT']` do painel, NAO o fallback 3001).
Confirma a unica convencao que cruza a borda: `--port` (CLI) → `PORT` (env) → bind do
backend. Cenario manual (nao no test harness automatizado, que mocka o `npm`).
