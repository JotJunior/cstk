# Feature Specification: Testes automatizados para scripts shell

**Feature**: `shell-scripts-tests`
**Created**: 2026-04-19
**Status**: Draft

## Contexto

O repositorio distribui skills que dependem de scripts shell POSIX para operacoes
deterministicas (geracao de IDs, scaffolding de docs, metricas, validacao). Esses
scripts rodam na maquina de centenas de usuarios, em shells diferentes (bash,
dash, zsh) e contra entrada de usuario imprevisivel.

Um bug recente em `metrics.sh` (tratamento incorreto de `grep -c` sem matches,
que gerou erro aritmetico "0 0: syntax error") chegou em producao porque nao
havia regressao automatizada. Essa feature existe para impedir que a mesma
classe de bug volte — e para dar confianca ao autor de que refatorar qualquer
script nao quebra integracoes downstream.

**Scripts atualmente cobertos pelo escopo**:

- `scaffold.sh` (initialize-docs)
- `next-uc-id.sh` (create-use-case)
- `next-task-id.sh` (create-tasks)
- `metrics.sh` (review-task)
- `validate.sh` (validate-docs-rendered)

## Clarifications

### Session 2026-04-19

- Q: Como reformular SC-005 para ser verificavel na implementacao? → A: Substituir por criterio de presenca — a suite contem testes nomeados que exercitariam cada classe de bug ja conhecida; verificavel via `tests/run.sh --list`.
- Q: Como a suite normal (sem `--check-coverage`) deve reagir a scripts orfaos (sem teste)? → A: Warning visivel no sumario, sem bloquear. Exit code 0 quando todos os testes existentes passam; orfaos continuam detectaveis mas nao impedem commit. `--check-coverage` permanece como modo estrito (exit 1 em orfao).
- Q: Como FR-005 (isolamento) deve tratar interrupcao externa (Ctrl+C, SIGTERM)? → A: Estender FR-005 para exigir limpeza tambem em caso de interrupcao, nao apenas em falha natural do teste.
- Q: Qual shell a suite exercita na primeira entrega? → A: Apenas `/bin/sh` do sistema (invocacao explicita via `sh script.sh`). Matriz multi-shell (bash/dash/zsh) fica como extensao futura, fora do escopo desta iteracao.
- Q: Como distinguir falha do script sob teste de falha do ambiente (ex: `awk`/`mktemp` ausente)? → A: Tres status distintos — PASS / FAIL / ERROR. FAIL = script comportou-se errado; ERROR = harness ou ambiente impediu avaliacao. Exit code 0 exige zero FAILs E zero ERRORs.

## User Scenarios & Testing

### User Story 1 — Rodar a suite antes de commitar (Priority: P1)

O mantenedor edita um script shell (ex: corrige um bug em `metrics.sh` ou
adiciona um flag em `scaffold.sh`). Antes de commitar, ele roda um unico
comando e recebe, em segundos, um relatorio que diz se TODOS os scripts
continuam funcionando nos cenarios esperados.

**Why this priority**: sem isto, nao ha feature. Um harness executavel +
cobertura de caminho feliz para todos os 5 scripts ja constitui MVP util.

**Independent Test**: rodar o comando unico de execucao, observar saida com
status por script, forcar uma falha plantada em um script qualquer e
confirmar que o relatorio marca aquele script como FAIL.

**Acceptance Scenarios**:

1. **Given** a suite e o estado atual dos scripts, **When** o mantenedor
   executa o comando de entrada, **Then** ele ve status `PASS` para cada um
   dos 5 scripts e exit code 0.
2. **Given** um bug plantado em qualquer script, **When** a suite roda,
   **Then** ela reporta qual script falhou, em qual cenario, com exit code
   diferente de 0.
3. **Given** execucao da suite, **When** ela termina, **Then** o tempo total
   decorrido e exibido e deve ser curto o bastante para rodar manualmente
   entre edicoes (cadencia de pre-commit).

---

### User Story 2 — Capturar regressoes conhecidas (Priority: P1)

Quando um bug e corrigido em um script, um teste de regressao especifico
daquele bug entra na suite. O bug do `metrics.sh` (tasks.md sem nenhum
checkbox ou sem checkboxes de algum tipo) e a primeira regressao
obrigatoria.

**Why this priority**: o pedido nasceu de um bug real em producao. Se a suite
nao protege contra ele, nao cumpre o proposito. Tambem P1 porque define o
padrao de como novos bugs serao incorporados no futuro.

**Independent Test**: reverter o fix de `metrics.sh` temporariamente e rodar
a suite — ela deve falhar. Restaurar o fix — ela deve passar.

**Acceptance Scenarios**:

1. **Given** um `tasks.md` sem nenhum checkbox, **When** `metrics.sh` roda,
   **Then** a saida e valida (nao ha erro aritmetico) e o total de subtarefas
   e reportado como 0.
2. **Given** um `tasks.md` com apenas checkboxes concluidos ([x]), **When**
   `metrics.sh` roda, **Then** o pct_done e 100 e nenhum contador e vazio.
3. **Given** um `tasks.md` com uma fase sem subtarefas marcadas ainda,
   **When** `metrics.sh` roda, **Then** os contadores ausentes viram 0 sem
   quebrar o JSON de saida.

---

### User Story 3 — Cobertura de caminhos de erro e entradas invalidas (Priority: P2)

Scripts precisam se comportar previsivelmente quando recebem entrada ruim
(arquivo inexistente, argumento faltando, diretorio errado). A suite
documenta e exercita essas saidas de erro.

**Why this priority**: caminhos de erro sao a segunda classe mais comum de
regressao silenciosa em shell. Vir depois do caminho feliz porque nao bloqueia
MVP, mas e necessario antes de considerar a suite "completa".

**Independent Test**: para cada script, rodar com: (a) sem argumentos, (b)
com caminho inexistente, (c) com argumento em formato errado. Em todos os
casos, o script deve sair com mensagem de erro legivel e exit code !=0.

**Acceptance Scenarios**:

1. **Given** `next-uc-id.sh AUTH --dir=/diretorio/que-nao-existe`, **When** o
   script roda, **Then** ele sai com erro descritivo e codigo !=0 (nao crasha
   com stacktrace de shell).
2. **Given** `next-task-id.sh` sem argumentos, **When** executado, **Then**
   ele imprime mensagem de uso e sai com codigo !=0.
3. **Given** `metrics.sh` apontando para arquivo inexistente, **When**
   executado, **Then** a mensagem e clara sobre o arquivo faltando.
4. **Given** `scaffold.sh --dry-run` em um diretorio sem permissao de escrita,
   **When** executado, **Then** ele nao altera nada e imprime o plano.

---

### User Story 4 — Isolamento e reprodutibilidade dos testes (Priority: P2)

Cada teste roda em um diretorio temporario proprio e nao deixa residuo no
repositorio nem depende de ordem de execucao. Rodar a suite duas vezes
seguidas produz o mesmo resultado. Rodar subconjunto da suite produz o
mesmo veredito sobre aqueles testes.

**Why this priority**: sem isolamento, bugs de "passa no meu ambiente" vao
aparecer. P2 e nao P1 porque o MVP da P1 pode ser feito com fixtures
estaticas read-only e ja entrega valor — isolamento full fica para quando
adicionarmos testes que escrevem arquivos (ex: `scaffold.sh`).

**Independent Test**: rodar a suite duas vezes consecutivas sem alterar
nada; ambas devem produzir identicamente `PASS`. Verificar que o `git
status` continua limpo depois das execucoes.

**Acceptance Scenarios**:

1. **Given** duas execucoes consecutivas da suite, **When** comparadas,
   **Then** o resultado e identico.
2. **Given** a suite executada, **When** o usuario roda `git status`,
   **Then** nenhum arquivo novo ou modificado aparece no working tree.
3. **Given** apenas o subconjunto de testes de `metrics.sh`, **When**
   executado isoladamente, **Then** o veredito sobre esses testes e o mesmo
   que apareceria na suite completa.

---

### User Story 5 — Governanca: todo script novo vem com teste (Priority: P3)

Quando o autor adiciona um novo `.sh` no repositorio, o proprio projeto
lembra que um teste correspondente e obrigatorio. A ausencia e detectavel
automaticamente (ex: a suite lista scripts sem cobertura).

**Why this priority**: evita erosao do valor da suite com o tempo. Nao e
necessario para o MVP mas e o que mantem a feature viva nos proximos 12 meses.

**Independent Test**: adicionar um `.sh` stub em qualquer skill sem teste
correspondente; rodar a suite ou checagem de cobertura; ela deve avisar
que o script novo nao tem teste.

**Acceptance Scenarios**:

1. **Given** um script `.sh` novo sem teste associado, **When** a suite (ou
   um comando auxiliar) e executada, **Then** uma mensagem lista o script
   orfao.
2. **Given** um script `.sh` removido, **When** a suite roda, **Then** nao
   ha erro por testes apontando para script que nao existe mais (ou a
   remocao e reportada).

---

### Edge Cases

- O que acontece quando `tasks.md` tem checkboxes mas nenhum do tipo pendente
  `[ ]`? (o caso que expos o bug original)
- Como a suite reage a scripts que falham por razao do ambiente (ex: `awk`
  ausente em minimalismo extremo)? Deve distinguir falha de teste vs falha
  de pre-requisito.
- Scripts rodam em bash, dash e zsh — se um teste so passa em bash, isso
  deveria ser falha ou warning?
- Fixtures incluem caminhos com espacos? Arquivos com BOM UTF-8?
- O que acontece se o teste for interrompido no meio (Ctrl+C) — ele deixa
  tmpdir pendurado?
- Dois testes rodando em paralelo (se alguem experimentar paralelizar) —
  colidem em tmpdir?

## Requirements

### Functional Requirements

- **FR-001**: A suite DEVE incluir ao menos um teste automatizado para cada
  um dos 5 scripts `.sh` listados no Contexto.
- **FR-002**: A suite DEVE ser executavel via um unico comando de entrada, a
  partir da raiz do repositorio, sem passos de setup manual alem do que ja
  existe no ambiente padrao de um dev do projeto.
- **FR-003**: A saida da suite DEVE indicar, por script e por cenario, um
  dos tres status: **PASS** (cenario executou e expectativas bateram),
  **FAIL** (cenario executou mas o script sob teste comportou-se diferente
  do esperado), **ERROR** (o harness ou o ambiente impediu a avaliacao —
  ex: ferramenta POSIX ausente, falha ao criar tmpdir, setup do teste
  crashou). A suite DEVE encerrar com exit code 0 se e somente se zero
  cenarios resultaram em FAIL E zero resultaram em ERROR.
- **FR-004**: A suite DEVE incluir teste de regressao para o bug de
  `metrics.sh` em que `grep -c` sem matches gerava expressao aritmetica
  invalida (entradas: tasks.md sem checkboxes, tasks.md sem checkboxes de
  algum tipo especifico).
- **FR-005**: Cada teste DEVE rodar em ambiente isolado (diretorio
  temporario proprio), sem criar, modificar ou remover arquivos fora desse
  diretorio, e limpar apos execucao em qualquer condicao de termino:
  (a) execucao bem-sucedida, (b) falha natural do teste, (c) interrupcao
  externa (Ctrl+C / SIGINT, SIGTERM). Em nenhum desses casos o tmpdir
  deve permanecer no sistema apos o processo do teste encerrar.
- **FR-006**: A suite DEVE cobrir, para cada script, pelo menos: (a) caso
  feliz com entrada valida, (b) ausencia de argumento obrigatorio, (c)
  entrada invalida (arquivo/dir inexistente).
- **FR-007**: A suite DEVE ser determinista: duas execucoes consecutivas,
  sem alteracao de codigo ou ambiente, produzem exatamente o mesmo veredito.
- **FR-008**: A suite DEVE executar em tempo curto o suficiente para ser
  rodada manualmente entre edicoes, em cadencia de pre-commit (ver SC-003).
- **FR-009**: Adicionar um script `.sh` novo ao repositorio sem teste
  correspondente DEVE ser detectavel em dois niveis:
  (a) na execucao normal da suite, orfaos aparecem como warning no sumario
  final (`ORPHANS: N`) sem alterar o exit code — sao informativos, nao
  bloqueantes;
  (b) no modo explicito `--check-coverage`, a presenca de qualquer orfao
  sai com exit code diferente de zero, servindo como gate estrito quando
  o mantenedor quiser forcar cobertura total. Remocao de um script com
  teste orfao (teste apontando para arquivo inexistente) tambem DEVE ser
  reportada nos dois modos.
- **FR-010**: Fixtures usadas pelos testes DEVEM ser versionadas junto da
  suite (nao baixadas em tempo de execucao), para que a suite funcione
  offline e sem dependencia externa.
- **FR-011**: Mensagens de falha DEVEM mostrar, no minimo, o script, o
  cenario, o comando executado, stdout e stderr capturados, exit code
  observado, expectativa violada, e — quando o status for ERROR — a causa
  do erro de ambiente (ex: "mktemp nao encontrado no PATH"). O conjunto
  deve ser suficiente para o mantenedor reproduzir sem anexar o debugger
  e diagnosticar se o problema e do script ou do ambiente.
- **FR-012**: A suite DEVE ser exclusivamente local nesta primeira entrega —
  rodada manualmente pelo mantenedor antes de commitar. Nao ha integracao
  automatica com CI remoto ou hooks de Git nesta iteracao. Se no futuro um
  CI for adicionado ao repositorio, a suite deve ser compativel com
  execucao em ambiente POSIX limpo (sem dependencias alem do que ja e
  requisito para desenvolvimento local).
- **FR-013**: Na iteracao 1, os testes DEVEM invocar os scripts sob teste
  explicitamente via `sh <script>` — ou seja, exercitam apenas o interpretador
  apontado por `/bin/sh` no sistema do mantenedor. Matriz multi-shell (rodar
  cada teste sob bash, dash, zsh separadamente) e explicitamente fora de
  escopo nesta iteracao; fica registrada como extensao futura acionavel via
  variavel de configuracao do runner sem reescrita do harness.

### Key Entities

- **Script sob teste**: um arquivo `.sh` no repositorio. Atributos
  relevantes: localizacao, contrato (argumentos aceitos, arquivos lidos,
  stdout/stderr/exit code).
- **Cenario de teste**: uma combinacao de (script, entrada, expectativa).
  Entrada inclui argumentos e fixtures. Expectativa inclui stdout, stderr,
  exit code e efeitos colaterais no sistema de arquivos.
- **Fixture**: conjunto minimo de arquivos de entrada necessarios para
  reproduzir um cenario (ex: um `tasks.md` com estrutura conhecida, um
  `docs/` com UCs ja numerados).
- **Relatorio de execucao**: saida consolidada da suite apos uma rodada —
  lista de scripts, status por cenario, tempo total, exit code.

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% dos scripts `.sh` atualmente no repositorio tem ao menos
  um cenario automatizado exercitando-os.
- **SC-002**: O bug historico de `metrics.sh` (tasks.md sem matches de grep)
  e detectado pela suite: se o fix for revertido, a suite falha com
  mensagem que aponta diretamente o cenario.
- **SC-003**: A suite completa termina em menos de 30 segundos em uma
  maquina de desenvolvimento tipica, para que o mantenedor a rode entre
  edicoes sem frustracao.
- **SC-004**: Em uma falha, 95% das vezes a mensagem do relatorio e
  suficiente para reproduzir o problema sem abrir o codigo do teste — ou
  seja, o mantenedor sabe qual comando rodar manualmente para ver o bug.
- **SC-005**: A suite contem, ao final da entrega, testes nomeados que
  exercitariam cada classe de bug ja conhecida: (a) mau tratamento de
  saida de `grep -c` sem matches (regressao historica de `metrics.sh`),
  (b) ausencia de argumento obrigatorio sem mensagem de uso clara.
  Verificavel imediatamente apos a entrega executando `tests/run.sh --list`
  e confirmando a presenca dos cenarios correspondentes.
- **SC-006**: Adicionar um script `.sh` novo sem teste correspondente e
  detectavel em menos de 1 minuto pelo mantenedor usando a suite ou o
  comando auxiliar de cobertura.
