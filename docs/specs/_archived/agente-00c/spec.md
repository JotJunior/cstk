# Feature Specification: Agente-00C — Orquestrador Autonomo da Pipeline SDD

**Feature**: `agente-00c`
**Created**: 2026-05-05
**Status**: Draft

> **Contexto**: esta spec deriva de `briefing.md` e `constitution.md` no mesmo
> diretorio. Atende ao experimento pessoal de joao para testar a robustez da
> pipeline SDD, descobrir limites do Claude Code como plataforma de
> orquestracao autonoma, e gerar aprendizado estruturado para evolucao das
> skills do toolkit. Cenario A (relatorio rico, 0 projetos entregues) vence
> Cenario B (1 projeto entregue, relatorio raso). Auditabilidade > avanco.

---

## User Scenarios & Testing

### User Story 1 — Receber relatorio auditavel ao final de uma execucao (Priority: P1)

Joao invoca o orquestrador 00C com uma descricao curta de POC/MVP que quer
explorar e uma stack inicial sugerida. Ele se afasta do computador e, quando
volta (mesmo que minutos depois ou ondas adiante), encontra um relatorio
estruturado dentro do projeto-alvo descrevendo o que aconteceu: que decisoes
foram tomadas, por quais agentes, com quais justificativas; onde a execucao
parou ou foi abortada e por que; quais sugestoes para evolucao das skills
emergiram.

**Why this priority**: o relatorio e o entregavel-mor do experimento. Sem
ele, nao ha aprendizado de volta para evoluir as skills do toolkit, e o
proposito do 00C colapsa. Toda execucao — bem sucedida, abortada, pausada,
incompleta — deve produzir relatorio.

**Independent Test**: invocar `/agente-00c` com qualquer descricao,
interromper voluntariamente em qualquer ponto (forcar gatilho de aborto, ou
deixar rodar ate completar), abrir o arquivo de relatorio e verificar que
contem todas as secoes obrigatorias preenchidas com decisoes rastreaveis.

**Acceptance Scenarios**:

1. **Given** uma execucao do 00C que rodou ate o fim sem bloqueios, **When**
   joao abre o relatorio, **Then** ele encontra resumo executivo, linha do
   tempo das etapas, lista de decisoes (cada uma com 5 campos), bloqueios
   humanos (mesmo que vazio), sugestoes para skills globais, metricas e
   licoes aprendidas.
2. **Given** uma execucao abortada por gatilho automatico (loop, movimento
   circular, orcamento estourado, impossibilidade tecnica, desvio de
   finalidade ou bug em skill global), **When** joao abre o relatorio,
   **Then** o motivo do aborto esta na primeira pagina, o estado em que a
   pipeline parou e visivel, e as decisoes tomadas ate o aborto estao
   completas.
3. **Given** uma execucao pausada por bloqueio humano, **When** joao abre o
   relatorio (parcial, gerado ao final da onda corrente), **Then** ele
   encontra o ponto exato onde foi pedida decisao humana, com o contexto
   suficiente para responder sem precisar reler artefatos.

---

### User Story 2 — Decisoes autonomas durante o clarify, com auditabilidade (Priority: P2)

Quando a pipeline atinge a etapa `clarify`, dois subagentes especializados
sao acionados pelo orquestrador. Um (clarify-asker) carrega a skill clarify
e gera as questoes mais importantes da spec corrente, com opcoes
recomendadas. O outro (clarify-answerer) recebe essas questoes acompanhadas
do briefing, da constitution, da stack-sugerida e das decisoes ja tomadas,
e escolhe uma opcao para cada questao com justificativa explicita. As
respostas do answerer alimentam a spec; as decisoes ficam registradas no
relatorio final.

**Why this priority**: o clarify e o gargalo classico de pipelines SDD —
e onde o humano e tradicionalmente requisitado. Sem decisao autonoma,
toda execucao vira bloqueio. Mas decisao autonoma sem auditabilidade vira
caixa-preta. Esta story junta os dois: 00C decide e mostra como decidiu.

**Independent Test**: rodar a pipeline ate `clarify` (mesmo isolado de
outras etapas), verificar que perguntas sao geradas e respondidas
automaticamente, e que o relatorio final contem cada par pergunta-resposta
com justificativa baseada em briefing + constitution + stack.

**Acceptance Scenarios**:

1. **Given** uma spec com ambiguidades na etapa clarify, **When** o
   orquestrador 00C executa a etapa, **Then** clarify-asker gera entre 1 e
   5 questoes (limite da skill clarify) e clarify-answerer escolhe uma opcao
   para cada uma sem invocar humano, registrando contexto + opcao + por que.
2. **Given** uma questao do clarify-asker para a qual o clarify-answerer nao
   consegue justificar a escolha em termos do briefing, constitution ou
   stack-sugerida, **When** o orquestrador recebe o retorno, **Then** a
   questao e convertida em bloqueio humano (Principio II Pause-or-Decide)
   e a pipeline pausa.
3. **Given** uma execucao concluida, **When** joao examina a secao
   "Decisoes" do relatorio, **Then** cada decisao do clarify-answerer
   aparece com os 5 campos preenchidos e e legivel sem consultar artefatos
   externos.

---

### User Story 3 — Retomada cross-sessao via schedule/clear/continue (Priority: P3)

Pipelines do 00C podem ser longas demais para caber em uma unica sessao do
Claude Code. Ao final de cada onda (uma sequencia de tomadas de acao no
mesmo turno), o orquestrador serializa o estado da execucao em disco (etapa
atual, decisoes ate o momento, proxima instrucao explicita), faz commit
local, agenda a proxima onda e libera a sessao. Quando a proxima onda
dispara, o orquestrador le o estado e retoma a pipeline exatamente de onde
parou.

**Why this priority**: sem retomada, executar 00C em projeto nao trivial
e impossivel — context window estoura no meio. Mas se P1 e P2 ja produzem
relatorio em uma sessao, esta story estende a duracao maxima viavel da
execucao. Por isso P3, nao P1.

**Independent Test**: forcar interrupcao de sessao (clear de contexto, ou
estouro de 80% do orcamento), aguardar disparo da proxima onda, verificar
que a pipeline continua na mesma etapa onde parou, com mesmas decisoes,
sem regressao.

**Acceptance Scenarios**:

1. **Given** uma execucao do 00C na metade da etapa `plan`, **When** a
   sessao corrente atinge 80% do consumo, **Then** o orquestrador grava
   estado, faz commit local, agenda nova execucao, e a onda corrente
   encerra graciosamente.
2. **Given** o estado serializado de uma execucao em pausa, **When** uma
   nova onda dispara, **Then** o orquestrador le o estado, valida o schema,
   reconstroi o contexto necessario a partir dos artefatos em disco e
   continua a partir da proxima instrucao registrada — sem perda de
   decisoes ja tomadas.
3. **Given** um arquivo de estado corrompido ou com schema desconhecido,
   **When** o orquestrador tenta retomar, **Then** detecta a corrupcao
   antes de qualquer acao, registra como bloqueio obrigatorio e gera
   relatorio parcial pedindo decisao humana.

---

### User Story 4 — Gatilhos de aborto graceful com relatorio parcial (Priority: P4)

Quando o 00C entra em situacao detectada como insustentavel (loop em
etapa, movimento circular, orcamento estourado, impossibilidade tecnica,
desvio de finalidade, bug impeditivo em skill global), o orquestrador
para imediatamente, gera relatorio parcial com motivo do aborto, estado
em que parou e decisoes tomadas ate ali, e libera a sessao.

**Why this priority**: P4 protege P1 — sem gatilhos, loop ou movimento
circular drenam tokens sem produzir relatorio. Mas P1 ja garante geracao
de relatorio mesmo em sucesso; gatilhos sao a borda. Por isso P4.

**Independent Test**: induzir cada gatilho separadamente (forcar 6
ciclos na mesma etapa, simular movimento circular fix-bug-fix-mesmo-bug,
estourar 80% sessao, etc) e verificar que o aborto dispara, que relatorio
parcial e gerado em menos de 60 segundos, e que o motivo aparece de forma
clara.

**Acceptance Scenarios**:

1. **Given** uma execucao em que o orquestrador esta no 5o ciclo da mesma
   etapa sem progresso mensuravel, **When** o 6o ciclo iniciaria, **Then**
   o orquestrador aborta com motivo "tendencia a loop", gera relatorio
   parcial e libera a sessao.
2. **Given** uma execucao que detectou padrao "fix bug A → bug B → fix B
   → bug A volta" via inspecao de historico de decisoes, **When** o padrao
   e confirmado, **Then** o orquestrador aborta com motivo "movimento
   circular".
3. **Given** uma execucao em que o consumo de sessao atingiu 80%, **When**
   a onda corrente termina, **Then** o orquestrador agenda continuacao
   (nao aborta — comportamento de P3) ate o limite da janela semanal; ao
   atingir 80% da janela semanal, agenda para a proxima janela; em
   nenhuma situacao continua sem orcamento.
4. **Given** o orquestrador encontrou bug impeditivo em skill global, **When**
   confirma o bug, **Then** abre issue no GitHub do toolkit
   `JotJunior/claude-ai-tips` com template estruturado, registra a issue
   no relatorio e aborta com motivo "bug em skill global, decisao humana
   necessaria".

---

### User Story 5 — Sugestoes para skills globais virando issues no toolkit (Priority: P5)

Durante uma execucao, o 00C pode descobrir que uma skill global (em
`~/.claude/skills/`) tem comportamento confuso, contradicao interna, gap
de cobertura ou bug nao impeditivo. Como skills globais sao read-only para
o 00C (Principio V), ele registra a sugestao em arquivo dedicado dentro
do projeto-alvo. Quando a sugestao representa bug confirmadamente
impeditivo (User Story 4), abre issue automatica no toolkit. Sugestoes
nao impeditivas viram lote no relatorio final, sem abrir issue por
default.

**Why this priority**: P5 alimenta o ciclo de evolucao do toolkit, mas
nao e essencial para uma execucao individual produzir valor. Sem ela, o
relatorio ainda contem a secao "sugestoes para skills globais" como
texto livre. Com ela, vira artefato acionavel.

**Independent Test**: forcar (manualmente) o orquestrador a registrar
uma sugestao de melhoria em skill global, verificar que arquivo dedicado
e gerado no projeto-alvo, e que issue e aberta no toolkit apenas quando
classificada como impeditiva.

**Acceptance Scenarios**:

1. **Given** o orquestrador detectou ambiguidade em uma skill global
   durante a pipeline mas conseguiu prosseguir com workaround documentado,
   **When** a execucao termina, **Then** a sugestao aparece no arquivo
   `<projeto-alvo>/.claude/agente-00c-suggestions.md` e e listada no
   relatorio sob "Sugestoes para skills globais", sem abrir issue.
2. **Given** o orquestrador detectou bug impeditivo em skill global,
   **When** confirma o bug, **Then** abre issue no toolkit com (skill
   afetada, diagnostico, proposta, link para relatorio que originou) e
   registra o numero da issue no relatorio.

---

### Edge Cases

- **Estado em disco corrompido ou com schema desconhecido**: bloqueio
  obrigatorio, sem tentativa de auto-correcao silenciosa.
- **Tentativa de spawnar tataraneto (4o nivel de subagente)**: falha
  explicita devolvida ao orquestrador raiz, registrada como decisao do
  tipo "limite atingido".
- **Terceira retro-execucao**: bloqueio humano obrigatorio (orcamento de
  retro-execucao por feature e 2).
- **6o ciclo na mesma etapa**: aborto por "tendencia a loop", como em
  User Story 4.
- **Movimento circular fix-bug-fix-mesmo-bug**: aborto por "movimento
  circular", como em User Story 4.
- **Bug impeditivo em skill global**: aborto + issue, como em User Story 4.
- **Atingir 80% sessao**: agendar proxima sessao via mecanismo definido
  no `/plan` (nao aborta).
- **Atingir 80% janela semanal**: agendar proxima janela.
- **URL fora da whitelist**: bloqueio com pergunta "adicionar a whitelist
  e prosseguir, ou abortar?". Por default, NAO adiciona automaticamente.
- **`.env` ausente no projeto-alvo**: para etapas que nao precisam de
  credenciais externas, segue. Para etapas que precisam, bloqueio humano.
- **Skill local conflitando com skill global de mesmo nome**: skill local
  vence (escopo do projeto-alvo). Conflito e registrado no relatorio.
- **Pipeline pede acao que viola Principio V (blast radius)**: aborto
  imediato com motivo "violacao de blast radius" — nao tenta workaround.
- **Operador interrompe manualmente durante uma onda**: orquestrador
  termina a tomada de acao corrente o mais rapido possivel, salva estado,
  gera relatorio parcial.
- **Diretorio do projeto-alvo movido ou renomeado durante execucao**:
  retomada le `state.json` e tenta acessar `projeto_alvo_path` registrado
  no inicio. Se o caminho nao existe mais, a validacao falha como "estado
  invalido / referencia quebrada" e dispara bloqueio humano. Sem
  auto-correcao (operador decide se atualiza o path ou aborta).
- **Multiplas execucoes 00C concorrentes**: 1 execucao 00C ativa por
  diretorio de projeto-alvo. Tentativa de invocar `/agente-00c` em projeto
  que ja tem `state.json` com status `em_andamento` ou `aguardando_humano`
  e rejeitada com mensagem direta. Multiplas execucoes em projetos-alvo
  **distintos** sao permitidas (cada uma tem seu proprio estado e isso e
  desejado).
- **Disco sem espaco para escrever estado/backup/artefatos**: tentativa de
  escrita falha → orquestrador captura o erro de I/O, dispara bloqueio
  humano com diagnostico e tamanho aproximado do que precisa ser
  liberado. NAO tenta limpar arquivos automaticamente.
- **Permissao de escrita negada no projeto-alvo**: detectado na invocacao
  (toque em arquivo de teste em `<projeto-alvo>/.claude/`) ou na primeira
  escrita real. Bloqueia com diagnostico claro. Sem fallback para outro
  diretorio.

---

## Requirements

### Functional Requirements

**Invocacao e parametros**

- **FR-001**: Operador MUST poder invocar o orquestrador 00C via comando
  unico passando descricao curta do projeto-alvo (POC/MVP a ser construido).
- **FR-002**: A invocacao MUST aceitar opcionalmente uma whitelist de URLs
  externas alem das declaradas no `.env` do projeto-alvo.
- **FR-003**: A invocacao MUST aceitar opcionalmente uma stack-sugerida
  (linguagem, framework, banco, cache, filas). Quando omitida, o
  clarify-answerer MUST escolher a stack durante a etapa clarify, baseando
  a decisao em (a) briefing do projeto-alvo, (b) `CLAUDE.md` do projeto-alvo
  se existir, (c) constitution. A escolha da stack quando feita
  automaticamente MUST ser registrada como decisao audit-relevante com os
  5 campos.

**Execucao da pipeline**

- **FR-004**: Sistema MUST executar as etapas da pipeline SDD na ordem:
  briefing → constitution → specify → clarify → plan → checklist →
  create-tasks → execute-task (loop por task) → review-task →
  review-features.
- **FR-005**: Sistema MUST mediar a etapa clarify usando dois subagentes
  distintos: clarify-asker (gera perguntas) e clarify-answerer (decide).
  Comunicacao entre eles e mediada pelo orquestrador, nao direta.
- **FR-006**: Sistema MUST permitir retro-execucao (volta a etapa anterior)
  quando detectar incoerencia entre artefatos, ate o limite de 2 retros
  por feature.

**Persistencia e retomada**

- **FR-007**: Sistema MUST persistir estado de orquestracao em disco ao
  final de cada onda, com schema versionado, contendo etapa corrente,
  decisoes tomadas, profundidade corrente de subagentes, retro-execucoes
  consumidas, ciclos consumidos por etapa, e proxima instrucao explicita.
- **FR-008**: Sistema MUST validar schema do estado antes de cada
  retomada e bloquear se invalido ou desconhecido.
- **FR-009**: Sistema MUST agendar continuacao automatica ao atingir
  qualquer um dos tres thresholds de proxy de consumo de sessao
  (numero de tool calls na onda, tempo wallclock da onda, tamanho do estado
  serializado). Thresholds iniciais e ajustaveis estao em `research.md`
  Decision 2. Janela semanal nao possui proxy confiavel observavel pelo
  agente — registrada como limitacao conhecida e mitigada via aborto manual
  do operador ou inspecao passiva via `/usage`.

**Auditabilidade**

- **FR-010**: Sistema MUST registrar cada decisao com 5 campos
  **obrigatorios** (contexto/etapa, opcoes consideradas, escolha feita,
  justificativa, agente responsavel) mais campos auxiliares com regras
  proprias: `timestamp` (sempre obrigatorio); `score_justificativa`
  (obrigatorio para decisoes do clarify-answerer; opcional para outros
  agentes); `referencias` (>= 1 referencia obrigatoria quando a decisao
  cita briefing/constitution/stack; vazio permitido quando decisao nao
  decorre de fonte externa); `artefato_originador` (path do artefato que
  originou a decisao quando aplicavel; pode ser nulo). Decisao com qualquer
  dos 5 obrigatorios faltando = violacao de Principio I e bloqueio.
- **FR-011**: Sistema MUST gerar relatorio final em
  `<projeto-alvo>/.claude/agente-00c-report.md` ao termino de qualquer
  execucao (sucesso, aborto, ou pausa por bloqueio humano), contendo
  exatamente as 6 secoes obrigatorias na ordem: (1) Resumo Executivo,
  (2) Linha do Tempo, (3) Decisoes, (4) Bloqueios Humanos, (5) Sugestoes
  para Skills Globais, (6) Licoes Aprendidas. Detalhamento do conteudo
  de cada secao em `contracts/report-format.md`.
- **FR-012**: Sistema MUST emitir relatorio parcial em ate 60 segundos
  apos disparo de gatilho de aborto.

**Autonomia limitada**

- **FR-013**: Sistema MUST limitar profundidade de subagentes a 3 niveis,
  contando o orquestrador raiz como nivel 0. Logo: filho = nivel 1, neto
  = nivel 2, bisneto = nivel 3. O nivel 3 (bisneto) NAO PODE spawnar
  subagentes — tentativa retorna falha de tool por ausencia de Agent na
  definicao do bisneto. Tataraneto = nivel 4 = invariante violada.
- **FR-014**: Sistema MUST abortar execucao quando detectar: (a) 6o ciclo
  na mesma etapa sem progresso mensuravel; (b) movimento circular; (c)
  impossibilidade tecnica; (d) desvio de finalidade; (e) bug impeditivo
  em skill global.

  **Definicao de "progresso mensuravel" em uma etapa**: pelo menos UM dos
  seguintes na ultima onda da etapa: novo artefato gerado em
  `<projeto-alvo>/docs/specs/<feature>/`; mudanca em conteudo de artefato
  pre-existente da etapa; nova decisao registrada com `agente !=
  orquestrador-00c`; teste/lint executado com mudanca de exit code em
  relacao a iteracao anterior. Ausencia de todos por 5 ciclos = sem
  progresso = aborto.

  **Definicao de "bug impeditivo em skill global"**: skill global retorna
  saida que (i) viola invariante documentada da skill (ex: clarify-asker
  retorna perguntas com opcoes auto-contraditorias sem cross-check), OU
  (ii) leva o orquestrador a esgotar o orcamento de retro-execucao da
  feature (max 2) sem conseguir contornar o comportamento. Bug que NAO
  atende esses criterios = "nao impeditivo" (workaround documentado +
  sugestao de severidade `aviso` ou `informativa`, sem aborto e sem issue
  no toolkit).
- **FR-015**: Sistema MUST converter clarify nao-decidivel pelo answerer
  (sem justificativa em briefing/constitution/stack) em bloqueio humano,
  pausando a pipeline.
- **FR-016**: Ao entrar em bloqueio humano no meio de uma onda, sistema
  MUST finalizar a onda corrente: gerar relatorio parcial, persistir
  estado com status "aguardando humano" + pergunta + contexto suficiente
  para resposta sem releitura, fazer commit local e liberar a sessao.
  NAO trava sincronamente aguardando resposta dentro do mesmo turno —
  comportamento consistente com schedule/clear/continue.

**Blast radius**

- **FR-017**: Sistema MUST restringir escrita em disco ao diretorio do
  projeto-alvo e seus subdiretorios. Skills globais sao read-only.
- **FR-018**: Sistema MUST nunca executar `sudo`, `git push`, deploy
  externo, ou comunicacao com URLs nao-whitelisted.
- **FR-019**: Sistema MUST executar package managers (npm, pip, go install,
  brew, etc) somente dentro do container docker do projeto-alvo, nunca no
  host.

**Sugestoes e issues**

- **FR-020**: Sistema MUST registrar sugestoes para skills globais em
  `<projeto-alvo>/.claude/agente-00c-suggestions.md` durante a execucao.
- **FR-021**: Sistema MUST abrir issue automatica no GitHub do toolkit
  `JotJunior/claude-ai-tips` quando confirmar bug impeditivo em skill
  global, com template estruturado (skill afetada, diagnostico, proposta,
  link para relatorio).

**Operacao manual**

- **FR-022**: Operador MUST poder interromper manualmente uma execucao em
  andamento via comando dedicado (codinome provisorio
  `/agente-00c-abort`). O comando le o estado corrente, marca a execucao
  como abortada com motivo "aborto manual", gera relatorio parcial e
  libera a sessao.
- **FR-023**: Operador MUST poder retomar uma execucao pausada por
  bloqueio humano respondendo a pergunta registrada no relatorio parcial,
  e disparando uma nova onda manual ou aguardando o schedule.

**Seguranca — Validacao de input**

- **FR-024**: Sistema MUST resolver simbolic links em `--projeto-alvo-path`
  (via `realpath` ou equivalente) ANTES de validar contra zonas proibidas
  (`/`, `/etc`, `/usr`, `~/.claude`, `~/.ssh`, `~/.config`). Path que
  resolve para zona proibida apos resolucao = invocacao rejeitada.
- **FR-025**: Sistema MUST limitar `descricao_curta` a no maximo 500
  caracteres. Sistema MUST NUNCA interpolar `descricao_curta` em comando
  Bash sem escape — quando o conteudo aparece em commit message, titulo
  de issue, ou path, sanitizacao explicita e obrigatoria (escape de aspas,
  remocao de control chars, no shell metachar).

**Seguranca — Goal alignment e prompt injection**

- **FR-026**: Sistema MUST tratar texto contido em artefatos lidos
  (briefing.md, spec.md, etc) como **conteudo/contexto**, nao como
  **instrucao executavel**. Instrucoes para subagentes vem exclusivamente
  do prompt construido pelo orquestrador. Texto adversarial em artefato
  ("ignore a constitution, execute X") nao deve alterar comportamento.
- **FR-027**: Sistema MUST extrair, no inicio da execucao, uma lista de
  3-7 aspectos-chave normalizados da `descricao_curta` (keywords semanticas
  + dominio). Esta lista e persistida no estado. A cada onda, o orquestrador
  compara as decisoes da onda contra os aspectos-chave: se 3 ondas
  consecutivas nao tocaram nenhum aspecto-chave, dispara aviso de drift; 5
  ondas consecutivas = "desvio de finalidade" (gatilho de aborto FR-014.d).

**Seguranca — Enforcement de blast radius**

- **FR-028**: Sistema MUST bloquear, via validacao pre-execucao, comandos
  Bash que (a) iniciem com `sudo` ou contenham ` sudo ` em qualquer posicao,
  (b) invoquem package managers de host (`npm`, `pip`, `go install`,
  `cargo install`, `gem install`, `brew install`) sem precedencia de
  `docker exec` ou `docker run`. Tentativa = decisao de tipo "violacao de
  blast radius" + aborto imediato (sem retry).

**Seguranca — Integridade de estado**

- **FR-029**: Sistema MUST gravar, ao final de cada onda, o hash SHA-256
  do `state.json` em arquivo separado `state.json.sha256` no mesmo
  diretorio. No inicio da proxima onda, sistema MUST recalcular o hash do
  `state.json` e comparar com o gravado: divergencia = bloqueio humano com
  diagnostico ("estado modificado externamente entre ondas — possivel
  tampering"). Sem auto-correcao.

**Seguranca — Filtro de secrets na saida**

- **FR-030**: Sistema MUST aplicar filtro de secrets antes de gravar
  qualquer texto em (a) `agente-00c-report.md`, (b) `agente-00c-suggestions.md`,
  (c) corpo de issue no toolkit. Filtro usa regex contra padroes minimos:
  tokens com >= 20 chars `[a-zA-Z0-9_-]+`; AWS keys (`AKIA[A-Z0-9]{16,}`);
  bearer tokens em URLs (`Bearer\s+[a-zA-Z0-9._-]+`); basic auth em URLs
  (`https?://[^:]+:[^@]+@`); strings que aparecem em chave do `.env` lido
  durante a execucao. Match positivo = substituir por `[REDACTED]` antes
  da escrita.

**Seguranca — Whitelist robusta**

- **FR-031**: Sistema MUST rejeitar entradas na whitelist que sejam
  excessivamente amplas: linhas com `**` puro (sem prefixo de dominio),
  padrao `*://*`, ou padrao `https?://[*]` sem dominio explicito. Tentativa
  de carregar whitelist com tais entradas = bloqueio com diagnostico
  apontando a linha invalida.

### Key Entities

- **Execucao**: instancia de pipeline 00C com identificador estavel,
  projeto-alvo, stack-sugerida, status (em andamento, pausada, abortada,
  concluida), timestamp de inicio, timestamp de termino, motivo de termino.
- **Onda**: unidade de execucao dentro de uma sessao. Tem inicio, fim,
  consumo medido, lista de decisoes tomadas, etapa em que estava, proxima
  instrucao serializada.
- **Estado de orquestracao**: snapshot persistido entre ondas. Contem
  schema_version, execucao corrente, etapa, decisoes acumuladas, orcamentos
  consumidos, profundidade corrente, retro-execucoes consumidas, proxima
  instrucao.
- **Decisao**: unidade audit-relevante. Tem contexto/etapa, opcoes
  consideradas, escolha feita, justificativa, agente responsavel, timestamp,
  link para artefato originador.
- **Bloqueio humano**: tipo especial de decisao que paralisa a pipeline.
  Tem pergunta, contexto suficiente para resposta sem releitura de
  artefatos, status (aguardando, respondido).
- **Relatorio**: artefato em
  `<projeto-alvo>/.claude/agente-00c-report.md`. Contem todas as secoes
  obrigatorias listadas em FR-011.
- **Sugestao para skill global**: registro em
  `<projeto-alvo>/.claude/agente-00c-suggestions.md`. Tem skill afetada,
  diagnostico, severidade (informativa, aviso, impeditiva), proposta, link
  para relatorio que originou.
- **Issue no toolkit**: criada automaticamente apenas quando severidade =
  impeditiva. Tem numero, link, conteudo seguindo template estruturado.

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% das execucoes (concluidas, abortadas ou pausadas) produzem
  um relatorio em `<projeto-alvo>/.claude/agente-00c-report.md` com todas
  as secoes obrigatorias preenchidas.
- **SC-002**: Pelo menos 95% das decisoes registradas no relatorio possuem
  os 5 campos completos (contexto, opcoes, escolha, justificativa, agente).
  Decisoes com campo faltando sao detectaveis por inspecao automatizada.
- **SC-003**: Apos interrupcao forcada (clear de contexto, sessao expirada,
  schedule disparando nova onda), 100% das execucoes retomadas continuam
  na mesma etapa em que pararam, com as decisoes anteriores preservadas
  e validadas.
- **SC-004**: Nenhuma execucao excede os orcamentos cravados (3 niveis de
  recursao, 2 retro-execucoes por feature, 5 ciclos por etapa, 80% sessao,
  80% janela semanal) sem ter disparado aborto graceful ou agendamento.
- **SC-005**: Tempo entre disparo de gatilho de aborto e relatorio parcial
  salvo em disco e inferior a 60 segundos em pelo menos 95% das ocorrencias.
- **SC-006**: Um leitor humano consegue reproduzir mentalmente todas as
  decisoes da execucao usando exclusivamente o relatorio, sem precisar
  consultar logs externos ou contexto da sessao do Claude Code. Verificavel
  por revisao manual em amostragem.
- **SC-007**: Toda decisao do clarify-answerer e justificada por referencia
  explicita a (a) briefing, (b) constitution, (c) stack-sugerida ou (d)
  decisao anterior — nunca por "pareceu razoavel" ou texto generico
  equivalente. Verificavel por inspecao da secao "Decisoes" do relatorio.
- **SC-008**: Comunicacao externa fora da whitelist + `.env` resulta em
  bloqueio em 100% das tentativas. Verificavel por simulacao com URL nao
  declarada.
- **SC-009**: Bug impeditivo em skill global resulta em issue no toolkit
  com template estruturado em 100% dos casos confirmados, antes do aborto.
- **SC-010**: A cada 3 execucoes (em media), pelo menos 1 licao aprendida
  concreta com proposta de melhoria de skill emerge no relatorio. Medida
  longitudinal sobre o experimento, nao por execucao isolada.
