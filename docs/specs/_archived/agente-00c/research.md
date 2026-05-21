# Research: Agente-00C

Documento Phase 0 do `/plan`. Resolve as duvidas tecnicas materiais identificadas
no briefing (8 "Itens a Definir") e na investigacao da plataforma Claude Code.

---

## Decision 1: Mecanismo de continuacao cross-sessao

**Decision**: Combinacao de **`/loop` (dynamic mode com `ScheduleWakeup`)** como primario
para ondas curtas (5-30 min), e **`/schedule` (Routines)** como fallback para pausas
longas (>= 1h, sobrevivem a maquina suspensa).

- O orquestrador-00C usa `ScheduleWakeup` ao final de cada onda passando como `prompt`
  o sentinela `<<autonomous-loop-dynamic>>` (resolvido pelo runtime para o prompt do
  `/loop` corrente, mantendo continuidade) com `delaySeconds` calibrado a etapa.
- Para pausas em bloqueio humano que podem demorar horas/dias, o orquestrador grava
  no estado uma intencao de retomada e apresenta ao operador a opcao de criar uma
  rotina via `/schedule` apontando para `/agente-00c-resume` (a ser implementado
  como comando auxiliar no toolkit).
- `/schedule` Routines roda na infraestrutura cloud da Anthropic e sobrevive a
  laptop suspenso, mas tem intervalo minimo de 1h.
- `/loop` exige a maquina ligada e tem expiracao de 7 dias; suficiente para o
  experimento pessoal.

**Rationale**: o briefing pediu "schedule para a proxima sessao em ~5 minutos".
`/schedule` minimo e 1h, entao nao serve para 5min. `/loop` + ScheduleWakeup
viabiliza 5min com ressalva (maquina ligada). Para quando o operador deixa o
experimento rodando overnight ou sai por dias, `/schedule` e o degrau seguinte.

**Alternatives considered**:

- **`/schedule` exclusivo**: rejeitado por intervalo minimo de 1h — quebra a
  cadencia cravada no briefing.
- **Cron externo (do sistema operacional)**: rejeitado porque exigiria integracao
  fora do harness Claude Code, aumentando blast radius (Principio V) e fragilidade.
- **Tudo em uma sessao com `/compact` agressivo**: rejeitado porque pipeline
  longa estoura context window mesmo com compact, e o objetivo do experimento
  e exatamente *testar* execucao multi-sessao.

---

## Decision 2: Heuristica para gatilho de "80% de consumo"

**Decision**: Pivotar de medicao direta de tokens (nao observavel) para **agregado
de tres proxies**:

1. **Numero de tool calls na onda corrente** — contador no estado, incrementado
   pelo proprio orquestrador a cada chamada significativa (Bash, Read, Write,
   Agent, Skill). Threshold inicial: 80 chamadas = sinal de "perto do limite".
2. **Tempo wallclock da onda** — `date +%s` no inicio da onda; comparar a cada
   ponto de decisao. Threshold inicial: 90 minutos de onda.
3. **Tamanho do estado serializado** — quando o estado JSON cresce alem de
   1MB, sinal de que decisoes acumulam alem do razoavel. Threshold de
   "compactar relatorio antes de proxima onda".

Qualquer um dos tres atingindo threshold dispara fim de onda + agendamento de
proxima. Janela semanal (limite de uso semanal Anthropic) **nao tem proxy
confiavel** — registra-se isso como limitacao conhecida no relatorio.

**Rationale**: a investigacao mostrou que Claude Code nao expoe consumo de
tokens em tempo real ao agente. Os tres proxies sao todos observaveis dentro
de uma onda (contadores incrementais, comandos shell), nao requerem features
nao publicas, e juntos cobrem os modos comuns de explosao de contexto. Os
thresholds sao chutes calibrados por tentativa-erro nas primeiras execucoes
do experimento — virarao licao aprendida.

**Alternatives considered**:

- **Esperar `/compact` automatico do harness e usar como sentinela**: rejeitado
  porque o agente nao tem hook nativo para detectar invocacao do compact; a
  deteccao seria post-hoc.
- **Usar transcript export via Bash a cada N decisoes para medir tamanho**:
  rejeitado por custo (cada export e tool call adicional + parsing).
- **Ignorar o gatilho e deixar a sessao estourar naturalmente**: rejeitado
  porque viola Principio IV (Autonomia Limitada com Aborto) — pipeline tem
  que parar antes do estouro, nao depois.

**Implicacao de spec**: FR-009 sera ajustado de "80% de consumo de sessao"
(literal, nao observavel) para "ao atingir qualquer um dos tres thresholds
de proxy" (observavel). Update aplicado a `spec.md` apos este research.md.

---

## Decision 3: Schema do estado em disco

**Decision**: arquivo JSON unico em
`<projeto-alvo>/.claude/agente-00c-state/state.json`, com schema versionado.
Backups por onda em `state-history/<timestamp>.json` para auditoria.

```json
{
  "schema_version": "1.0.0",
  "execucao_id": "exec-2026-05-05T14-23-00Z-agente-00c-{slug-projeto-alvo}",
  "projeto_alvo": {
    "path": "/Users/jot/Projects/_lab/poc-foo",
    "descricao_curta": "POC de bot Slack que sumariza threads",
    "stack_sugerida": null
  },
  "status": "em_andamento | aguardando_humano | abortada | concluida",
  "etapa_corrente": "specify",
  "proxima_instrucao": "Continuar specify com base em briefing.md gerado na onda anterior. Stack ainda nao escolhida — clarify-answerer deve decidir.",
  "ondas": [
    {
      "id": "onda-001",
      "inicio": "2026-05-05T14:23:00Z",
      "fim": "2026-05-05T14:51:00Z",
      "etapas_executadas": ["briefing"],
      "tool_calls": 42,
      "wallclock_seconds": 1680,
      "motivo_termino": "etapa_concluida_avancando"
    }
  ],
  "decisoes": [
    {
      "id": "dec-001",
      "timestamp": "2026-05-05T14:31:22Z",
      "etapa": "briefing",
      "agente": "orquestrador-00c",
      "contexto": "Briefing pergunta 4: stakeholders — operador unico ou time?",
      "opcoes_consideradas": ["Operador unico", "Time pequeno", "Multi-time"],
      "escolha": "Operador unico",
      "justificativa": "Briefing do 00C marca uso pessoal sem stakeholders externos; projeto-alvo herda esse padrao por default."
    }
  ],
  "bloqueios_humanos": [],
  "orcamentos": {
    "recursividade_max": 3,
    "profundidade_corrente": 1,
    "retro_execucoes_max_por_feature": 2,
    "retro_execucoes_consumidas": 0,
    "ciclos_max_por_etapa": 5,
    "ciclos_corrente_etapa": 1,
    "tool_calls_threshold_onda": 80,
    "wallclock_threshold_segundos": 5400,
    "estado_size_threshold_bytes": 1048576
  },
  "metricas_acumuladas": {
    "ondas_total": 1,
    "tool_calls_total": 42,
    "tempo_wallclock_total_segundos": 1680,
    "profundidade_max_atingida": 1,
    "subagentes_spawned": 0
  },
  "whitelist_urls_externas": ["https://pkg.go.dev", "https://hub.docker.com"],
  "sugestoes_skills_globais_count": 0,
  "issues_toolkit_abertas": []
}
```

**Rationale**: schema_version explicito permite migracao futura (Principio III
exige validacao a cada onda). JSON unico evita race conditions entre arquivos.
History/backup por onda permite auditoria e rollback de estado corrompido.

**Alternatives considered**:

- **SQLite**: rejeitado por adicionar dependencia (driver SQLite no host) e
  violar simplicidade — JSON e POSIX-compativel via shell.
- **Multiplos arquivos por aspecto** (decisoes.json, ondas.json, etc): rejeitado
  por risco de inconsistencia entre arquivos sem transacao atomica.
- **YAML em vez de JSON**: rejeitado porque YAML em shell exige `yq` (nao POSIX,
  proibido por Principio II do toolkit em scripts do toolkit).

---

## Decision 4: Heuristica de deteccao de movimento circular

**Decision**: durante etapas que envolvem fixes/correcoes (execute-task em loop),
manter um **buffer deslizante das ultimas 6 decisoes** com hash do par
(descricao_problema, descricao_solucao). Se aparecerem 2 pares com a mesma
descricao_problema mas descricao_solucao diferente, e em seguida um terceiro par
com a primeira descricao_solucao + primeira descricao_problema, classificar como
movimento circular e abortar.

```
Buffer (capacidade 6):
[ (P=A, S=X), (P=B, S=Y), (P=A, S=Z), (P=B, S=Y), (P=A, S=X) ]
                                                       ^ retorna ao primeiro par => CIRCULAR
```

A descricao do problema e da solucao sao normalizadas (lowercase, primeiras
~20 palavras semanticamente relevantes). O hash usa a normalizacao para tolerar
pequenas variacoes de wording.

**Rationale**: detecta o padrao classico fix-A-quebra-B, fix-B-rerompe-A. A
janela de 6 e suficiente para 2 ciclos completos de "ida e volta" sem ser
sensivel a variacoes legitimas na pipeline.

**Alternatives considered**:

- **Hash exato (sem normalizacao)**: rejeitado porque pequenas variacoes de
  wording mascaram o ciclo.
- **Janela de tamanho 4**: rejeitado por sensibilidade demais — captura
  apenas o primeiro ciclo, nao distingue de fluxo legitimo.
- **Modelo ML para detectar similaridade semantica**: rejeitado por
  complexidade absurda para experimento pessoal. Heuristica simples basta.

---

## Decision 5: Formato da whitelist de URLs externas

**Decision**: arquivo `<projeto-alvo>/.claude/agente-00c-whitelist`, formato
linha-por-URL com globs simples permitidos. URL do `.env` sao automaticamente
incluidas via leitura no inicio da execucao.

```
# Whitelist de URLs externas que o agente-00C pode acessar.
# Uma URL ou padrao por linha. Linhas com # sao comentarios.
# Padroes simples com * e ** suportados.

https://pkg.go.dev/**
https://api.github.com/repos/JotJunior/claude-ai-tips/**
https://hub.docker.com/_/**
```

Ao iniciar a execucao, o orquestrador le whitelist + URLs do `.env` e armazena
no estado em `whitelist_urls_externas`. Tentativa de acesso a URL nao listada
dispara bloqueio. Operador pode adicionar URL mid-execucao editando o arquivo
+ disparando retomada manual (estado le whitelist a cada onda).

**Rationale**: simplicidade. Linha-por-linha e amigavel a `grep`/`awk`/`sed`
(POSIX). Globs simples cobrem 90% dos casos sem exigir parser sofisticado.

**Alternatives considered**:

- **Regex cru**: rejeitado por dificuldade de auditoria humana.
- **JSON estruturado** (whitelist.json): rejeitado por overkill — uma lista
  de strings nao precisa de schema.
- **Validacao no `.env` apenas**: rejeitado porque algumas URLs (docs, pkg
  registries) nao tem credencial e nao caberiam no `.env`.

---

## Decision 6: Heuristica de confianca do clarify-answerer

**Decision**: o clarify-answerer atribui um **score de justificativa em
{0, 1, 2, 3}** a cada possivel resposta, baseado em quantas das fontes
abaixo a justificam:

- (1) Briefing (do projeto-alvo) suporta a opcao
- (2) Constitution (do projeto-alvo, do toolkit, ou ambas) suporta a opcao
- (3) Stack-sugerida foi explicitamente passada e aponta para a opcao

Regra de decisao:

- Score >= 2: decide e registra a opcao com as referencias.
- Score == 1: decide somente se a opcao restante for unanimemente rejeitavel
  (ex: viola constitution); senao pausa.
- Score == 0: pausa obrigatoriamente — Pause-or-Decide.

**Rationale**: traduz Principio II em criterio mecanico verificavel. Evita
"pareceu razoavel" porque cada decisao tem um trail de quais fontes (1/2/3)
suportaram a escolha.

**Alternatives considered**:

- **Score continuo via embedding similarity**: rejeitado por complexidade.
- **Decisao livre baseada em "raciocinio do agente"**: rejeitado por ser
  exatamente o que Principio II proibe.
- **Threshold mais alto (so decide com score 3)**: rejeitado porque
  realisticamente muitas decisoes nao terao stack-sugerida explicita; isso
  faria toda execucao virar bloqueio humano.

---

## Decision 7: Comportamento quando bisneto tenta spawnar tataraneto

**Decision**: o subagente bisneto (profundidade 3) recebe ferramentas Agent
**bloqueadas** em sua definicao. Tentativa de spawnar = falha de tool com
mensagem clara, retornada como erro ao orquestrador raiz que registra como
decisao "limite de profundidade atingido" e tenta caminho alternativo (delegar
ao neto, ou acumular contexto e fazer ele mesmo).

**Rationale**: bloquear na definicao do subagente e mais robusto que confiar
em validacao no orquestrador raiz. O proprio harness recusa o spawn antes da
chamada acontecer — defesa em profundidade.

**Alternatives considered**:

- **Validacao apenas no orquestrador raiz**: rejeitado porque depende de o raiz
  saber a profundidade corrente, e isso pode falhar em retomada.
- **Permitir tataraneto com bloqueio em tatataraneto**: rejeitado por
  inflar gastos sem ganho — 3 niveis ja cobrem casos do experimento.

---

## Decision 8: Forma do 00C no harness

**Decision**: combinacao de tres artefatos no toolkit `claude-ai-tips`:

1. **Slash command** em `global/commands/agente-00c.md` — ponto de entrada
   manual `/agente-00c <args>`. Carrega instrucoes resumidas + spawna o
   agente-orquestrador via Agent tool.
2. **Agente custom orquestrador** em
   `global/agents/agente-00c-orchestrator.md` — frontmatter com tools amplas
   (Agent, Skill, Bash, Read, Write, Edit, Glob, Grep, ScheduleWakeup),
   instrucoes detalhadas de orquestracao da pipeline.
3. **Agentes custom especializados** para o padrao de dois atores:
   - `global/agents/agente-00c-clarify-asker.md` — frontmatter com Skill, Read.
   - `global/agents/agente-00c-clarify-answerer.md` — frontmatter com Read,
     Bash (para `date`).
4. **Slash commands auxiliares**:
   - `/agente-00c-abort` em `global/commands/agente-00c-abort.md` — leitura
     de estado, marcacao como abortado, geracao de relatorio.
   - `/agente-00c-resume` em `global/commands/agente-00c-resume.md` — para
     o caso de retomada via `/schedule` Routines.

Skill formal `global/skills/agente-00c/SKILL.md` **nao e necessaria** —
toda a logica de progressive disclosure cabe no agente-orquestrador, e o
slash command e o ponto de invocacao.

**Rationale**: slash command permite invocacao manual com argumentos. Agente
custom permite tools amplas isoladas do contexto principal. Especializacao
via subagentes mediados pelo orquestrador implementa o padrao de dois atores
do clarify (Pergunta 4 do spike).

**Alternatives considered**:

- **Skill unica `agente-00c`**: rejeitado porque skill nao tem mecanismo de
  ponto-de-entrada parametrizado equivalente a slash command.
- **Slash command sem agente custom**: rejeitado porque a sessao principal
  ficaria poluida por toda a pipeline; agente custom isola contexto.
- **Hooks como gatilho**: rejeitado porque hooks sao para reacao a eventos,
  nao para fluxo de trabalho long-running.

---

## Decision 9: Comunicacao orquestrador <-> subagentes

**Decision**: comunicacao **sempre mediada pelo orquestrador**. Subagentes
retornam UMA mensagem; orquestrador la, decide proximo passo, spawna proximo
subagente passando o contexto necessario.

Padrao especifico para clarify de dois atores:

```
1. Orquestrador → spawna `clarify-asker` com argumentos
   { spec_corrente, briefing, etapa }
   ← recebe { perguntas: [{ id, contexto, opcoes_recomendadas: [...] }] }

2. Orquestrador → spawna `clarify-answerer` com argumentos
   { perguntas (do passo 1), briefing, constitution_projeto, constitution_toolkit, stack_sugerida, decisoes_anteriores }
   ← recebe { respostas: [{ pergunta_id, opcao_escolhida, justificativa, score }] }

3. Orquestrador → para cada resposta com score < threshold,
   converte em bloqueio humano e pausa onda.
4. Orquestrador → para respostas com score suficiente,
   aplica a spec, registra como decisoes auditaveis.
```

`SendMessage` (continuar agente parado) **nao e usado** — cada subagente roda
e retorna; o estado vive no orquestrador raiz.

**Rationale**: respeita o limite arquitetural do harness (subagentes retornam
1 mensagem). O padrao mediado e mais simples e auditavel que tentar canal
sibling-to-sibling. Cada spawn e uma decisao registrada no estado.

**Alternatives considered**:

- **`SendMessage` para retomar `clarify-answerer` apos parecer**: rejeitado
  por complexidade — exige rastrear `agentId` e gerenciar dois ciclos de
  vida em paralelo.
- **Um unico subagente que combina ask+answer**: rejeitado porque isso era
  exatamente o que o usuario rejeitou no design original (queria dois atores
  distintos para separar bias do asker e do answerer).

---

## Decision 10: Estrutura final do relatorio

**Decision**: relatorio em
`<projeto-alvo>/.claude/agente-00c-report.md` com seis secoes obrigatorias
fixas mais um indice. Estrutura definida em `contracts/report-format.md`.

Resumo das secoes:

1. **Resumo executivo** (1 pagina): id execucao, projeto-alvo, descricao, stack
   final, status (concluida/abortada/aguardando humano), motivo termino,
   metricas-chave (ondas, tool calls, decisoes, bloqueios, sugestoes, issues
   abertas).
2. **Linha do tempo**: tabela cronologica de ondas com etapa inicial, etapa
   final, motivo termino, duracao.
3. **Decisoes**: tabela ou lista de cada decisao com 5 campos.
4. **Bloqueios humanos**: lista de cada bloqueio com pergunta, contexto e
   status (aguardando/respondido).
5. **Sugestoes para skills globais**: lista de itens registrados em
   `agente-00c-suggestions.md`, com indicacao de quais viraram issues.
6. **Licoes aprendidas**: secao livre, populada pelo orquestrador no final
   da execucao com observacoes sobre o que funcionou, o que nao funcionou,
   e propostas concretas de melhoria das skills.

**Rationale**: alinhado com FR-011 e cenario A (relatorio rico). Secoes
fixas garantem comparabilidade entre execucoes (essencial para licao
longitudinal — SC-010).

**Alternatives considered**:

- **Estrutura livre**: rejeitado porque dificulta SC-010 (comparar execucoes).
- **Relatorio em JSON**: rejeitado porque o consumidor primario e o operador
  humano joao — markdown e mais legivel.

---

## Decisao agregada: ajustes na spec

A pesquisa identificou **um requisito da spec que precisa ajuste** para refletir
o que e tecnicamente observavel:

- **FR-009** (original): "Sistema MUST agendar continuacao automatica ao atingir
  80% de consumo de sessao, e nova janela ao atingir 80% de consumo da janela
  semanal."
- **FR-009** (ajustado): "Sistema MUST agendar continuacao automatica ao atingir
  qualquer um dos tres thresholds de proxy de consumo de sessao (tool calls,
  wallclock, tamanho de estado). Janela semanal nao tem proxy confiavel — registrada
  como limitacao conhecida; mitigada via gatilho de aborto manual ou inspecao
  passiva via `/usage`."

Aplicado a `spec.md` apos publicacao deste research.md.
