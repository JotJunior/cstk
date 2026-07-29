# Quickstart: panel-docker

Cenarios que validam o modo Docker end-to-end. Happy path + error cases + o roundtrip
empirico de paridade de dados (que exercita o RISCO #1 do `research.md`).

## Scenario 1: Subir o painel sem npm no host (US1 / happy path)

1. Host com runtime de container disponivel, **sem `npm`/`node`** no PATH.
2. Rodar `cstk serve --docker` (opcionalmente `--port <P>`).
3. Abrir `http://127.0.0.1:<P|5173>` no navegador.
4. **Expected**: painel acessivel; o sistema NUNCA tentou localizar/exigir `npm` no
   host (SC-001); `npm install`/`npm run build` ocorreram dentro da imagem.

## Scenario 2: Runtime de container ausente (US1.3 / fail-closed — FR-003)

1. Host **sem** runtime de container instalado.
2. Rodar `cstk serve --docker`.
3. **Expected**: recusa imediata com mensagem acionavel "docker nao instalado", exit 1,
   **sem nenhuma chamada de rede antes** da checagem; diagnostico em <5s (SC-006). Sem
   fallback silencioso ao modo nativo.

## Scenario 3: Runtime instalado mas daemon parado (FR-004)

1. Runtime instalado, daemon parado/sem permissao de acesso.
2. Rodar `cstk serve --docker`.
3. **Expected**: mensagem acionavel DISTINTA da do Scenario 2 ("daemon parado/
   inacessivel"), exit 1, sem rede previa.

## Scenario 4: Paridade de dados — Roundtrip End-to-End (US2 / RISCO #1 — obrigatorio)

Valida que o painel containerizado le o knowledge.db real (WAL, montado `:ro`) com
paridade face ao nativo. NAO usar mock/fixture — comparar dado REAL.

1. Ter um `~/.claude/cstk/knowledge.db` populado por execucoes anteriores
   (`journal_mode=wal`, com sidecars `-shm`/`-wal`).
2. Subir o painel em modo Docker (mount `:ro` do dir de dados do cstk;
   `CSTK_KNOWLEDGE_DB` apontando ao arquivo montado).
3. Coletar contadores/listas/detalhes via a API/telas do painel containerizado.
4. Comparar com o que o **modo nativo** produz para o MESMO indice.
5. **Expected**: dados **identicos** (SC-002), zero divergencia. Em particular, a
   conexao readonly better-sqlite3 (sem `immutable=1`) abre o WAL db sobre mount `:ro`
   **sem erro** (`SQLITE_CANTOPEN`/torn read) e enxerga dados recentes.
6. **Se falhar** (RISCO #1, research.md Decision 3): NAO mascarar — registrar como
   bloqueio/nota e escalar a estrategia de mount/`immutable=1` antes de fechar FR-008.

## Scenario 5: Indice ainda inexistente (US2.2 — sem dados, nao falha)

1. Instalacao nova: `~/.claude/cstk/knowledge.db` ausente.
2. Subir em modo Docker.
3. **Expected**: painel inicia normalmente e mostra o mesmo estado "sem dados" do modo
   nativo — nunca falha de inicializacao.

## Scenario 6: Encerramento gracioso com Ctrl+C (US3.4 — FR-011)

1. Painel rodando em modo Docker.
2. Ctrl+C no terminal do `cstk serve --docker`.
3. **Expected**: `docker stop` com grace (~5s, espelhando `_serve_shutdown`), container
   encerra e (com `--rm`) e removido; **nenhum** container/processo orfao (SC-003).

## Scenario 7: Reexecucao com container remanescente (US4.1 — FR-012-INFRA-IDEMP)

1. Simular queda anterior deixando um container remanescente (parado ou rodando) de
   nome deterministico (ex.: `kill -9` do cstk; container nao removido).
2. Rodar `cstk serve --docker` de novo.
3. **Expected**: reconciliacao automatica (remove/substitui o remanescente pelo nome) e
   painel sobe normalmente, **sem** limpeza manual (SC-005) e **sem** erro cru do
   runtime (US4.2 exige mensagem cstk se a reconciliacao for impossivel).

## Scenario 8: Porta customizada (US3.1 — FR-005/FR-010)

1. Rodar `cstk serve --docker --port 8080`.
2. **Expected**: painel acessivel em `http://127.0.0.1:8080`, equivalente ao nativo; o
   encaminhador in-container garante alcancabilidade apesar do bind interno em 127.0.0.1.

## Scenario 9: `--update` / `--reinstall` no modo Docker (US3.2/3.3 — FR-010)

1. `cstk serve --docker --update`: **Expected**: consulta release; se ha versao nova,
   re-baixa+verifica e **reconstroi a imagem**; senao reusa; falha de rede mantem a
   imagem instalada e ainda sobe o painel (best-effort).
2. `cstk serve --docker --reinstall`: **Expected**: remove a imagem cacheada e
   reconstroi do zero, incondicional.

## Scenario 10: Integridade nao confirmada com `--docker` (FR-007)

1. `.sha256` do pacote do painel ausente, `cstk serve --docker` sem bypass.
2. **Expected**: bloqueio fail-closed identico ao nativo (mesmo texto/log
   `serve-integrity`); com `--allow-unverified`/`CSTK_SERVE_ALLOW_UNVERIFIED=1`,
   prossegue com aviso de alta visibilidade. Checksum **divergente** bloqueia sempre,
   sem bypass.

## Scenario 11: Atualizacao ao vivo do indice (US2 Acceptance Scenario 3 — CHK017)

Valida que uma escrita concorrente do host no `knowledge.db` fica visivel no painel
containerizado SEM reiniciar o container — RESOLVIDO empiricamente na FASE 5 (dec-061).

1. Painel Docker `running` (mount `:ro` do dir de dados do cstk, Scenario 4).
2. Anotar a contagem atual (`GET /api/v1/health` -> `data.counts.executions`, ou via
   `sqlite3 ~/.claude/cstk/knowledge.db "SELECT count(*) FROM executions;"` no host).
3. Gerar uma nova escrita no `knowledge.db` do HOST **sem tocar no container** — nem
   `docker restart`, nem `docker exec`: qualquer escrita nativa server, ex.
   `cstk recall --ingest --state-dir <state-dir-de-uma-execucao>` (uma nova onda de
   orquestrador real) ou um `INSERT` direto via `sqlite3` (mais controlavel para
   reproduzir o teste).
4. Repetir `GET /api/v1/health` no painel containerizado (mesma sessao, container
   nunca reiniciado).
5. **Expected**: a contagem refletiu a escrita na PROXIMA requisicao, sem restart —
   **CONFIRMADO**: `executions` foi de 54 para 55 imediatamente apos o INSERT do host
   (container ja `running`), e voltou a 54 apos o DELETE de limpeza, tambem sem
   restart. Mecanismo: `apps/server/src/db/open.ts::openDb()` abre (e fecha) uma
   conexao SQLite readonly nova A CADA requisicao HTTP — nunca uma conexao
   cacheada/long-lived aberta no boot do container — logo cada leitura observa o
   estado WAL committed no momento em que ela acontece. **Implicacao para o usuario**:
   nao ha necessidade de reiniciar `cstk serve --docker` apos uma nova execucao dos
   orquestradores gravar no indice; o painel reflete o dado mais recente na proxima
   navegacao/refresh de tela.
6. Regressao automatizada equivalente (dado sintetico, deterministica):
   `tests/docker/run-panel-docker-smoke.sh::scenario_concurrent_write_visible_without_restart`.
