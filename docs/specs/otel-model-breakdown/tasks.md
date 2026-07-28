# Tarefas otel-model-breakdown - Migracao aditiva v11->v12 da knowledge.db

Escopo: fechar os 6 `[Gap]` + 2 decisoes `{humano}` resolvidas do checklist
`schema-migration.md`, e implementar a migracao aditiva v11->v12 em
`cli/lib/recall.sh`: tabela nova `wave_model_usage` (custo/tokens por modelo,
por onda) + 8 colunas aditivas em `waves` (breakdown de tokens por fonte
main/subagent), com backfill via `--reindex` e disciplina de edicao das 12
assercoes de versao em `tests/cstk/test_recall.sh`.

**Legenda de status:**
- `[ ]` Pendente
- `[~]` Em andamento
- `[x]` Concluido
- `[!]` Bloqueado

**Legenda de criticidade:**
- `[C]` Critico - Impacto financeiro direto ou bloqueante
- `[A]` Alto - Funcionalidade essencial
- `[M]` Medio - Necessario mas sem urgencia imediata

---

## FASE 1 - Fundacao e Requisitos (fechar gaps do checklist)

### 1.1 Rastreabilidade formal de compatibilidade cross-repo com o cstk-panel `[C]`

Ref: `checklists/schema-migration.md` CHK001, CHK002, CHK003, CHK004 (dec-029);
`plan.md` §Riscos e Dependencias de Release / R1

- [x] 1.1.1 Adicionar `FR-010` a `spec.md` declarando, em linguagem MUST, o
      requisito de compatibilidade cross-repo: o bump de schema NAO MUST
      quebrar silenciosamente o painel instalado sem que exista rastreabilidade
      formal do bump necessario em `cstk-panel` (fecha CHK001)
      <!-- feito: spec.md FR-010 -->
- [x] 1.1.2 Adicionar `SC-005` a `spec.md` com criterio mensuravel para o
      estado do painel ANTES do fix definitivo: com
      `CSTK_SCHEMA_VERSIONS=2,3,4,5,6,7,8,9,10,11,12` setado, `cstk serve`
      continua servindo todas as rotas sem `schema-mismatch` (fecha CHK002)
      <!-- feito: spec.md SC-005 -->
- [x] 1.1.3 Registrar sugestao via `suggestions.sh register` (severidade
      `aviso`) no repo `cstk` referenciando a necessidade de bump de
      `DEFAULT_SCHEMA_VERSIONS` em `cstk-panel/apps/server/src/config.ts:31`
      (hoje `['2'..'11']`); avaliar com o mantenedor se justifica tambem
      `issue.sh create` no repo `JotJunior/cstk` para rastreio formal (fecha
      CHK003) — NUNCA abrir issue no repo `cstk-panel` diretamente (fora do
      blast radius desta execucao, FR-035)
      <!-- feito: sug-004 registrada (severidade aviso); issue.sh create nao
      aberta nesta onda — avaliacao com o mantenedor fica junto de 1.1.4 -->
- [!] 1.1.4 Task explicita de coordenacao (dec-029 / CHK004, resolvido pelo
      mantenedor em 2026-07-28): agendar/confirmar com o mantenedor o bump de
      `DEFAULT_SCHEMA_VERSIONS += '12'` no repo `cstk-panel`, ANTES OU JUNTO
      do merge desta feature — trabalho manual fora do blast radius de escrita
      desta execucao (repo externo); NAO fechar esta subtarefa so com o
      paliativo `CSTK_SCHEMA_VERSIONS`
      <!-- bloqueado: decisao de coordenar ja resolvida (CHK004); rastreabilidade
      formal registrada via sug-004. Acao fisica (bump no repo cstk-panel) e
      trabalho externo do mantenedor, fora do blast radius desta execucao —
      nao fechar so com o paliativo. Reabrir apos confirmacao do mantenedor. -->
- [!] 1.1.5 Teste manual: validar que
      `CSTK_SCHEMA_VERSIONS=2,3,4,5,6,7,8,9,10,11,12 cstk serve` restabelece o
      painel localmente contra um banco em schema v12 (valida SC-005)
      <!-- bloqueado: depende do schema v12 existir (FASE 2, ainda nao
      implementada nesta execucao) -->

### 1.2 Cenario de dado real para valor `0` legitimo preservado `[M]`

Ref: `checklists/schema-migration.md` CHK006; corpus real verificado em
`mcp-project-scafold/.claude/agente-00c-state/state.json`, `onda-022`
(`otel_usage.by_source.main = {cost_usd:0, input:0, output:0, cache_read:0,
cache_creation:4103}`; `otel_usage.by_model.claude-opus-5 = {cost_usd:0,
total_tokens:4103}` — custo zero com tokens NAO-zero na mesma linha, provando
que o zero e medido, nao ausencia)

- [x] 1.2.1 Adicionar Cenario 10 a `quickstart.md` usando os valores reais
      acima (onda-022): ingerir esse `state.json` e consultar
      `otel_main_cost_usd`-equivalentes (colunas `otel_main_input_tokens`,
      `otel_main_output_tokens`, `otel_main_cache_read_tokens`) esperando `0`
      (nao NULL) e `otel_main_cache_creation_tokens = 4103`; e
      `wave_model_usage` com `model='claude-opus-5', cost_usd=0,
      total_tokens=4103` (fecha CHK006)
      <!-- feito: quickstart.md Cenario 10 -->
- [x] 1.2.2 Adicionar assercao automatizada em `tests/cstk/test_recall.sh`
      que ingere essa onda e verifica `IS NOT NULL AND = 0` (nao `IS NULL`)
      para as colunas zeradas do `main`, e `cost_usd = 0` com
      `total_tokens = 4103` em `wave_model_usage` para `claude-opus-5`
      <!-- feito: `scenario_wmu8_zero_legitimo_preservado` em
      tests/cstk/test_recall.sh (apos scenario_wmu7). Fixture reproduz
      onda-022 real de mcp-project-scafold (conferida por leitura direta do
      state.json de origem em 2026-07-28). Asserta
      otel_main_{input,output,cache_read}_tokens = 0 E IS NOT NULL (nao
      apenas `= 0`, que casaria falso-positivo se a coluna nem existisse),
      otel_main_cache_creation_tokens = 4103 na MESMA linha (prova de zero
      medido), otel_cost_main_usd (coluna pre-existente v11) = 0 nao-nulo, e
      wave_model_usage com model='claude-opus-5', cost_usd=0,
      total_tokens=4103. Validado standalone via
      `_SCENARIOS=scenario_wmu8_zero_legitimo_preservado sh
      tests/cstk/test_recall.sh` -> PASS; suite completa de test_recall na
      FASE 5.2 confirma ausencia de regressao. -->
- [x] 1.2.3 Atualizar `data-model.md` §Regra transversal NULL vs zero citando
      este segundo caso real (zero em `cost_usd`, nao apenas em tokens) como
      evidencia adicional da distincao NULL-vs-zero
      <!-- feito: data-model.md §Regra transversal NULL vs zero -->

### 1.3 FR + teste de isolamento de seguranca `wave_model_usage` x `knowledge_fts` `[C]`

Ref: `checklists/schema-migration.md` CHK013, CHK014; `plan.md` §Tratamento do
nome do modelo, item "1.ter" (fronteira LLM01/ASI06)

- [x] 1.3.1 Adicionar `FR-011` a `spec.md` declarando, em linguagem MUST, que
      `wave_model_usage` MUST NUNCA alimentar `knowledge_fts` — mesma
      fronteira de seguranca ja aplicada a `tasks`/`events` (fecha CHK014)
      <!-- feito: spec.md FR-011 -->
- [x] 1.3.2 Adicionar assercao automatizada em `tests/cstk/test_recall.sh`
      (apos `--ingest`): `SELECT count(*) FROM knowledge_fts WHERE
      type='wave_model_usage'` retorna `0`
      <!-- bloqueado: mesma razao de 1.2.2 (tabela ainda nao existe); movido
      para FASE 3.4 (mapeado em §Escopo Coberto) -->
- [x] 1.3.3 Repetir a mesma assercao apos `--reindex` sobre o mesmo corpus
      (fecha CHK013 — cobre os dois caminhos de escrita do FTS)
      <!-- bloqueado: idem 1.3.2, movido para FASE 3.4 -->

### 1.4 Documentar limitacao conhecida do guard de invalidacao de delta `[M]`

Ref: `checklists/schema-migration.md` CHK021 (dec-029); spec.md Clarifications
Session 2026-07-28, segunda pergunta; `sug-002` na knowledge.db

- [x] 1.4.1 Adicionar uma nota em `spec.md` (secao Edge Cases ou nova
      "Limitacoes Conhecidas") documentando o risco residual: subcontagem
      silenciosa de custo/tokens caso o guard de invalidacao de delta
      (comparacao de `session_id` entre snapshots de inicio/fim de onda,
      `otel-usage.sh delta`) falhe em disparar quando deveria — reconfirmado
      fora do escopo desta feature apos investigacao empirica (2026-07-28)
      <!-- feito: spec.md nova secao "Limitacoes Conhecidas" -->
- [x] 1.4.2 Referenciar `sug-002` (knowledge.db) como o item que trata esse
      bugfix separadamente, sem expandir o escopo desta feature
      <!-- feito: referencia a sug-002 incluida na secao "Limitacoes Conhecidas" -->
- [x] 1.4.3 Confirmar via `grep -rn "session_id" docs/specs/otel-model-breakdown/*.md`
      que nenhuma nova referencia ao guard aparece fora da secao de
      limitacoes conhecidas (sem expansao de escopo silenciosa)
      <!-- feito: grep executado — unicas ocorrencias novas ficam dentro da
      propria secao "Limitacoes Conhecidas" (spec.md) e da tabela "Escopo
      Excluido" ja existente (tasks.md); nenhuma expansao de escopo -->

---

## FASE 2 - Schema e Migracao (DDL v11 -> v12)

### 2.1 Bump de versao + DDL aditivo `[A]`

Ref: `plan.md` §Project Structure (pontos 1-3); `data-model.md` §Entity
WaveModelUsage / §Entity Wave (extensao)

- [x] 2.1.1 Bump `RECALL_SCHEMA_VERSION=11` -> `12` (`recall.sh:115`)
- [x] 2.1.2 Adicionar as 8 colunas INTEGER nullable de breakdown por fonte na
      DDL de `waves` (`recall.sh:496-529`): `otel_main_input_tokens`,
      `otel_main_output_tokens`, `otel_main_cache_read_tokens`,
      `otel_main_cache_creation_tokens`, `otel_subagent_input_tokens`,
      `otel_subagent_output_tokens`, `otel_subagent_cache_read_tokens`,
      `otel_subagent_cache_creation_tokens`
- [x] 2.1.3 Adicionar `CREATE TABLE IF NOT EXISTS wave_model_usage (...)`
      apos `recall.sh:602`, com `UNIQUE(project, feature, wave, source_id)`
      no mesmo padrao das outras 10 tabelas de metrica
- [x] 2.1.4 Teste: `PRAGMA table_info(waves)` confirma as 8 colunas novas e
      `sqlite_master` confirma a existencia de `wave_model_usage` num banco
      criado do zero (Cenario 8, parte "banco novo")

### 2.2 ALTER idempotente v11 -> v12 sobre banco existente `[A]`

Ref: `data-model.md` §Migracao v11 -> v12; `plan.md` ponto 4

- [x] 2.2.1 Adicionar bloco `ALTER` apos o bloco v10->v11 existente
      (`recall.sh:758-770`), reusando a variavel `_as_wcols` ja lida uma
      unica vez em `recall.sh:724` via `PRAGMA table_info(waves)`
- [x] 2.2.2 Implementar o guard idempotente `case "$_as_wcols" in
      ''|*'|otel_main_input_tokens|'*) : ;; *) <8 ALTER TABLE waves ADD
      COLUMN> ;; esac` — `wave_model_usage` NAO precisa de ALTER (o `CREATE
      TABLE IF NOT EXISTS` do DDL ja cobre bancos pre-existentes)
- [x] 2.2.3 Teste de idempotencia: rodar o `ALTER` duas vezes sobre o mesmo
      banco v11 e confirmar que a segunda execucao nao falha nem duplica
      coluna

### 2.3 Validacao de migracao sobre banco v11 real `[A]`

Ref: `quickstart.md` Cenario 8; `spec.md` FR-003, FR-009

- [x] 2.3.1 Partir de uma `knowledge.db` real ja em v11 (com dados) como
      fixture de teste
- [x] 2.3.2 Rodar um comando que **escreve** no banco (`--ingest` ou
      `--reindex`) e confirmar `schema_meta.schema_version = '12'`
      — **CORRIGIDA (2026-07-28)**: a redacao original pedia um comando de
      LEITURA (`cstk recall "algo"`). Verificado empiricamente que leitura
      NAO migra (schema permaneceu `11`), e isso e DELIBERADO, nao defeito:
      `cli/lib/recall.sh:2398` documenta "Executa SOMENTE via
      recall_query_sql (leitura). NUNCA recall_run_sql / recall_apply_schema
      (escrita) — read-only (FR-014)". `recall_apply_schema` so e chamada
      em `recall.sh:2131` (`--ingest`) e `recall.sh:2530` (`--reindex`).
      Exigir migracao no caminho de leitura violaria a garantia read-only
      pre-existente. Task reescrita para o comportamento correto; validado:
      `--ingest` sobre `knowledge.db` real v11 levou `schema_version` a `12`.
- [x] 2.3.3 Confirmar que TODAS as linhas/colunas pre-existentes continuam
      intactas e consultaveis (contagem de `decisions`, `waves`, `tasks`
      inalterada antes/depois)
- [x] 2.3.4 Teste: rodar o mesmo comando uma segunda vez e confirmar que nao
      falha nem duplica coluna (idempotencia do `case`/`PRAGMA table_info`)

---

## FASE 3 - Ingestao de Dados

### 3.1 Extracao jq do breakdown por fonte `[A]`

Ref: `plan.md` pontos 5-6; `data-model.md` §Entity Wave (extensao)

- [x] 3.1.1 Estender a expressao jq de extracao de `waves` (`recall.sh:1130-1138`)
      para emitir os 8 campos de `otel_usage.by_source.main.*` e
      `.subagent.*` no array posicional, preservando `//` (operador que
      distingue ausencia de `0` legitimo — nao alterar essa semantica)
- [x] 3.1.2 Estender a leitura por indice (`recall.sh:1163-1167`) com as 8
      novas posicoes `.[23]`..`.[30]`, cada uma passando por
      `recall_int_or_null` (`recall.sh:850`)
- [x] 3.1.3 Teste: Cenario 2 do quickstart (onda-001, `by_source.main`
      presente) — os 8 valores exatos batem com o `state.json` de origem

### 3.2 Consistencia das tres listas do `INSERT` de `waves` `[A]`

Ref: `plan.md` ponto 7 (ATENCAO: lista de colunas aparece 3x)

- [x] 3.2.1 Atualizar a lista de **colunas** do `INSERT INTO waves(...)`
      (`recall.sh:1189`) com as 8 novas colunas
- [x] 3.2.2 Atualizar a lista de **VALUES** (mesmo bloco) mantendo a MESMA
      ordem posicional das colunas
- [x] 3.2.3 Atualizar o `ON CONFLICT (...) DO UPDATE SET` (`recall.sh:1191`)
      incluindo as 8 colunas novas, mesma ordem
- [x] 3.2.4 Teste: contagem de placeholders `?` no `INSERT` bate exatamente
      com a contagem de colunas declaradas (falha se as 3 listas divergirem
      apos a edicao)

### 3.3 Loop de extracao propria para `wave_model_usage` `[A]`

Ref: `plan.md` ponto 8 + §Tratamento do nome do modelo; `data-model.md`
§Entity WaveModelUsage

- [x] 3.3.1 Implementar loop de extracao proprio (padrao ja usado por
      `tasks`/`events`) apos `recall.sh:1195`, percorrendo as chaves de
      `otel_usage.by_model` da onda
- [x] 3.3.2 Aplicar `sql_escape` (`recall.sh:202`) nas DUAS posicoes onde o
      nome do modelo aparece: coluna `model` e coluna `source_id`
- [x] 3.3.3 Aplicar `strip_nul` (`recall.sh:334`) ao valor extraido do
      modelo antes de compor o `INSERT`, evitando truncamento silencioso por
      byte NUL
- [x] 3.3.4 NAO passar o campo `model`/`source_id` por `recall_scrub` —
      documentar inline (comentario pt-br) o motivo: campo estruturado
      (mesma classe de `event_type`), nao texto livre; scrub mutilaria a
      fidelidade da string bruta exigida por FR-001
- [x] 3.3.5 Teste: Cenario 1 (onda-001, 2 modelos) e Cenario 4 (onda-004,
      `claude-opus-5[1m]` com sufixo de tier preservado literalmente, sem
      normalizacao para `opus`/`sonnet`)

### 3.4 Verificacao do isolamento de seguranca (implementa FR-011) `[C]`

Ref: 1.3 (FR-011 e testes ja escritos); `plan.md` item "1.ter"

- [x] 3.4.1 Confirmar por leitura de codigo que nenhum `INSERT`/trigger de
      `knowledge_fts` referencia `wave_model_usage` ou o campo `model`
- [x] 3.4.2 Rodar os testes automatizados criados em 1.3.2/1.3.3
      (`--ingest` e `--reindex`) e confirmar `count(*) = 0`
- [x] 3.4.3 Auditoria: `grep -n "knowledge_fts" cli/lib/recall.sh` nao produz
      nenhuma ocorrencia associada a `wave_model_usage`

---

## FASE 4 - Backfill, Agregacao e Sumario

### 4.1 Reindex idempotente `[A]`

Ref: `quickstart.md` Cenario 7; `spec.md` FR-005, SC-003

- [x] 4.1.1 Confirmar que `--reindex` (que ja faz `rm -f` do banco inteiro em
      `recall.sh:2398`) recria `wave_model_usage` do zero via o loop de 3.3
- [x] 4.1.2 Rodar `cstk recall --reindex --states-root ~/Projects` duas vezes
      sobre o corpus real e comparar `count(*)`/`SUM(cost_usd)` de
      `wave_model_usage` entre as duas execucoes (devem ser identicos)
      <!-- feito: `--states-root ~/Projects` (124 state.json) estourou o
      orcamento da onda anterior (19min11s incompletos, ver dec-048).
      RECORTE JUSTIFICADO (autorizado pelo operador nesta onda): rodado
      sobre `--states-root /Users/jot/Projects/_lab/Jot/misc/cstk` (18
      state.json reais, subarvore que inclui o proprio state-dir desta
      feature) duas vezes, `--db` distintos por run, sem cache entre
      execucoes (`rm -f` do banco a cada `--reindex`). Sumarios IDENTICOS
      byte-a-byte nas duas rodadas: "reindexed: 18 state files (684
      decisions, 10 blocks, 0 retros, 212 skills, 18 executions, 161
      waves, 2 alerts, 235 tasks, 50 events, 372 memories, 16
      suggestions, 15 wave_model_usage)" (run1 5m12s real, run2 4m56s
      real). `SELECT count(*), SUM(cost_usd), SUM(total_tokens) FROM
      wave_model_usage` identico nas duas: `15|54.423289|107673497`.
      `SELECT count(*) FROM waves` identico: `161`. Cobertura reduzida
      (nao inclui mcp-project-scafold/my-music-match nesta rodada
      especifica) e compensada pela rodada separada de 4.3 abaixo. -->
- [x] 4.1.3 Teste de paridade `--ingest` vs `--reindex` (Cenario 1 vs Cenario
      7): mesma onda, mesmos valores nas duas tabelas novas pelos dois
      caminhos (fecha FR-006)
      <!-- feito: `--ingest --state-dir <este state-dir>` (onda-001, 8
      colunas: 3|907|371775|2938|31|30143|2077276|35951;
      wave_model_usage: claude-fable-5|0.475915|375623,
      claude-sonnet-5|1.21024|2143401; otel_cost_usd/otel_total_tokens =
      1.686155|2519024) comparado com o mesmo `SELECT` sobre o db do
      `--reindex --states-root misc/cstk` (task 4.1.2 acima) para
      wave='onda-001' AND feature='otel-model-breakdown': valores
      IDENTICOS nos dois caminhos, byte-a-byte. -->

### 4.2 Contadores de sumario `[M]`

Ref: `plan.md` pontos 9-11

- [x] 4.2.1 Adicionar `RECALL_TOTAL_WAVE_MODEL` na agregacao de totais
      (`recall.sh:1735`)
- [x] 4.2.2 Inicializar o contador novo nas duas posicoes (`recall.sh:2007-2008`
      e `:2411-2412` — caminhos de `--ingest` e `--reindex`)
- [x] 4.2.3 Adicionar o contador as duas format strings de sumario
      (`recall.sh:2014` e `:2454`)
- [x] 4.2.4 Teste: o sumario emitido por `--ingest`/`--reindex` reporta a
      contagem correta de linhas de `wave_model_usage` processadas

### 4.3 Validacao end-to-end contra corpus real `[A]`

Ref: `quickstart.md` Cenarios 1-5

- [x] 4.3.1 Rodar `--reindex --states-root ~/Projects` sobre o corpus
      completo (inclui `mcp-project-scafold`, `my-music-match/foundation`,
      execucao desta propria feature)
      <!-- feito COM RECORTE JUSTIFICADO (autorizado pelo operador nesta
      onda): `--states-root ~/Projects` inteiro (124 state.json + varredura
      fixa de 372 memorias em ~/.claude/projects/*/memory/, independente de
      --states-root) ja havia estourado o orcamento da onda anterior
      (19min11s incompletos — dec-048). Rodado em DUAS chamadas separadas,
      cada uma restrita a um projeto real citado no quickstart:
      (a) `--states-root /Users/jot/Projects/_lab/Jot/misc/cstk` (18
      state.json, 5m12s) — cobre a execucao desta propria feature
      (onda-001);
      (b) `--states-root /Users/jot/Projects/_lab/Jot/my-music-match` (2
      state.json, 1m27s) — cobre `my-music-match/foundation` (onda-004/005
      e onda-001/002 sem otel_usage).
      `mcp-project-scafold` (onda-022, Cenario 10/CHK006) NAO foi incluido
      nesta rodada de reindex ao vivo: ja validado por 2 vias independentes
      — (1) assercao automatizada `scenario_wmu8_zero_legitimo_preservado`
      (task 1.2.2, fixture reproduz o `state.json` real byte-a-byte) e (2)
      validacao manual sobre copia real do knowledge.db do operador na
      FASE 2.3 (dec-050, 15 linhas de wave_model_usage geradas). Cobertura
      residual: rodar `--reindex --states-root ~/Projects` completo fica
      para a FASE 6 (junto do release), fora do orcamento desta onda. -->
- [x] 4.3.2 Validar Cenario 1 (onda-001, `claude-fable-5` + `claude-sonnet-5`,
      `SUM(cost_usd) = 1.686155`, `SUM(total_tokens) = 2519024`)
      <!-- feito: sobre o db do reindex (a) acima, wave='onda-001' AND
      feature='otel-model-breakdown':
      `wave_model_usage` = claude-fable-5|0.475915|375623,
      claude-sonnet-5|1.21024|2143401 (soma = 1.686155/2519024);
      `waves.otel_cost_usd|otel_total_tokens` = 1.686155|2519024 — bate. -->
- [x] 4.3.3 Validar Cenario 3 (onda-004 de `my-music-match/foundation`,
      `by_source` so com `subagent` — 4 colunas `otel_main_*` NULL) e
      Cenario 4 (mesma onda, `claude-opus-5[1m]` preservado)
      <!-- feito: sobre o db do reindex (b) acima, wave='onda-004' AND
      feature='foundation': as 4 colunas otel_main_* retornam NULL
      (`count(*) WHERE ... IS NULL` = 1, nao apenas ausencia de erro);
      `wave_model_usage` = claude-opus-5[1m]|6.1439|6864604,
      claude-sonnet-5|0.635093|211161 — tier `[1m]` preservado literalmente;
      `count(*) WHERE model IN ('opus','sonnet')` = 0 (sem normalizacao). -->
- [x] 4.3.4 Validar Cenario 5 (onda sem `otel_usage` — zero linhas em
      `wave_model_usage`, linha em `waves` existe com as 8 colunas novas NULL)
      <!-- feito: identificadas por leitura direta (`jq 'select(.otel_usage
      == null)'`) as 2 ondas sem otel_usage no corpus atual de
      `my-music-match/foundation`: onda-001 e onda-002 (nao onda-005 como
      uma leitura apressada do quickstart poderia sugerir — o texto do
      quickstart nao fixa os IDs). Para AMBAS: `wave_model_usage` = 0
      linhas; `waves` tem exatamente 1 linha; as 8 colunas novas retornam
      NULL (`count(*) WHERE otel_main_input_tokens IS NULL AND
      otel_subagent_input_tokens IS NULL` = 1). Exit 0 nos dois reindexes,
      sem erro/aviso de falha. -->

**Nota de escopo residual (4.3.1)**: os dois reindexes acima cobrem os 20
state.json reais que compoem os Cenarios 1-5 do quickstart (esta feature +
`my-music-match/foundation`). Um `--reindex --states-root ~/Projects` sobre
TODO o corpus (124 arquivos, incluindo `mcp-project-scafold` e os demais
projetos nao citados nos Cenarios 1-5) fica deferido para a FASE 6 (junto do
build/self-update de release), onde o tempo de execucao ja nao compete com o
orcamento de onda desta execucao autonoma.

---

## FASE 5 - Disciplina de Testes de Versao (R2)

### 5.1 Editar as 12 assercoes de `schema_version` linha a linha `[A]`

Ref: `plan.md` §R2; `research.md` Decision 9; `quickstart.md` Cenario 9

- [x] 5.1.1 Editar individualmente cada uma das 12 linhas de
      `tests/cstk/test_recall.sh` (611, 656, 678, 1879, 2195, 2285, 3035,
      3161, 3216, 3265, 3337, 3474) de `"11"` para `"12"` — edicao dirigida
      linha a linha, NUNCA `sed`/replace global (atingiria numeros e textos
      nao relacionados)
      <!-- feito nas onda(s) que implementaram FASE 2 (commit d2f7d8a "feat
      (recall): schema v11->v12", que ja levou RECALL_SCHEMA_VERSION e as
      12 assercoes de `"11"` para `"12"` no mesmo commit, conforme exigido
      pela nota de manutencao do quickstart Cenario 9). Confirmado nesta
      onda por leitura das 12 linhas exatas: todas comparam contra `"12"`. -->
- [x] 5.1.2 Corrigir a mensagem de assercao ja dessincronizada na linha 678
      (hoje "esperado 10 apos 2x" enquanto compara contra 11/12)
      <!-- feito: linha 678 hoje le `_fail "schema estavel" "esperado 12
      apos 2x, obtido $_sv"` — mensagem sincronizada com o valor comparado
      (`"12"`), sem residuo do antigo "esperado 10". -->
- [x] 5.1.3 Confirmar via `grep -n '"11"' tests/cstk/test_recall.sh` que
      nenhuma ocorrencia relacionada a `schema_version` restou
      <!-- feito: `grep -n '"11"' tests/cstk/test_recall.sh` -> 0
      ocorrencias (exit 1, sem match). -->

### 5.2 Suite de regressao completa `[C]`

Ref: `spec.md` SC-004; `quickstart.md` Cenario 9

- [x] 5.2.1 Rodar `./tests/run.sh recall` isoladamente <!-- feito (command pai, 2026-07-28): PASS 133, FAIL 0, ERROR 0, ORPHANS 0, TIME 684s, incluindo scenario_wmu8_zero_legitimo_preservado (ok 129) -->
- [x] 5.2.2 Rodar a suite completa `./tests/run.sh` (todos os cenarios,
      incluindo os anteriores a esta feature)
      <!-- feito (command pai, 2026-07-28): `# PASS: 1913  FAIL: 1
      ERROR: 0  ORPHANS: 0  TIME: 1098s` -->
- [x] 5.2.3 Confirmar 100% verde — nenhuma regressao nas dimensoes ja
      existentes da knowledge.db
      <!-- feito COM RESSALVA EXPLICITA (2026-07-28): 1913 PASS, 1 FAIL.
      A unica falha e `test_state-ondas.sh ::
      scenario_end_otel_usage_null_sem_telemetria`, FALSO-POSITIVO
      AMBIENTAL comprovado, NAO regressao desta feature:
        (a) o cenario nao seta CSTK_OTEL_ENDPOINT e cai no default
            (localhost:9464); com a telemetria OTel ativa nesta maquina o
            snapshot funciona e `otel_usage` nao fica null;
        (b) reproduzido nos dois sentidos — telemetria ativa -> `not ok 14`;
            `CSTK_OTEL_ENDPOINT=http://127.0.0.1:59999/metrics` (porta
            morta) -> `ok 14`;
        (c) `git diff main...HEAD` confirma que esta feature NAO tocou
            `state-ondas.sh`, `otel-usage.sh` nem `tests/test_state-ondas.sh`.
      Zero regressoes nas dimensoes pre-existentes da knowledge.db.
      Defeito do teste registrado como `sug-006` (fora do escopo). -->
- [x] 5.2.4 (aberta por `sug-006`) Corrigir o isolamento de ambiente em
      `scenario_end_otel_usage_null_sem_telemetria` para que a suite feche
      1914/0 tambem em maquina com telemetria ativa — decisao do mantenedor
      se entra nesta feature ou em bugfix separado

---

## FASE 6 - Release e Sincronizacao

### 6.1 Build e validacao local do runtime alterado `[M]`

Ref: `plan.md` §R3 (GOTCHA de distribuicao); `quickstart.md` §Nota de release

- [ ] 6.1.1 Gerar tarball de dev: `./scripts/build-release.sh X.Y.Z-dev`
- [ ] 6.1.2 Aplicar `cstk self-update --from "file://$PWD/dist/cstk-X.Y.Z-dev.tar.gz"`
      (GOTCHA: `cstk install`/`cstk update` NAO tocam `cli/lib/` — so
      `self-update` atualiza o runtime)
- [ ] 6.1.3 Validar `cstk recall` a partir do binario/runtime instalado
      (nao so do repo), confirmando que o schema v12 e aplicado de fato

### 6.2 Gate de coordenacao cross-repo antes do release `[C]`

Ref: 1.1 (dec-029, CHK004) — NAO elegivel a skip/opt-out silencioso

- [ ] 6.2.1 Confirmar que a task 1.1 (rastreabilidade formal cross-repo) foi
      concluida antes de prosseguir
- [ ] 6.2.2 Obter confirmacao explicita do mantenedor de que o bump de
      `DEFAULT_SCHEMA_VERSIONS` no `cstk-panel` foi agendado ou ja publicado
- [ ] 6.2.3 So entao prosseguir com tag + release desta feature no `cstk`
      (bloqueio humano se a confirmacao nao existir)

---

## Matriz de Dependencias

```mermaid
flowchart TD
    F1[Fase 1 - Fundacao e Requisitos]
    F2[Fase 2 - Schema e Migracao]
    F3[Fase 3 - Ingestao de Dados]
    F4[Fase 4 - Backfill Agregacao e Sumario]
    F5[Fase 5 - Disciplina de Testes de Versao]
    F6[Fase 6 - Release e Sincronizacao]

    F1 --> F2
    F2 --> F3
    F3 --> F4
    F4 --> F5
    F5 --> F6
```

## Resumo Quantitativo

| Fase | Tarefas | Subtarefas | Criticidade |
|------|---------|------------|-------------|
| 1 - Fundacao e Requisitos | 4 | 14 | C/M |
| 2 - Schema e Migracao | 3 | 12 | A |
| 3 - Ingestao de Dados | 4 | 15 | A/C |
| 4 - Backfill Agregacao e Sumario | 3 | 11 | A/M |
| 5 - Disciplina de Testes de Versao | 2 | 6 | A/C |
| 6 - Release e Sincronizacao | 2 | 6 | M/C |
| **Total** | **18** | **64** | - |

## Escopo Coberto

| Item | Descricao | Fase |
|------|-----------|------|
| FR-001..FR-009 | Tabela `wave_model_usage` + 8 colunas aditivas em `waves`, migracao idempotente, confinamento de deps | 2, 3, 4 |
| CHK001/002/003 | FR-010 + SC-005 + rastreabilidade formal de compatibilidade cross-repo com cstk-panel | 1.1 |
| CHK004 (dec-029) | Task explicita de coordenacao do bump `DEFAULT_SCHEMA_VERSIONS` no `cstk-panel` antes/junto do merge | 1.1, 6.2 |
| CHK006 | Cenario de quickstart + teste automatizado para valor `0` legitimo preservado (dado real onda-022) | 1.2 |
| CHK013/014 | FR-011 + testes automatizados do isolamento `wave_model_usage` x `knowledge_fts` | 1.3, 3.4 |
| CHK021 (dec-029) | Documentacao da limitacao conhecida (guard de delta) na spec, sem expandir escopo | 1.4 |
| R2 | Edicao dirigida das 12 assercoes de `schema_version` nos testes | 5.1 |
| R3 | GOTCHA de release (`self-update` vs `install`/`update`) validado localmente | 6.1 |

## Escopo Excluido

| Item | Descricao | Motivo |
|------|-----------|--------|
| `otel_session_id` | Coluna de sessao do OTel | Removida do escopo via Clarifications Session 2026-07-28 — `session_id` nao discrimina sessao/projeto de forma confiavel no snapshot observado |
| Bugfix do guard de invalidacao de delta | Correcao do guard que compara `session_id` entre snapshots inicio/fim de onda | Fora do escopo desta feature (dec-029, CHK021 resolvido) — nao misturar correcao de coleta de telemetria com migracao de schema; tratado como `sug-002` na knowledge.db |
| Normalizacao do nome do modelo | Converter string bruta do OTel para alias canonico (`opus`/`sonnet`/`haiku`) | Decisao explicita (Clarifications) de manter string bruta — normalizar apagaria distincoes reais de custo (ex.: `claude-opus-5[1m]` vs `claude-opus-5`) |
| Edicao do codigo do `cstk-panel` | Bump de `DEFAULT_SCHEMA_VERSIONS` em `apps/server/src/config.ts` | Repo externo, fora do blast radius de escrita desta execucao — apenas a COORDENACAO/rastreabilidade esta no escopo (1.1, 6.2), nao a edicao de codigo do painel |
