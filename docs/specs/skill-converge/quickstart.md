# Quickstart: Skill Converge

Cenários que validam a implementação end-to-end. Um por fluxo crítico
(happy path + error cases + idempotência). Alinhados aos Acceptance Scenarios
da spec e aos Success Criteria (SC-001..SC-006).

> **Roundtrip backend↔frontend**: **N/A — single-layer**. `converge` é uma
> skill POSIX local read-only sobre artefatos de arquivo; não há borda de rede,
> DTO ou payload. O §5.4 "Convenções de Borda" do plan também é N/A por isso.

---

## Scenario 1: Detecção — path declarado que não existe (Happy Path, US1/AC2)

1. Preparar uma feature com `spec.md` + `tasks.md`, onde `tasks.md` referencia
   `scripts/foo.sh` que **não** existe no repositório.
2. Rodar `converge` standalone apontando para o diretório da feature.
3. **Expected**: o report aponta `scripts/foo.sh` como achado `type=missing`,
   citando o path exato e a task/FR de origem. Uma FASE de convergência é
   apendada ao final do `tasks.md` com uma tarefa `- [ ]` para esse gap.

## Scenario 2: Feature fielmente implementada → zero acionáveis (US1/AC1, SC-001)

1. Feature cujo código implementa fielmente todas as tasks marcadas `[x]`.
2. Rodar `converge`.
3. **Expected**: report com zero achados `CRITICAL`/`HIGH` acionáveis;
   **nenhuma** FASE de convergência apendada (FR-010); `tasks.md` inalterado.

## Scenario 3: Classificação por tipo (US2/AC1-4)

1. Preparar 4 paths: um ausente (`missing`), um parcialmente implementado
   (`partial`), um cujo comportamento contradiz a task (`contradicts`), um com
   código sem pedido correspondente na spec (`unrequested`).
2. Rodar `converge`.
3. **Expected**: cada achado recebe exatamente o tipo correto; o `unrequested`
   vira tarefa `kind=revisar` (não "implementar", FR-013).

## Scenario 4: Severidade CRITICAL por violação de MUST (US2/AC5, SC-002)

1. Um path declarado contém um script que **não é POSIX sh puro** (viola
   Constitution II — `MUST`/`NON-NEGOTIABLE`).
2. Rodar `converge` com `constitution.md` presente no projeto.
3. **Expected**: o achado recebe `severity=CRITICAL`, distinto dos demais,
   independente do tipo de gap. 100% dos achados que violam `MUST` são
   `CRITICAL` (nenhum rebaixado).

## Scenario 5: Severidade derivada da prioridade da story (US2, FR-020)

1. Achado `missing` ligado a uma User Story `P1`; outro `missing` ligado a `P3`.
2. Rodar `converge` (sem violação de `MUST`).
3. **Expected**: o primeiro recebe `HIGH`, o segundo `MEDIUM` — derivado da
   `Priority` da story de origem em `spec.md`.

## Scenario 6: Append-only preserva backlog existente (US3/AC1-2, SC-005)

1. `tasks.md` com fases/tarefas pré-existentes numeradas.
2. Rodar `converge` num estado com ≥1 gap acionável.
3. **Expected**: nova FASE numerada em sequência (`max+1`) apendada ao final;
   **nenhum** número/texto de fase ou tarefa pré-existente é alterado — `diff`
   antes/depois mostra apenas conteúdo adicionado.

## Scenario 7: Idempotência byte-a-byte (US4/AC1, SC-003) — CRÍTICO

1. Rodar `converge` sobre uma feature; capturar `tasks.md` (cópia A).
2. **Sem alterar nenhum arquivo de código**, rodar `converge` de novo;
   capturar `tasks.md` (cópia B).
3. **Expected**: `cmp A B` (ou `diff A B`) retorna **idêntico** — zero bytes de
   diferença. Nenhuma fase de convergência duplicada.

## Scenario 8: Dedup de gap já registrado (US4/AC2, FR-012)

1. Feature cuja última fase de convergência já contém uma tarefa para um gap
   específico ainda não resolvido.
2. Rodar `converge` de novo sobre o mesmo estado de código.
3. **Expected**: o gap é reconhecido pela `converge-key` (path+tipo+origem) já
   presente; **não** é duplicado numa nova fase.

## Scenario 9 (Error): abortar quando artefato ausente (US1/AC3, FR-017)

1. Diretório de feature **sem** `tasks.md` (ou sem `spec.md`).
2. Rodar `converge`.
3. **Expected**: a skill **aborta** com mensagem indicando qual artefato falta
   e qual comando o gera (`/specify` ou `/create-tasks`) — sem tentar adivinhar
   conteúdo. Exit não-zero.

## Scenario 10 (Error): path fora do projeto-alvo (Edge Case, FR-018)

1. `tasks.md` referencia um path que resolve para **fora** do diretório do
   projeto-alvo (ex.: `../../etc/passwd`).
2. Rodar `converge`.
3. **Expected**: o path é reportado como `missing`/inconclusivo e o arquivo
   **não** é lido (blast radius contido). `path-contains.sh` retorna exit 1
   para esse path.

## Scenario 11: Integração autônoma — gate antes de review-task (US5/AC1-2)

1. Execução `feature-00c` que concluiu todas as tasks da onda em `execute-task`.
2. Observar a transição de etapa (sem intervenção manual).
3. **Expected**: `converge` roda automaticamente **antes** de `review-task`;
   um achado `CRITICAL` fica registrado como Decisão auditável no `state.json`
   (via `state-decisions.sh register` + `record-skill`); o orquestrador decide
   se escala para bloqueio humano (converge não trava sozinho — FR-019).

## Scenario 12: Standalone sem orquestrador (SC-006)

1. Nenhuma execução `agente-00c`/`feature-00c` ativa (sem `state.json`).
2. Rodar `converge` direto sobre uma feature.
3. **Expected**: a skill completa e apresenta o report sem exigir orquestrador;
   nenhuma tentativa de escrever `state.json`.
