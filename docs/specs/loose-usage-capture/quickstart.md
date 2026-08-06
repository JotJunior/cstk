# Quickstart: Loose Usage Capture

Cenarios que validam a implementacao end-to-end. Todos rodam localmente, sem
rede externa.

**Nota de ambiente (research.md Decision 11)**: durante uma execucao 00c
ativa, o `pretooluse-bash-guard` bloqueia comandos de rede cuja URL nao esteja
na whitelist do projeto, e a whitelist atual so contem a porta fixa `9464`.
Por isso os cenarios abaixo usam **fixture local** via `--endpoint file://...`
— caminho ja previsto pelo comentario de `_OU_DEFAULT_ENDPOINT`
(`otel-usage.sh` linhas 125-127: "ou para apontar a um arquivo em teste").
Isso tambem torna os cenarios deterministicos e reproduziveis em CI.

---

## Scenario 1: Happy path — captura avulsa com dois modelos (US1)

1. Preparar fixture `A` com linhas `claude_code_cost_usage_total{...}` e
   `claude_code_token_usage_total{...}` para DOIS modelos distintos, e uma
   fixture `B` identica porem com os contadores incrementados.
2. Provisionar o hook num projeto de teste:
   `cstk hooks install --with-loose-usage --project-path <tmp>` `[PROPOSTA]`
3. Disparar o hook com payload de `PostToolUse` (`.cwd` = projeto de teste,
   `.tool_name` preenchido) e `CSTK_OTEL_ENDPOINT=file://.../A`.
4. Avancar o relogio do throttle (tocar `meta.tsv` com `updated_at` antigo) e
   disparar o hook de novo, agora apontando para a fixture `B`.
5. `cstk usage --project <projeto de teste> --json` `[PROPOSTA]`
6. **Expected**: duas entradas em `models[]`, uma por modelo, com
   `total_tokens` e `cost_usd` iguais a `B - A` **por modelo**; nenhum campo
   `null`; exit 0.

---

## Scenario 2: Error case — endpoint indisponivel nao vira zero (FR-005 / SC-004)

1. Estado inicial: nenhum dado de captura para o projeto.
2. Disparar o hook com `CSTK_OTEL_ENDPOINT` apontando para um caminho
   inexistente.
3. **Expected**:
   - hook: exit `0`, stdout vazio, stderr vazio, nenhum diretorio de captura
     criado;
   - `cstk usage --project <p>` responde **`nao medido`** (mensagem de
     ausencia de cobertura), exit 0;
   - a saida NAO contem `0` como valor de tokens nem de custo.

---

## Scenario 3: Exclusao de janela de pipeline (US2 / SC-002)

1. No projeto de teste, criar um estado 00c com `status: em_andamento`
   (state-dir sob `.claude/feature-00c-state/<short>/`), de modo que
   `_hook-active-exec.sh` retorne `0` (ativa) para aquele `cwd`.
2. Disparar o hook com fixture `C` (contadores maiores que os do segmento
   aberto).
3. **Expected**: o segmento corrente e marcado como fechado; o valor
   registrado permanece o do ultimo tick de execucao INATIVA; nenhum
   incremento de `C` entra em `loose_usage`.
4. Promover o estado 00c para terminal (`status: concluida`), avancar o
   throttle e disparar o hook com fixture `D`.
5. **Expected** (FR-010): um segmento NOVO e aberto; capturas voltam a
   ocorrer sem reiniciar o processo; o total do projeto = segmento anterior +
   novo segmento, e o consumo do trecho de execucao ativa nao aparece em
   nenhum dos dois.

---

## Scenario 4: Sobrevivencia a encerramento abrupto (US3 / SC-003)

1. Disparar duas capturas periodicas bem-sucedidas para um processo.
2. Simular encerramento abrupto: **nao** disparar nenhum evento de fim de
   sessao; simplesmente parar de invocar o hook (o segmento fica sem marcador
   `closed`).
3. Consultar `cstk usage --project <p>`.
4. **Expected**: o consumo acumulado ate a ultima captura permanece
   disponivel e integro; o segmento aparece como aberto (`segment_open = 1`);
   nenhum dado e perdido pela ausencia do evento de encerramento.

---

## Scenario 5: Comparacao avulso vs pipeline (US1 cenario 2 / FR-009 / SC-005)

1. Popular `wave_model_usage` com ao menos uma linha para o projeto (via
   execucao 00c real ou `cstk recall --ingest` de um state-dir de teste).
2. Popular `loose_usage` pelos Scenarios 1/3.
3. `cstk usage compare --project <p>` `[PROPOSTA]`
4. **Expected**: duas categorias (`loose` e `pipeline`) lado a lado, cada uma
   com mix por modelo (`share_pct`) e `blended_cost_per_mtok`; sem
   cruzamento manual de fontes pelo operador.
5. Repetir com um projeto que tenha SO uma das categorias.
6. **Expected**: a categoria ausente aparece como `nao medido` (nao `0`), e a
   categoria presente continua sendo exibida normalmente.

---

## Scenario 6: Roundtrip End-to-End produtor↔consumidor (obrigatorio)

Adaptacao do cenario de roundtrip para a borda desta feature. Nao ha borda
backend↔frontend; a borda real e **hook (produtor de TSV) ↔ CLI (consumidor)**,
e o modo de falha analogo ao drift de case style e o **drift de formato de
snapshot** — o `delta` ja possui uma guarda que descarta snapshot "em formato
antigo" com 4 colunas em vez de 5 (`otel-usage.sh` linhas 320-331, exit 3).

1. Executar o hook de verdade (nao fixture de TSV pre-fabricado): ele deve
   produzir os arquivos chamando `otel-usage.sh snapshot`.
2. Inspecionar `otel-start.tsv` / `otel-end.tsv` produzidos e comparar o shape
   contra o contrato declarado em `data-model.md`:
   - numero de colunas por linha = 5, separadas por TAB;
   - ordem `session_id, query_source, model, type, value`;
   - presenca do cabecalho `# session_id<TAB>...`.
3. Rodar o consumidor real (`cstk usage`) sobre esses arquivos — sem mock,
   sem fixture intermediaria.
4. Verificar que nenhum label de PII (`user_email`, `user_id`,
   `user_account_uuid`, `user_account_id`, `organization_id`) aparece nos
   arquivos gerados.
5. **Expected**: zero divergencia entre o arquivo realmente escrito pelo hook,
   o formato documentado e o que o consumidor parseia; `delta` NAO retorna
   `null` por formato antigo; zero PII em disco.

---

## Scenario 7: Opt-out preservado (FR-006 / dec-008)

1. Rodar `cstk hooks install --project-path <tmp>` **sem** `--with-loose-usage`.
2. **Expected**: `.claude/hooks/` contem os tres hooks obrigatorios atuais e
   **nao** contem `posttooluse-loose-usage.sh`; o `settings.json` nao registra
   o hook de captura; nenhum diretorio sob `~/.claude/cstk/loose-usage/` e
   criado durante uma sessao subsequente.
