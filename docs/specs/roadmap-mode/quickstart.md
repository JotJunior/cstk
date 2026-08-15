# Quickstart / Cenarios de Teste: roadmap-mode

**Feature**: `roadmap-mode`

Cenarios de validacao end-to-end. Cada um mapeia para pelo menos um
Success Criterion da spec ou para um achado do gate de seguranca.

**Classificacao**: os cenarios 1-3, 5-8 e 10-12 sao automatizaveis na
suite POSIX (`tests/`). O cenario 4 exige execucao real do orquestrador
(aceitacao manual). O cenario 9 e parcialmente automatizavel — a
validacao estrutural do roadmap de 1 entrada e automatizavel; a presenca
da sugestao no relatorio final depende de execucao real.

---

## Cenario 1 — Nao-regressao: sem opt-in, pipeline identica (SC-003) `[CRITICO]`

O cenario mais importante da feature: o modo e aditivo e o caminho
default nao pode mudar.

1. Rodar `pipeline.sh stages` **sem** `--mode`
   → **Expected**: exatamente as 10 etapas atuais, na ordem atual
   (`briefing constitution specify clarify plan checklist create-tasks
   execute-task review-task review-features`). Byte-identico ao anterior.
2. Rodar `pipeline.sh next-stage --current constitution` sem `--mode`
   → **Expected**: `specify`.
3. Rodar `pipeline.sh stages --mode default`
   → **Expected**: identico ao passo 1.
4. Inicializar um estado sem `--roadmap-mode` e ler
   `roadmap-mode.sh is-enabled`
   → **Expected**: `false`, exit 0.
5. Rodar a suite existente de `tests/test_pipeline.sh` e
   `tests/test_state-ondas.sh`
   → **Expected**: verde, sem edicao das assercoes existentes. Se
   alguma assercao existente precisou ser alterada para passar, a
   mudanca **nao** e aditiva — parar e redesenhar.

---

## Cenario 2 — Lista escopada por modo (FR-002)

1. `pipeline.sh stages --mode roadmap`
   → **Expected**: `briefing constitution roadmap` (3 etapas).
2. `pipeline.sh next-stage --mode roadmap --current briefing`
   → **Expected**: `constitution`.
3. `pipeline.sh next-stage --mode roadmap --current constitution`
   → **Expected**: `roadmap` (**nao** `specify` — esta e a assercao que
   prova que o modo nao vaza para a pipeline de implementacao).
4. `pipeline.sh next-stage --mode roadmap --current roadmap`
   → **Expected**: stdout vazio, exit 0 (terminal).
5. `pipeline.sh stages --mode inexistente`
   → **Expected**: exit 2, diagnostico em stderr.
6. `pipeline.sh prev-stage --mode roadmap --current roadmap`
   → **Expected**: `constitution` (a flag `--mode` vale para as tres
   consultas de etapa, nao so `stages`/`next-stage`).
7. `pipeline.sh prev-stage --mode roadmap --current briefing`
   → **Expected**: stdout vazio, exit 0 (primeira etapa).

---

## Cenario 3 — Flag do modo persiste sem migracao de schema (FR-001)

Rodar **nos dois backends** (JSON e SQLite).

1. `state-rw.sh init ... --roadmap-mode true`
   → **Expected**: exit 0, estado criado.
2. `roadmap-mode.sh is-enabled --state-dir <SD>`
   → **Expected**: `true`, exit 0.
3. Sob backend SQLite, inspecionar `execution.extra_fields`
   → **Expected**: contem `roadmap_mode_enabled`; **nenhuma coluna nova**
   na tabela `execution`.
4. `state-rw.sh init ... --roadmap-mode talvez`
   → **Expected**: exit 2, nenhum estado escrito.
5. Estado criado **sem** a flag, depois `is-enabled`
   → **Expected**: `false`, exit 0 (campo ausente ⇒ default seguro).

---

## Cenario 4 — Execucao completa do modo (SC-001) `[ACEITACAO MANUAL]`

1. Em projeto-alvo limpo, iniciar `/agente-00c` e responder
   afirmativamente ao prompt do modo roadmap.
2. Deixar a execucao conduzir briefing e constitution.
3. Ao concluir a etapa `roadmap`
   → **Expected**: existe `docs/roadmap.md`; **nao existe** nenhum
   diretorio novo em `docs/specs/` criado pela execucao.
4. Ler o estado da execucao
   → **Expected**: `.execution.status` = `concluida`,
   `.execution.termination_reason` = `concluido`, `.execution.finished_at`
   preenchido.
5. Ler o relatorio final
   → **Expected**: o roadmap (features, ordem, dependencias) consta no
   relatorio (FR-004).
6. Verificar que a execucao **nao** reagendou
   → **Expected**: `Schedule intent: none; motivo=concluido`.
7. Contar as ondas consumidas
   → **Expected**: menos ondas que uma execucao completa do mesmo
   projeto (SC-001); o modo nunca alcanca `specify`.

---

## Cenario 5 — Validacao estrutural do artefato (gate de conclusao)

1. `pipeline.sh detect-completion --stage roadmap --projeto-alvo-path <PAP>`
   com `docs/roadmap.md` ausente
   → **Expected**: exit 1.
2. Idem, com roadmap valido (header + `## Features` + >= 1 entrada bem
   formada)
   → **Expected**: exit 0.
3. Idem, com entrada cujo `short-name` do metadado diverge do heading
   → **Expected**: exit 1, stderr apontando a divergencia.
4. Idem, com `short-name` invalido (ex.: `Auth_Basica`)
   → **Expected**: exit 1.
5. Idem, com dependencia apontando para short-name inexistente no
   documento
   → **Expected**: exit 1.
6. Idem, com `[TBD]` no corpo de uma entrada
   → **Expected**: exit 1.
7. Idem, com dois short-names iguais
   → **Expected**: exit 1 (chave natural duplicada).

---

## Cenario 6 — Entrada consumivel pelo `/feature-00c` (SC-002)

1. Gerar (ou fixar) um roadmap com >= 2 entradas.
2. Extrair o primeiro short-name com o comando de referencia do
   contrato (`sed -n 's/^### [1-9][0-9]*\. \([a-z][a-z0-9-]*\)$/\1/p'`)
   → **Expected**: short-name limpo, sem crases nem numeracao.
3. Validar o short-name contra `^[a-z][a-z0-9-]*$`
   → **Expected**: casa — aceito pelo `/feature-00c` sem edicao.
4. Verificar que `docs/briefing.md` e `docs/constitution.md` existem e
   satisfazem a pre-condicao do `/feature-00c`
   → **Expected**: pre-condicao satisfeita pelos artefatos da propria
   execucao roadmap; a feature inicia sem retrabalho.

---

## Cenario 7 — Idempotencia da re-execucao (SC-004) `[CRITICO]`

1. Partir de um roadmap com 3 entradas: `a-um`, `b-dois`, `c-tres`.
2. Criar `docs/specs/a-um/` (simulando feature ja iniciada).
3. Re-executar a geracao do roadmap, com a analise sugerindo tambem uma
   feature nova `d-quatro`.
4. Inspecionar o roadmap resultante
   → **Expected**: 4 entradas; `a-um`, `b-dois`, `c-tres` preservadas
   com short-name e descricao originais; `d-quatro` anexada.
   → **Expected**: **zero** entradas duplicadas.
   → **Expected**: `a-um` nao foi renomeada nem re-sugerida sob outro
   nome.
5. Rodar o cruzamento de status
   → **Expected**: `a-um` = `em-andamento`; as demais = `nao-iniciada`.
6. Repetir o passo 3 uma segunda vez sem mudanca de analise
   → **Expected**: artefato estavel — nenhuma entrada adicionada,
   removida ou duplicada (idempotencia real, nao apenas primeira
   re-execucao).

---

## Cenario 8 — Cruzamento de portfolio no review-features (FR-006)

1. Roadmap com 3 entradas; `docs/specs/a-um/` existente **sem**
   `tasks.md`; `docs/specs/b-dois/` com `tasks.md` sem pendentes;
   `c-tres` sem diretorio.
2. `roadmap-status.sh`
   → **Expected**: `a-um` = `em-andamento` (este e o caso que
   `aggregate.sh` sozinho nao enxerga), `b-dois` = `concluida`,
   `c-tres` = `nao-iniciada`; linhas na ordem do roadmap.
3. `roadmap-status.sh --json`
   → **Expected**: uma linha JSON por entrada, parseavel.
4. `roadmap-status.sh` com `docs/roadmap.md` ausente
   → **Expected**: exit 1 com diagnostico — e o `review-features`, que o
   chama best-effort, produz o relatorio atual sem secao de roadmap e
   sem falhar.
5. Rodar `review-features` num projeto **sem** roadmap
   → **Expected**: relatorio identico ao atual (zero regressao).

---

## Cenario 9 — Roadmap de entrada unica (edge case, FR-007)

1. Gerar roadmap que resulta em 1 unica entrada.
2. Inspecionar artefato e relatorio
   → **Expected**: roadmap valido (1 entrada e valido); o relatorio
   sugere **explicitamente** que o operador considere a pipeline
   completa, ja que a feature unica equivale ao projeto.

---

## Cenario 10 — Avanco de onda respeita o modo (FR-002)

1. Estado em modo roadmap, fase corrente `constitution`.
2. `state-ondas.sh end --motivo-termino etapa_concluida_avancando
   --advance --mode roadmap`
   → **Expected**: `current_stage` = `roadmap`, `next_instruction`
   coerente — **nao** `specify`.
3. Mesmo comando **sem** `--mode`
   → **Expected**: `specify` (comportamento atual preservado).
4. `--mode roadmap` **sem** `--advance`
   → **Expected**: exit 2 (mesma politica de `--terminal-phase` e
   `--advance-from`).
5. Estado em fase `roadmap`, tentar
   `end --advance --terminal-phase roadmap`
   → **Expected**: exit 2 fail-closed, com a mensagem existente
   orientando `--motivo-termino concluido` + promocao de status.

---

## Cenario 11 — Validacao fail-closed no consumidor (seguranca H2) `[CRITICO]`

Exercita um `docs/roadmap.md` que **nunca passou** pelo gate de
conclusao (editado a mao / vindo de merge).

1. Roadmap com `- **depende-de**: ` seguido de texto arbitrario
   (ex.: `../../etc`, `a; rm -rf /`, valor com `"` e `\`)
   → **Expected**: `roadmap-status.sh` descarta o token invalido, avisa
   em stderr, e **nunca** emite o valor bruto na saida.
2. Roadmap com `short-name` de 100k caracteres
   → **Expected**: entrada descartada (limite 64), aviso; sem varredura
   de diretorio com o valor.
3. Roadmap com `depende-de` contendo `|`
   → **Expected**: saida markdown com o `|` sanitizado; tabela nao
   quebra nem ganha coluna.
4. Roadmap com `depende-de` contendo `"` e `\`, com `--json`
   → **Expected**: cada linha JSON permanece parseavel (escape
   aplicado).
5. Roadmap presente mas estruturalmente invalido
   → **Expected**: exit 3 (distinto de exit 1 = ausente), com aviso —
   corrupcao nao some em silencio do relatorio.
6. `--stage roadmap` **sem** `--mode roadmap` em `detect-completion`
   → **Expected**: continua invalido (a lista global nao foi alargada).

---

## Cenario 12 — Ordem do finalize vs promocao terminal (seguranca M1) `[CRITICO]`

1. Execucao em modo roadmap com atomic-commit habilitado, concluindo a
   etapa `roadmap`.
2. Inspecionar a ordem das operacoes
   → **Expected**: `commit-mode.sh finalize` (push + PR) ocorre
   **antes** da promocao de status terminal.
3. Verificar o estado no instante do `finalize`
   → **Expected**: status ainda **nao** terminal — logo a guarda
   enforced de Bash esta ATIVA durante o `git push`.
4. Tentativa de mutar o modo em execucao ja alem de `constitution`
   (`roadmap-mode.sh set-enabled`)
   → **Expected**: exit 2, estado inalterado (flag write-once).

---

## Nota sobre roundtrip End-to-End backend↔frontend

**N/A** — a feature nao tem borda backend↔frontend. Ver
`plan.md` §Convencoes de Borda.
