# Operational Checklist: Paridade Backend-Agnostica dos Hooks 00C

**Purpose**: Validar a QUALIDADE dos requisitos operacionais da feature
`hooks-db-parity` — degradacao, observabilidade, distribuicao, prevencao de
regressao e tolerancias. Os tres hooks rodam sincronamente a cada tool call, em
toda sessao do operador: erro operacional aqui e sentido em cada interacao.
**Created**: 2026-08-03
**Feature**: [spec.md](../spec.md)
**Numeracao**: continua a partir de [security.md](./security.md) (CHK001-CHK022)
para evitar colisao de IDs dentro da feature.

## Degradacao e disponibilidade de dependencia

- [x] CHK023 - Esta definido o comportamento de cada hook quando a dependencia `sqlite3` esta ausente do host? [Completude, Spec §FR-003/§FR-004; quickstart §Cenario 5/§Cenario 6] {auto}
      → Divergencia intencional e documentada por hook: guarda bloqueia (`MECANISMO_FALHOU`, cenario 5), metricas viram no-op silencioso (cenario 6).
- [x] CHK024 - Esta definido o comportamento quando o catalogo instalado esta stale e o helper compartilhado nao pode ser resolvido? [Cobertura, plan §Riscos; research §Decision 5] {auto}
      → Fallback JSON inline preserva o comportamento atual quando nao ha `state.db`; o impacto de bloqueio fica restrito a projetos ja migrados — que hoje estao sem guarda alguma (nao ha piora relativa ao estado corrente).
- [x] CHK025 - Os requisitos preservam explicitamente o caminho JSON (base instalada majoritaria) como nao-regressao? [Consistencia, plan §Riscos; research §Decision 2] {auto}
      → Requisito de nao-regressao declarado: o caminho `jq`/`state.json` permanece inline e inalterado, e a suite existente dos 3 hooks e o piso de nao-regressao.
- [x] CHK026 - Ha requisito cobrindo contencao transitoria do SQLite (busy/lock) para que nao vire falha espuria? [Cobertura, Spec §Edge Cases (3o); contracts/hook-active-exec.md §SEC-M2] {auto}
      → `PRAGMA busy_timeout=200` exigido antes do `SELECT`, com o gotcha do eco do pragma no stdout do CLI documentado (precedente `_state-db.sh`).
- [x] CHK027 - O valor do `busy_timeout` (200 ms) esta reconciliado com o orcamento de latencia do hook de metrica (~30 ms)? [Ambiguity, contracts/hook-active-exec.md §SEC-M2 vs Spec §FR-005] {auto}
      → **Resolvido (task 1.6, onda-006)**: politica DIFERENCIADA por hook — guarda mantem `busy_timeout=200ms` (fail-closed tolera a espera, cabe no teto de gate de 400ms); hooks de metrica usam `busy_timeout=50ms` (fail-open nao pode custar 200ms em toda tool call sem estourar o teto de gate de 150ms) — `contracts/hook-active-exec.md §SEC-M2` e `spec.md` FR-004 atualizados.

## Observabilidade e auditoria

- [x] CHK028 - Os requisitos preservam o registro auditavel das decisoes de bloqueio sob o novo backend? [Completude, contracts/hook-io.md §"Efeito colateral"; data-model §EnforcementDecisionLog] {auto}
      → Append de 1 linha em `<cwd>/.claude/enforcement-log.jsonl` mantido como efeito colateral contratual, com o schema da entidade inalterado (`[EXISTENTE]`).
- [x] CHK029 - Esta definido que falha ao gravar o log de auditoria nao pode alterar a decisao do hook? [Clareza, contracts/hook-io.md §"Efeito colateral"] {auto}
      → Explicito: "falha de escrita nunca aborta o hook" (aviso apenas), preservando a separacao entre decidir e registrar.
- [x] CHK030 - Os requisitos permitem distinguir, no diagnostico, um bloqueio por regra de um bloqueio por falha de mecanismo? [Mensurabilidade, Spec §FR-003; contracts/hook-io.md §"Condicoes de MECANISMO_FALHOU"] {auto}
      → `MECANISMO_FALHOU` e nomeado como categoria distinta de `REGRA_VIOLADA`, com secao dedicada de condicoes no contrato de I/O.
- [x] CHK031 - O campo `backend` da sonda esta declarado como informativo, sem virar dependencia de comportamento? [Clareza, data-model §ActiveExecutionProbe] {auto}
      → Tabela de campos marca `backend` como "informativo para log/diagnostico"; a decisao do consumidor depende exclusivamente do exit code.

## Criterios de aceite mensuraveis

- [x] CHK032 - O criterio de sucesso da guarda e expresso como taxa verificavel, e nao como adjetivo? [Mensurabilidade, Spec §SC-001] {auto}
      → "100% dos casos testados" continuam bloqueados sob `state.db`, comparado contra a linha de base JSON.
- [x] CHK033 - A tolerancia de fronteira aceita para a contagem de tool calls esta quantificada? [Ambiguity, Spec §SC-002/§US2 Acceptance 1] {auto}
      → **Resolvido (task 1.7, onda-006)**: tolerancia = maximo **2 ticks perdidos por onda** (1 na abertura + 1 no fechamento), derivada do mecanismo real de reset/agregacao do sidecar em `state-ondas.sh` (`start` L604, `end`/`_so_ticks_count` L365-372/L738-739) — `spec.md` SC-002 e `quickstart.md §Cenario 12` atualizados com o criterio verificavel.
- [x] CHK034 - O gate de latencia tem estatistica, tamanho de amostra e condicao de skip definidos, em vez de "medir a latencia"? [Mensurabilidade, research §Decision 3; quickstart §Cenario 7] {auto}
      → Mediana (nao media/p95) de N=20 apos 3 warm-ups; tetos por hook; skip — nunca fail — se `perl` ou `sqlite3` ausentes.
- [x] CHK035 - O criterio de nao-interferencia em sessao manual e observavel por contagem? [Mensurabilidade, Spec §SC-004; quickstart §Cenario 8/§Cenario 10] {auto}
      → "0 bloqueios e 0 escritas de sidecar fora de uma execucao ativa", exercitado por sandbox limpo (cenario 8) e por execucao em status terminal (cenario 10).
- [x] CHK036 - Existe cenario de aceite que prova o bug ANTES da correcao (baseline), evitando teste que passaria de qualquer jeito? [Cobertura, quickstart §Cenario 0] {auto}
      → Cenario 0 dedicado a reproduzir o fail-open atual sob SQLite; sem ele, os cenarios 1-3 nao provariam causalidade.

## Cobertura de cenarios e prevencao de regressao

- [x] CHK037 - Cada requisito funcional tem ao menos um cenario de validacao associado? [Cobertura, quickstart §"Mapa cenario x requisito"] {auto}
      → Mapa explicito cobrindo FR-001..FR-007 e SC-001..SC-004; confirmado tambem pelo gate deterministico `requirement-coverage.sh` sobre a spec: `requirements=7|covered=7|errors=0` (exit 0).
- [x] CHK038 - Ha requisito de prevencao de regressao que impeca um hook futuro de voltar a ler `state.json` direto? [Completude, quickstart §Cenario 11; research §Decision 6] {auto}
      → Extensao do `test_state-parity-sweep.sh` ao diretorio `hooks/` com allowlist (decisao registrada em `dec-022`), transformando a regra em varredura estatica que falha a suite.
- [x] CHK039 - O escopo do cenario "backend misto" esta explicitamente delimitado, em vez de ficar implicitamente exigido? [Clareza, Spec §Clarifications/§Assuncoes; §Edge Cases (2o)] {auto}
      → Resolvido como best-effort/nao garantido: sem cenario de teste dedicado exigido, mas a precedencia determinista de FR-002 continua valendo se a mistura ocorrer por acidente.
- [x] CHK040 - Os requisitos cobrem execucao em status terminal como caso distinto de "nenhuma execucao"? [Cobertura, data-model §"Validation rules"; quickstart §Cenario 10] {auto}
      → `abortada`/`concluida` MUST resultar em nao-ativo, com cenario proprio (10) verificando que nao ativam nada.

## Distribuicao e rollout

- [x] CHK041 - Esta definido que a feature nao introduz mecanismo novo de distribuicao? [Completude, plan §"Distribuicao (sem mecanismo novo)"] {auto}
      → Secao dedicada declara reuso do provisionamento existente (`apply_guard_hooks`, escopo `project`), sem novo canal.
- [x] CHK042 - O `settings.snippet.json` (matchers e timeouts) esta declarado como inalterado, evitando mudanca silenciosa de contrato com o harness? [Consistencia, plan §Project Structure] {auto}
      → Marcado "INALTERADO — matchers e timeouts preservados" na arvore de arquivos do plano.
- [x] CHK043 - A ordem de rollout entre catalogo (`~/.claude`) e runtime esta definida para evitar janela de incoerencia? [Gap, plan §"Distribuicao"] {auto}
      → **Resolvido (task 1.8, onda-006)**: `plan.md §Distribuicao` (paragrafo "Ordem de rollout catalogo x runtime") documenta que hooks + helper vivem na mesma skill (mesmo `cstk update`/`install`, sem janela hook-novo-vs-helper-ausente) e aceita o unico risco residual (troca de arquivos durante onda aberta) sem mitigacao adicional, por ser identico ao de qualquer update de skill hoje.
- [ ] CHK044 - A decisao de habilitar a guarda em projetos hoje desprotegidos foi validada com o dono quanto a impacto operacional? [Risco, Spec §US1 "Why this priority"] {humano}
      → Em aberto: a correcao reativa bloqueios em todo projeto migrado para SQLite que hoje roda sem guarda alguma. E o objetivo da feature, mas muda o comportamento percebido nesses projetos — confirmar antes do rollout.
- [ ] CHK045 - A profundidade de validacao antes do merge (suite completa vs `--fast`) esta acordada para uma mudanca que roda a cada tool call? [Risco, plan §Estrategia de implementacao] {humano}
      → Em aberto: cada fase e declarada mergeavel isoladamente; falta o dono definir se o gate de merge exige a suite completa (~12 min) ou o subconjunto rapido.

## Notes

- Items `{auto}` resolvidos contra os artefatos com citacao rastreavel; `[Gap]`/`[Ambiguity]` sao achados reais, nao pendencias de leitura.
- Items `{humano}` (CHK044, CHK045) ficam `[ ]` aguardando o dono do produto antes de `/execute-task`.
- Nenhum item aqui testa implementacao — todos avaliam se o requisito escrito e completo, nao-ambiguo e verificavel.
