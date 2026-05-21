<!--
Sync Impact Report
- Version: (none) -> 1.0.0  [initial ratification, feature-scoped]
- Bump rationale: constituicao feature-scoped inexistente antes; criacao inicial
  versao 1.0.0 derivada do briefing em docs/specs/agente-00c/briefing.md.
- Escopo: principios operacionais do orquestrador autonomo agente-00C. SUBORDINADA
  a docs/constitution.md (toolkit constitution v1.1.0). Em qualquer conflito entre
  esta constitution e a do toolkit, prevalece a do toolkit.
- Principios criados (1.0.0):
  I.   Auditabilidade Total (NON-NEGOTIABLE)
  II.  Pause-or-Decide (NON-NEGOTIABLE)
  III. Idempotencia de Retomada (NON-NEGOTIABLE)
  IV.  Autonomia Limitada com Gatilhos de Aborto (NON-NEGOTIABLE)
  V.   Blast Radius Confinado (NON-NEGOTIABLE)
- Secoes adicionadas (1.0.0): Quality Standards, Decision Framework, Governance
- Artefatos que precisam atualizacao: nenhum ainda — briefing acabou de ser ratificado;
  spec.md, plan.md, tasks.md serao gerados ja respeitando esta constitution.
- TODOs pendentes: nenhum bloqueante. Itens em "Itens a Definir" do briefing serao
  endereçados em /plan, nao aqui.
-->

# Agente-00C Feature Constitution

Principios imutaveis que governam o desenho e a execucao do agente-00C —
orquestrador autonomo da pipeline SDD. Derivados do briefing em
`docs/specs/agente-00c/briefing.md`. Esta constituicao e
**feature-scoped**: complementa a [constituicao do toolkit](../../constitution.md)
v1.1.0 com regras especificas de orquestracao autonoma. **Em qualquer conflito,
a constituicao do toolkit prevalece.** Violacoes desta constituicao sao
bloqueantes em `/plan` e `/analyze` da feature 00C.

## Core Principles

### I. Auditabilidade Total (NON-NEGOTIABLE)

Toda decisao tomada pelo orquestrador ou por qualquer subagente filho/neto/bisneto
durante uma execucao deve ser registrada de forma estruturada e recuperavel ao
final. Sem auditabilidade, o experimento nao gera o aprendizado que justifica
sua existencia.

**MUST:**

- Toda decisao registrada com **5 campos minimos**: (1) contexto/etapa,
  (2) opcoes consideradas, (3) escolha feita, (4) justificativa, (5) agente
  responsavel pela decisao (orquestrador, clarify-answerer, executor de task,
  etc.).
- Decisoes do `clarify-answerer` (que escolhe entre opcoes geradas pelo
  `clarify-asker`) sao registradas integralmente — pergunta + opcoes
  recomendadas + escolha + por que.
- Bloqueios humanos sao registrados como decisao do tipo "pause" com mesmos
  5 campos + descricao do que foi pedido ao humano.
- Sugestoes para skills globais (que nao podem ser modificadas — ver Principio V)
  sao registradas em arquivo dedicado dentro do projeto-alvo e, quando
  comprovam bug impeditivo, abrem issue no GitHub do toolkit.
- Relatorio final consolida o registro completo em
  `<projeto-alvo>/.claude/agente-00c-report.md` com as secoes definidas no
  briefing §3.MVP.9.

**Rationale**: o briefing escolhe explicitamente Cenario A (relatorio rico, 0
projetos entregues) sobre Cenario B (1 projeto entregue, relatorio raso) como
mais valioso. Se uma decisao nao puder ser auditada, o experimento perde sua
proposta de valor — virar municao para evolucao das skills do toolkit.

### II. Pause-or-Decide (NON-NEGOTIABLE)

Quando o orquestrador ou subagente nao tem confianca suficiente para decidir,
ou quando detecta incoerencia entre artefatos que excede o orcamento de
retro-execucao (Principio IV), DEVE pausar e solicitar decisao humana com
contexto completo, em vez de chutar. Avancar mal e pior que pausar bem.

**MUST:**

- Bloqueios humanos sao **aceitaveis e esperados** — nao sao falha. Sao dado
  para evolucao das skills.
- O `clarify-answerer` SOMENTE decide quando pode justificar a escolha em termos
  do briefing + constitution + stack-sugerida + decisoes anteriores. Se a
  justificativa for "pareceu razoavel", DEVE pausar.
- Detectar incoerencia entre artefatos (ex: plan contradiz spec) dispara
  retro-execucao se houver orcamento (max 2 — Principio IV); se nao houver,
  pausa obrigatoria.
- Bug impeditivo confirmado em skill global e bloqueio obrigatorio: abre issue
  no toolkit e PARA pedindo decisao humana (nao tenta workaround).

**SHOULD:**

- O orquestrador favorece pausar e registrar fundo a avancar sem entender bem,
  inclusive quando o orcamento de tokens permite continuar. A regra e: na
  duvida, pause.

**Rationale**: o briefing prioriza qualidade do relatorio sobre avanco da
pipeline. O `clarify-answerer` decidir mal e a pipeline seguir sem perceber
e o risco mais perigoso identificado no briefing §8. Pause-or-decide e a
mitigacao primaria.

### III. Idempotencia de Retomada (NON-NEGOTIABLE)

A estrategia schedule/clear/continue exige que toda execucao do orquestrador
seja totalmente reconstruivel a partir do estado em disco. Nada essencial
pode viver apenas no contexto carregado — porque o contexto e descartado
entre ondas.

**MUST:**

- Estado de orquestracao persistido em arquivo versionado (schema JSON) em
  `<projeto-alvo>/.claude/agente-00c-state/`. Schema exato definido no `/plan`.
- Cada onda comeca lendo o estado + verificando integridade (schema valido,
  decisoes coerentes) antes de tomar qualquer acao.
- A proxima instrucao (o que executar na proxima onda) e serializada
  explicitamente no estado — nao depende de "lembrar onde parou".
- Artefatos da pipeline (briefing.md, spec.md, plan.md, tasks.md, etc) sao
  fonte da verdade para o conteudo; o estado JSON e indice + decisoes +
  metricas.
- Estado corrompido ou schema invalido = bloqueio obrigatorio com pause humano.
  Nao tentar "consertar" silenciosamente.

**Rationale**: sem idempotencia, schedule/clear/continue vira aposta. O
briefing identifica drift de estado em disco como risco e exige schema
versionado com validacao a cada onda.

### IV. Autonomia Limitada com Gatilhos de Aborto (NON-NEGOTIABLE)

A autonomia do 00C e explicitamente orcada. Nenhum loop, nenhuma recursao,
nenhuma tentativa de auto-correcao escapa dos limites abaixo. Quando um
limite e atingido, o orquestrador para e gera o relatorio mesmo que a
pipeline nao tenha terminado.

**MUST (orcamentos):**

- **Profundidade de subagentes**: maximo 3 niveis. Filho, neto, bisneto.
  Tentativa de spawnar tataraneto = falha explicita devolvida ao orquestrador
  raiz.
- **Retro-execucoes por feature**: maximo 2. Cada uma registrada em
  `decisions[]` com motivo. Terceira incoerencia = pause humano.
- **Loop em etapa**: maximo 5 ciclos na mesma etapa sem progresso mensuravel.
  Sexto ciclo = aborto por "tendencia a loop".
- **Sessao**: ao atingir 80% do consumo da sessao corrente, parar onda atual,
  registrar estado, agendar proxima sessao disponivel via mecanismo definido
  no /plan.
- **Janela semanal**: ao atingir 80% do consumo da janela semanal, parar e
  agendar para a proxima janela.

**MUST (gatilhos de aborto imediato com relatorio):**

- **Impossibilidade tecnica**: comportamento desejado nao implementavel no
  ambiente (Claude Code, docker local, dependencias).
- **Desvio de finalidade**: o que esta sendo construido nao corresponde mais
  ao que foi pedido.
- **Movimento circular**: fix de bug A gera bug B; fix de B regenera A; fix
  de A volta a gerar B. Detectado por heuristica (definida no /plan) em
  inspecao do historico de decisoes.
- **Bug impeditivo em skill global**: ja coberto em Principio II.

**Rationale**: o briefing crava esses limites explicitamente como condicao de
ousadia controlada. Sem orcamento, o experimento vira buraco negro de tokens
e o relatorio final nunca e gerado — perda total.

### V. Blast Radius Confinado (NON-NEGOTIABLE)

O escopo do que o 00C pode escrever, executar e comunicar e estritamente
limitado. Sem este principio, um agente autonomo com tools amplas e risco
operacional inaceitavel.

**MUST (escrita em disco):**

- **Escrita** restrita ao diretorio do projeto-alvo e seus subdiretorios.
  `~/` fora; `~/.claude/skills/` jamais.
- **Skills locais** (`<projeto-alvo>/.claude/skills/`) podem ser editadas pelo
  00C durante a execucao se necessario.
- **Skills globais** (`~/.claude/skills/`) sao **read-only**. Sugestoes de
  melhoria vao para arquivo dedicado no projeto-alvo + (quando comprovam bug)
  issue no toolkit.
- **`.env` do projeto-alvo**: read-only.
- **`.env.claude`** do projeto-alvo: o 00C pode escrever (uso para credenciais
  ou config geradas durante a pipeline).

**MUST (execucao):**

- **Sudo** no host: vetado sem excecao.
- **Package managers** (`npm`, `pip`, `go install`, `brew`, etc.): permitidos
  somente com execucao dentro do container docker do projeto-alvo, nunca no
  host.
- **Docker**: containers locais apenas. Sem registry remoto, sem orquestrador
  remoto.

**MUST (comunicacao externa):**

- **Default: ar-gapped**. Nenhuma chamada externa fora dos canais explicitamente
  autorizados.
- **`curl` / fetches**: somente para URLs declaradas no `.env` do projeto-alvo
  ou em whitelist apresentada no inicio da execucao.
- **`gh`**: operacoes locais (commit, repo info) + **excecao explicita**: pode
  abrir issues no GitHub do toolkit `JotJunior/claude-ai-tips` para reportar
  bugs/sugestoes em skills globais. Sem push de codigo, sem PR externo, sem
  outras operacoes remotas.
- **Credenciais**: o 00C pode usar livremente apenas o que esta no `.env` do
  projeto-alvo. Credenciais fora dali (chaves do sistema operacional, tokens
  globais) ficam fora.

**MUST (git):**

- Commits **locais sempre**, ao final de cada etapa concluida.
- **Push**: jamais, em nenhum branch, em nenhum remote.
- **Deploy externo** (cloud, kubernetes remoto, serverless, etc.): jamais.

**Rationale**: o briefing crava cada uma dessas linhas vermelhas. A combinacao
"agente autonomo com tools amplas + autonomia entre turnos" e segura **somente**
porque o blast radius e finito e auditado. Relaxar qualquer item acima sem
amendment formal degrada a confianca no experimento como um todo.

## Quality Standards

Padroes operacionais que implementam os principios acima e formam o quality
gate em `/plan` (Constitution Check) e `/analyze` da feature 00C.

- **Estado em disco e schema-versionado**: o JSON de estado tem campo `schema_version`
  e validacao a cada leitura. Estado sem `schema_version` ou com schema
  desconhecido = bloqueio (Principio III).
- **Relatorio final tem todas as secoes obrigatorias**: resumo executivo, linha
  do tempo, decisoes (com 5 campos), bloqueios humanos, sugestoes para skills
  globais, metricas (tokens, ondas, tempo wallclock, profundidade max de
  subagentes), licoes aprendidas. Relatorio sem qualquer dessas secoes =
  feature 00C com bug (Principio I).
- **Toda decisao no relatorio tem rastreabilidade**: id estavel + referencia
  ao artefato que originou (qual etapa da pipeline, qual subagente, qual
  pergunta do clarify, etc).
- **Profundidade de subagentes verificavel**: o estado mantem profundidade
  corrente, e tentativa de spawn alem de 3 niveis e detectada e bloqueada
  antes da chamada de Agent tool, nao depois (Principio IV).
- **Whitelist de URLs externas explicita**: declarada no inicio da execucao
  ou no `.env` do projeto-alvo; chamada externa para URL fora da whitelist =
  bloqueio (Principio V).
- **Subordinacao ao toolkit verificada**: codigo gerado pelo 00C que toque
  no proprio toolkit (skills, scripts) DEVE respeitar a constitution do
  toolkit (POSIX sh puro, formato canonico de skill, etc). Codigo gerado
  para o projeto-alvo nao se aplica — projeto-alvo e outro mundo.
- **Issue no toolkit tem template estruturado**: skill afetada, diagnostico,
  proposta, link para o relatorio que originou. Issues sem essa estrutura nao
  devem ser abertas.

## Decision Framework

Quando principios entram em tensao, a ordem de desempate e:

1. **Toolkit constitution prevalece sobre esta**. Se algum principio aqui
   conflita com Principios I-V do toolkit (SDD recursivo, POSIX sh, formato
   canonico de skill, zero coleta remota, profundidade sobre adocao), o
   toolkit vence — esta constitution se ajusta ou e emendada.

2. **NON-NEGOTIABLE vence SHOULD**. Os 5 principios acima sao MUST. Otimizacao
   de progresso, velocidade ou economia de tokens nao cede aos MUST. Se um
   atalho exige relaxar Auditabilidade ou Blast Radius, o atalho e rejeitado.

3. **Quando dois MUST aparentemente conflitam, cita o briefing**. Ex:
   "Auditabilidade exige registrar tudo, mas isso explode tokens e dispara
   Principio IV (orcamento)". Resolucao: o briefing prioriza relatorio rico
   (Cenario A vence). Reduzir nivel de detalhe da auditoria so quando
   estritamente necessario para nao estourar orcamento, e registrar essa
   reducao no proprio relatorio. Auditabilidade e o objetivo; orcamento e a
   restricao operacional.

4. **Reversibilidade favorece exploracao; irreversibilidade favorece
   conservadorismo**. Decisao reversivel (escolher entre duas libs JS no
   projeto-alvo) pode ser tomada pelo `clarify-answerer`. Decisao irreversivel
   ou alto custo de reversao (mexer no schema do estado em disco, romper
   contrato de invocacao do orquestrador) exige spec.md + amendment se for
   na propria feature 00C.

5. **Excecao a SHOULD requer documentacao explicita no relatorio**. Excecao
   a MUST (Principios I-V desta constitution ou I-V do toolkit) exige
   amendment formal — nao ha opt-out tacito.

## Governance

**Subordinacao ao toolkit:**

- Esta constitution e feature-level. A constituicao do toolkit (`docs/constitution.md`)
  e fonte primaria. Toda alteracao no toolkit que afete principios aqui
  exige re-validacao desta constitution.

**Amendment process:**

- Mudancas nesta constitution sao propostas como amendments dentro da propria
  feature 00C (commit no `docs/specs/agente-00c/constitution.md` com Sync
  Impact Report atualizado).
- Amendment que remove ou redefine principio incompativelmente = MAJOR bump.
- Amendment que adiciona novo principio ou expande materialmente uma secao =
  MINOR bump.
- Amendment que clarifica texto sem mudar semantica = PATCH bump.

**Propagacao obrigatoria em MAJOR/MINOR:**

- Atualizar Sync Impact Report no topo deste arquivo.
- Re-rodar `/analyze` na feature 00C.
- Se a mudanca afeta o relatorio final ou o schema de estado: documentar
  migracao para execucoes ja em andamento (improvavel em fase de design,
  obrigatorio quando 00C estiver em uso).

**Authority:**

- Autor/mantenedor (jot) aprova amendments. Esta constitution e governanca
  do experimento; nao tem multiplas partes interessadas.

**Versioning:**

- SemVer rigoroso: MAJOR.MINOR.PATCH.
- Datas em ISO YYYY-MM-DD.
- Versao inicial 1.0.0 — qualquer amendment futuro muda este rodape.

**Version**: 1.0.0 | **Ratified**: 2026-05-05 | **Last Amended**: 2026-05-05
