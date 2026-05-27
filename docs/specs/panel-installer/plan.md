# Implementation Plan: panel-installer

**Feature**: `panel-installer` | **Date**: 2026-05-26 | **Spec**: [spec.md](./spec.md)

## Summary

Adicionar o subcomando `cstk serve [--port 5173] [--host 127.0.0.1] [--reinstall]`
que instala o painel de visualizacao (`cstk-panel`) sob demanda na primeira
invocacao e o reutiliza nas seguintes. A abordagem tecnica: um novo helper POSIX
`cli/lib/serve.sh` (funcao `serve_main`, despachada por `cli/cstk` no padrao ja
existente `. lib && <cmd>_main`), que (1) faz lazy-install do release mais recente
de `JotJunior/cstk-panel` via GitHub API + tarball nativo, (2) detecta primeira
execucao pela ausencia/invalidade de `~/.local/share/cstk/panel/` (override
`CSTK_PANEL_DIR`), (3) valida pre-requisitos de runtime (`curl`, `npm`) com
degradacao graceful (exit 1 + mensagem acionavel), (4) sobe o painel via
`npm run start` em foreground exportando `PORT=<porta resolvida>`, propagando
SIGINT/SIGTERM ao filho. O `--port` default e **5173** (intencao explicita do
usuario); o `cstk serve` SEMPRE exporta `PORT`, tornando o fallback interno `3001`
do painel irrelevante neste caminho.

## Technical Context

**Language/Version**: POSIX sh (`#!/bin/sh`, `set -eu`) para o helper `cli/lib/serve.sh`.
O painel servido roda em Node.js (runtime EXTERNO baixado sob demanda, nao do cstk).
**Primary Dependencies**: ferramentas POSIX canonicas (`mkdir`, `rm`, `mv`, `tar`,
`awk`, `printf`, `command`) + helpers internos reutilizados (`cli/lib/http.sh`:
`http_download`, `http_check_url`; `cli/lib/compat.sh`: `sha256_file`). Deps OPCIONAIS
nao-POSIX confinadas em `serve.sh`: `curl` (download), `npm`/`node` (runtime do painel).
**Storage**: filesystem local — instalacao em `~/.local/share/cstk/panel/`
(`$CSTK_PANEL_DIR` override), marker de versao em `<panel-dir>/.panel-version`.
**Testing**: `tests/cstk/test_serve.sh` (harness `tests/run.sh`), sem rede real —
mocks via env vars (`CSTK_PANEL_DIR`, stub de `curl`/`npm` no PATH, ou hook de
injecao de fixture).
**Target Platform**: terminal POSIX (macOS/Linux). Painel acessivel via browser local.
**Project Type**: CLI tool (extensao do binario `cstk` existente).
**Performance Goals**: painel acessivel em <60s na 1a execucao (excl. download de rede),
<10s nas subsequentes (sem rede) — SC da spec.
**Constraints**: zero coleta remota alem de GitHub API + CDN de release (Principio IV);
backend do painel fixo em `127.0.0.1` (limitacao herdada do cstk-panel).
**Scale/Scope**: uso single-operator, manual, foreground; sem daemon, sem PID file,
sem lock de instancia (FR-013-INFRA-PROC / FR-014-INFRA-LOCK).

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checar apos Phase 1.*

### Pre-Phase 0

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (NON-NEGOTIABLE) | PASS | Feature segue pipeline specify→clarify→plan→checklist→tasks; spec.md + clarifications + estes artefatos rastreiam intencao. |
| II. POSIX sh puro, zero dep externa (NON-NEGOTIABLE) | PASS (via carve-out 1.1.0) | `serve.sh` e `#!/bin/sh`+`set -eu`, sem Bash-isms. `curl`/`npm`/`node` sao deps OPCIONAIS sob o carve-out do amendment 1.1.0 — ver analise (a)(b)(c) abaixo. |
| III. Formato canonico de skill | N/A | Feature nao cria/edita skill; e subcomando do binario `cstk`. |
| IV. Zero coleta remota (NON-NEGOTIABLE) | PASS | Unico trafego externo: GitHub API (`api.github.com`) + CDN de release (`objects.githubusercontent.com`) para DOWNLOAD; nenhum dado do ambiente local transmitido (FR-012). Whitelist ja no state. |
| V. Profundidade sobre adocao | PASS | Reusa helpers existentes (`http.sh`), nao reinventa download; degradacao graceful coberta por teste. |

### Analise do carve-out do Principio II (amendment 1.1.0) para `curl`/`npm`/`node`

O Principio II proibe dep externa, MAS o amendment 1.1.0 abre carve-out disciplinado
quando as TRES condicoes sao CUMULATIVAS. Verificacao:

- **(a) Uso opcional com fallback graceful documentado E verificavel por teste.**
  `serve.sh` verifica `command -v curl` e `command -v npm` ANTES de usar (FR-006).
  Ausentes ⇒ mensagem de erro acionavel ("instale Node.js"/"instale curl") + exit 1,
  SEM crash. Nenhum outro subcomando do `cstk` depende de `npm`/`node` — o core do
  toolkit continua funcionando sem eles. `tests/cstk/test_serve.sh` cobre o caminho
  "npm ausente" e "curl ausente" stubando o PATH (cenario verificavel).
- **(b) Codigo que referencia a dep confinado em UM arquivo identificavel.**
  `grep -rn 'npm\|node\|npm run start'` deve casar SOMENTE em `cli/lib/serve.sh`
  (alem de docs/tests). `curl` ja e confinado em `cli/lib/http.sh` (reuso, nao nova
  superficie) — `serve.sh` chama `http_download`/`http_check_url`, nunca `curl`
  diretamente.
- **(c) Dep declarada na documentacao da feature.** Declarada em `spec.md` FR-006/
  FR-011 e neste `plan.md`, com caminho confinado (b) e fallback (a).

**Conclusao**: as tres condicoes sao satisfeitas; `curl`/`npm`/`node` entram como
deps OPCIONAIS sob o carve-out. `npm`/`node` sao runtime do PAINEL (artefato externo
baixado sob demanda), nao do `cstk` em si — o subcomando `serve` e inerentemente
opt-in (operador escolhe rodar o painel). Bash-isms permanecem proibidos
(`serve.sh` e POSIX puro). Ver `## Complexity Tracking` — sem violacao residual a
justificar; o carve-out e mecanismo de conformidade, nao excecao ad-hoc.

## Project Structure

### Documentation (this feature)

```
docs/specs/panel-installer/
├── spec.md          # reconciliado (default --port = 5173)
├── plan.md          # This file
├── research.md      # Phase 0 output
├── data-model.md    # Phase 1 output
├── quickstart.md    # Phase 1 output
└── contracts/
    ├── cli-serve.md     # contrato CLI do `cstk serve`
    └── serve-sh.md      # contrato do helper serve.sh (serve_main)
```

### Source Code (repository root)

```
cli/
├── cstk                 # dispatch: adicionar `serve` ao case (-> serve_main)
└── lib/
    ├── serve.sh         # NOVO — helper POSIX, define serve_main
    ├── http.sh          # REUSO — http_download / http_check_url (curl)
    ├── compat.sh        # REUSO — sha256_file (integridade best-effort)
    └── tarball.sh       # REFERENCIA — download_and_verify exige .sha256;
                         #   NAO reutilizavel direto (cstk-panel sem asset .sha256)
tests/cstk/
└── test_serve.sh        # NOVO — cobre 1a exec, reuso, flags invalidas, prereq ausente
```

**Structure Decision**: o subcomando segue a convencao de dispatch ja firmada em
`cli/cstk` (`case "$_cmd" in ... serve) ... . "$CSTK_LIB/serve.sh"; serve_main "$@"`).
Isso isola 100% a logica do painel em `cli/lib/serve.sh` (SC: "serve nao interfere em
nenhum outro subcomando"). O download reusa `cli/lib/http.sh` (ja POSIX, ja com error
mapping de curl), evitando nova superficie de dep. `cli/lib/tarball.sh` NAO e reusado
porque seu `download_and_verify` EXIGE um `sha256_url` e aborta na ausencia — o release
do cstk-panel nao publica `.sha256` (assets vazios), entao `serve.sh` implementa um
fluxo de download proprio (best-effort de integridade — ver research.md D2).

## Convencoes de Borda

| Camada | Case style | Validacao | Fonte da verdade |
|--------|------------|-----------|------------------|
| Flags CLI (`cstk serve`) | kebab-case (`--port`, `--host`, `--reinstall`) | parser POSIX em `serve.sh` | `contracts/cli-serve.md` |
| Variavel de ambiente para o painel | UPPER_SNAKE (`PORT`) | export antes de `npm run start` | `contracts/serve-sh.md` |
| Variavel de override de path | UPPER_SNAKE (`CSTK_PANEL_DIR`) | leitura com default | FR-007 |
| Marker de versao instalada | dotfile (`.panel-version`) | leitura/escrita texto plano | `data-model.md` (PainelInstalado) |
| Resposta GitHub API (`/releases/latest`) | JSON camelCase/snake (`tag_name`, `tarball_url`) | parse via `grep`/`sed` POSIX (sem jq no caminho serve) | `data-model.md` (ReleaseGitHub) |

**Borda relevante**: CLI shell ↔ processo Node. A unica convencao que atravessa a
fronteira e a porta: o operador passa `--port N` (kebab) ⇒ `serve.sh` exporta
`PORT=N` (env var) ⇒ o painel le `process.env['PORT']`. A fonte da verdade do valor
e a flag CLI; o painel apenas consome. NAO ha mapper layer, NAO ha DTO snake/camel
porque nao ha payload estruturado cruzando — apenas uma env var escalar.

**Parsing da resposta GitHub sem jq**: o caminho do `cstk serve` evita `jq` (que e
dep opcional de OUTRAS partes do toolkit, nao deste subcomando). `tag_name` e
`tarball_url` sao extraidos com `grep`/`sed` POSIX da resposta JSON da API. Ver
research.md D1 para o trade-off (robustez vs zero-dep adicional).

## Security Review (gate owasp-security — onda-003)

Revisao de DESIGN (nao de codigo) contra OWASP Top 10:2025 + Agentic 2026. Findings
com severidade + recomendacao. Nenhum critical/high ⇒ sem BloqueioHumano obrigatorio;
findings sao Decisoes informativas no state.json (etapa plan).

| ID | Vetor | Severidade | Status |
|----|-------|------------|--------|
| S1 | Supply-chain integrity gap (ASI04 / A08) — download sem SHA256 | MEDIUM | aceito (design, FR-008) + follow-up |
| S2 | SSRF via `tarball_url` + `curl -L` redirect | LOW | mitigar no impl (host-allowlist check) |
| S3 | Execucao de codigo de terceiros (ASI05 / A03) — `npm install`/`run start` | MEDIUM | aceito (opt-in) + documentar trust boundary |
| S4 | Parsing JSON fragil com grep/sed | LOW | nao e injection; quote sempre |
| S5 | Command injection no helper POSIX | LOW | preventivel: validar porta, quoting, sem eval |

### S1 — Supply-chain integrity gap (ASI04 / A08) — MEDIUM

Download do release sem verificacao de SHA256 (upstream nao publica `.sha256`,
`assets: []`). **Mitigacoes presentes**: HTTPS-only via `curl -fsSL` (cert validation),
hosts confinados a whitelist (`api.github.com`/`objects.githubusercontent.com`),
`tarball_url` vindo da resposta AUTENTICADA da API (nao input do usuario), extracao em
`mktemp -d` + move atomico (destino intacto em falha). **Risco residual**: um release
comprometido upstream OU MITM-com-cert-valido nao seria detectado. **Por que NAO
critical/high**: feature opt-in, proveniencia confinada a 1 repo via API oficial,
TLS valida cadeia, FR-008 auto-eleva para verificacao se `.sha256` surgir. **Follow-up
recomendado**: rastrear upstream publicar `.sha256` (issue no cstk-panel); a `tag_name`
gravada em `.panel-version` ja permite ao operador auditar o que foi instalado.

### S2 — SSRF via tarball_url — LOW

`curl -L` segue redirects (o tarball do GitHub redireciona para codeload/
objects.githubusercontent.com). Se a resposta da API fosse adulterada, o redirect
poderia ir a host arbitrario. **Recomendacao (defense-in-depth, barata)**: `serve.sh`
DEVE validar que o host de `tarball_url` casa com `github.com`/`codeload.github.com`/
`objects.githubusercontent.com` via `case` glob ANTES de baixar. Rejeitar host fora da
allowlist com exit 1. (Adicionar como requisito de implementacao em tasks.)

### S3 — Execucao de codigo de terceiros (ASI05 / A03) — MEDIUM

`npm install` executa lifecycle scripts (postinstall etc.) e `npm run start` roda Node
arbitrario do upstream. **Inerente** a "baixar e rodar um painel"; aceito como opt-in
explicito do usuario. **Recomendacao**: documentar o trust boundary no contrato
(feito em serve-sh.md / research D2 nota de seguranca); preferir `npm ci` a
`npm install` SE o release trouxer lockfile (install deterministico, reproduzivel).
`--ignore-scripts` NAO e viavel (painel precisa de build). A confianca ancora em
proveniencia confinada (so `JotJunior/cstk-panel`).

### S4 — Parsing JSON fragil (grep/sed) — LOW

Extrair `tag_name`/`tarball_url` com grep/sed e fragil (risco FUNCIONAL, nao de
seguranca per se — os valores viram URLs passadas via `--` a curl, que neutraliza
option-injection). **Recomendacao**: sempre quotar valores extraidos; o host-allowlist
check de S2 serve tambem de sanity gate. Considerar `jq` opcional como refino futuro
(fallback grep/sed permanece).

### S5 — Command injection no helper POSIX — LOW

`--port`/`--host`/paths sao controlados pelo operador. **Recomendacao (requisitos de
impl)**: (a) `--port` validado como inteiro 1-65535 antes de exportar `PORT` (ja no
plano); (b) ZERO `eval`; (c) toda variavel de path/URL entre aspas duplas; (d)
`npm run start` invocado com args fixos, sem interpolar input do usuario no comando.
`set -eu` + quoting consistente fecham a superficie.

### Conformidade com Principios IV e II

- **Principio IV (zero coleta remota)**: PASS — trafego externo limitado a download do
  release; nenhum dado do ambiente local transmitido (FR-012). Confirmado no design.
- **Principio II (POSIX)**: PASS via carve-out (ver Constitution Check). `curl -L`
  redirect e seguro com S2 mitigation.

## Complexity Tracking

> Sem violacao residual de constitution. `curl`/`npm`/`node` sao deps OPCIONAIS
> conformes ao carve-out 1.1.0 (condicoes (a)(b)(c) satisfeitas — ver Constitution
> Check). Nenhuma justificativa de complexidade adicional necessaria.

| Violacao | Por Que Necessario | Alternativa Simples Rejeitada Porque |
|----------|--------------------|--------------------------------------|
| (nenhuma) | — | — |
