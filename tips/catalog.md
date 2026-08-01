# Catalogo de Dicas — Claude AI Tips Toolkit
#
# Encoding: UTF-8
# Formato: Markdown com frontmatter YAML por entrada.
#
# == INSTRUCOES PARA MANTENEDORES ==
#
# Cada entrada e delimitada por linhas contendo EXATAMENTE "---" (tres
# hifens, sem espacos antes ou depois). O arquivo DEVE terminar com "---"
# apos o corpo da ultima entrada — sem esse terminador final, a ultima
# entrada nao sera emitida pelo parser.
#
# ESTRUTURA DE UMA ENTRADA:
#
#   ---
#   skill: <nome-da-skill>          <- OBRIGATORIO: nome exato (ex: review-task)
#   category: <enum>                <- OBRIGATORIO: uso | gotcha | avancado
#   text: <texto da dica>           <- OBRIGATORIO: max 2 frases, uma linha
#   ---
#   <corpo com exemplos>
#
# CAMPOS OBRIGATORIOS:
#   skill:    nome exato da skill (case-sensitive; deve corresponder a um
#             diretorio em global/skills/ ou language-related/*/skills/)
#   category: um dos tres valores: uso | gotcha | avancado
#   text:     texto da dica em ate 2 frases; manter em uma unica linha YAML
#
# CORPO (apos o segundo "---"):
#   - Conter pelo menos 1 exemplo de uso concreto (FR-001)
#   - Exemplos em fence de codigo (``` ... ```) ou indentados com 4 espacos
#   - NUNCA usar linha isolada "---" no corpo — confunde o parser awk
#   - Texto descritivo antes do exemplo e bem-vindo mas opcional
#
# PARSEABILIDADE:
#   O parser usa uma maquina de estados awk. Transicao de estado ocorre
#   em linha "^---$". Qualquer linha de conteudo que corresponda exatamente
#   a "---" sera interpretada como separador — use "- --" ou fence de codigo
#   para representar separadores dentro do corpo.
#
# TEMPO ESTIMADO PARA ADICIONAR UMA DICA: < 5 minutos
#
# == ENTRADA DE EXEMPLO (referencia para novos mantenedores) ==
#
#   ---
#   skill: review-task
#   category: uso
#   text: Use /review-task para um relatorio completo do andamento da feature, com tarefas prontas para iniciar.
#   ---
#   Quer saber como esta o andamento da sua feature?
#
#   ```
#   /review-task nome-da-feature
#   ```
#
#   Retorna progresso por fase e proximas tarefas desbloqueadas.
#
# == FIM DAS INSTRUCOES ==

# ============================================================
# SECAO 1: Skills Globais (23 skills)
# ============================================================

---
skill: advisor
category: uso
text: Use /advisor para obter uma critica estrategica de um plano ou ideia antes de implementar — o advisor questiona premissas e aponta riscos nao obvios.
---
Antes de comecar a implementar uma feature complexa, peca uma avaliacao estrategica:

```
/advisor
Estou planejando implementar um sistema de cache distribuido para resolver
latencia de leitura. Faz sentido para um MVP com 100 usuarios?
```

O advisor questiona se o problema real e latencia ou outra coisa, e sugere alternativas mais simples.

---
skill: advisor
category: gotcha
text: O advisor e para critica e avaliacao de ideias/planos — nao use para tarefas tecnicas como implementar codigo ou corrigir bugs.
---
Errado: pedir ao advisor para implementar uma feature ou corrigir um bug.

```
# NAO faca isso — use /execute-task ou /bugfix no lugar:
/advisor
Implemente um endpoint REST para criar usuarios no banco.
```

Correto: pedir avaliacao estrategica de uma decisao arquitetural ou plano.

---
skill: agente-00c-runtime
category: uso
text: O agente-00c-runtime e um helper interno do orquestrador — nao e invocavel diretamente pelo usuario. Ele e usado pelos scripts de runtime (state-rw.sh, state-ondas.sh, etc.).
---
O runtime e acionado internamente pelos orquestradores agente-00c e feature-00c.
Para interagir com o pipeline autonomo, use:

```
/agente-00c          # iniciar execucao autonoma
/agente-00c-resume   # retomar execucao pausada
/agente-00c-abort    # abortar execucao corrente
```

---
skill: agente-00c-runtime
category: gotcha
text: Tentar invocar agente-00c-runtime diretamente nao produz resultado util — a skill e um modulo interno sem interface publica para o usuario.
---
O agente-00c-runtime nao tem interface de usuario. Se voce quer auditar o state
de uma execucao autonoma, leia o arquivo diretamente:

```bash
cat .claude/agente-00c-state/state.json | jq '.ondas[-1]'
```

---
skill: analyze
category: uso
text: Use /analyze para verificar consistencia cross-artifact entre spec, plan, tasks e constitution — detecta divergencias que validacao individual nao pega.
---
Apos criar spec + plan + tasks, verifique se estao consistentes:

```
/analyze
```

O analyze compara os artefatos entre si e lista inconsistencias como "task 3.2
referencia FR-007 que nao existe na spec" ou "plan menciona endpoint /v2/users
que nao tem UC correspondente".

---
skill: analyze
category: gotcha
text: O /analyze e para validacao cross-artifact — nao use para validar um unico documento (use /validate-documentation para isso).
---
Para validar um documento individual:

```
/validate-documentation docs/specs/minha-feature/spec.md
```

Para validar consistencia entre multiplos artefatos:

```
/analyze   # le spec + plan + tasks + constitution juntos
```

---
skill: apply-insights
category: uso
text: Use /apply-insights para aplicar aprendizados do seu historico de uso do Claude Code ao projeto atual — melhora CLAUDE.md, hooks e workflows automaticamente.
---
Apos usar o Claude Code por um tempo, aplique os insights acumulados:

```
/apply-insights
```

A skill le ~/.claude/usage-data/facets/*.json (ou insights curados) e sugere
melhorias concretas para CLAUDE.md e settings.json do projeto.

---
skill: apply-insights
category: gotcha
text: O /apply-insights consome dados do comando nativo /insights do Claude Code — rode /insights primeiro para ter dados frescos antes de aplicar.
---
Fluxo correto:

```
/insights          # gera/atualiza os dados de uso (comando nativo)
/apply-insights    # consome esses dados e aplica melhorias ao projeto
```

Rodar /apply-insights sem dados frescos pode resultar em sugestoes genericas.

---
skill: briefing
category: uso
text: Use /briefing no inicio de um projeto novo para conduzir uma entrevista estruturada de discovery — visao, usuarios, constraints, stack e criterios de sucesso.
---
No inicio de qualquer projeto novo:

```
/briefing
```

A skill conduz uma entrevista com perguntas sobre visao do produto, usuarios-alvo,
constraints tecnicas e de negocio, e stack preferida. O resultado e um briefing.md
que alimenta a constitution e o pipeline SDD.

---
skill: briefing
category: gotcha
text: Se o briefing ja existe e voce quer atualizar apenas um aspecto, especifique explicitamente — sem isso, a skill pode refazer toda a entrevista.
---
Para atualizar o briefing existente:

```
/briefing   # entao diga: "quero atualizar apenas a secao de constraints"
```

Sem esse contexto, a skill pode iniciar a entrevista do zero e sobrescrever
decisoes ja ratificadas.

---
skill: bugfix
category: uso
text: Use /bugfix para investigacao multi-camada de bugs — a skill traceja o problema por todas as camadas (API, servico, banco) antes de aplicar o patch.
---
Para um bug de producao que voce nao consegue reproduzir localmente:

```
/bugfix
Stack trace: NullPointerException em UserService.findById linha 47.
O erro ocorre apenas quando o usuario tem role=GUEST.
```

O bugfix investiga todas as camadas (controller → service → repository → schema)
antes de sugerir o patch — evita fixes superficiais que revelam o bug em outra camada.

---
skill: bugfix
category: gotcha
text: Nao use /bugfix para novas features — e especificamente para investigar e corrigir comportamento incorreto de codigo existente.
---
```
# NAO use bugfix para isso:
/bugfix   # "quero adicionar autenticacao JWT ao sistema"

# Use execute-task ou specify:
/specify  # para nova feature
/execute-task  # para implementar tarefa do backlog
```

---
skill: bugfix
category: avancado
text: Para bugs intermitentes ou race conditions, inclua no prompt o contexto de concorrencia — o bugfix usa isso para investigar locks, transacoes e estado compartilhado.
---
Bug intermitente em ambiente multi-thread:

```
/bugfix
Erro ocasional: "Duplicate key violation" em orders.order_number.
Ocorre apenas sob carga alta (>50 req/s). Temos transacoes mas o
gerador de numero usa SELECT MAX + 1 sem lock.
```

O bugfix traceja o caminho de geracao do numero e sugere: sequence do banco,
UUID, ou lock otimista — dependendo do contrato de negocio.

---
skill: checklist
category: uso
text: Use /checklist para um quality gate de requisitos por dominio (ux/api/security/performance/a11y) — valida a qualidade dos requisitos, nao o codigo.
---
Apos escrever os requisitos de uma feature, valide-os:

```
/checklist
```

A skill percorre os requisitos e verifica: sao tesaveis? tem criterios de
aceitacao? cobrem casos de erro? Retorna uma lista de gaps a resolver antes
de comecar a implementar.

---
skill: checklist
category: gotcha
text: O /checklist valida REQUISITOS, nao codigo — para validar consistencia de artefatos SDD use /analyze, para validar documentos individuais use /validate-documentation.
---
```
# Para requisitos (spec.md, user stories):
/checklist

# Para consistencia entre spec/plan/tasks:
/analyze

# Para um documento individual (spec, plan, ADR):
/validate-documentation docs/specs/minha-feature/spec.md
```

---
skill: clarify
category: uso
text: Use /clarify para refinar uma spec existente via Q&A estruturado — resolve ambiguidades especificas sem reescrever a spec do zero.
---
Quando a spec tem pontos ambiguos:

```
/clarify
```

A skill identifica as principais ambiguidades (max 5 perguntas) e atualiza a
spec na secao "## Clarifications" com as respostas. Ideal apos /specify e
antes de /plan.

---
skill: clarify
category: gotcha
text: O /clarify opera em uma spec.md ja existente — use /specify para criar uma spec nova a partir de descricao em linguagem natural.
---
```
# Para criar spec nova:
/specify  "feature de autenticacao com OAuth2"

# Para refinar spec ja existente (com ambiguidades):
/clarify  # le a spec.md corrente e faz perguntas
```

---
skill: constitution
category: uso
text: Use /constitution para criar ou atualizar os principios de governanca imoveis do projeto — arquitetura, qualidade, seguranca e convencoes que todos os artefatos devem respeitar.
---
No inicio do projeto, apos o briefing:

```
/constitution
```

A constitution define MUSTs que o pipeline SDD vai verificar — ex: "POSIX sh puro",
"sem dependencias de runtime externas", "SemVer obrigatorio". Uma vez ratificada,
mudancas requerem justificativa explicita.

---
skill: constitution
category: gotcha
text: A constitution e para principios imoveis de governanca — para decisoes tecnicas pontuais use ADRs em vez de atualizar a constitution.
---
```
# Para decisao arquitetural especifica (ex: "escolhemos PostgreSQL"):
# Crie um ADR em docs/architecture/decisions/

# Para principio que vale para TODO o projeto (ex: "zero dependencias externas"):
/constitution  # adicionar como MUST
```

---
skill: create-tasks
category: uso
text: Use /create-tasks para decompor uma spec ou escopo em backlog de tarefas com fases, dependencias e criticidade — resultado em tasks.md.
---
Apos /plan estar completo:

```
/create-tasks
```

A skill le spec + plan e gera um tasks.md com tarefas agrupadas por fase,
ordenadas por dependencia, com criticidade [C]/[A]/[M] e subtarefas atomicas.

---
skill: create-tasks
category: gotcha
text: O /create-tasks decompose escopo em tarefas — nao executa as tarefas. Para executar, use /execute-task com o ID da tarefa.
---
```
/create-tasks    # gera tasks.md com backlog estruturado
/execute-task 1.1  # executa a tarefa 1.1 do backlog
```

Rodar /create-tasks novamente sobre um tasks.md existente pode sobrescrever
progresso marcado — verifique antes.

---
skill: execute-task
category: uso
text: Use /execute-task com o ID da tarefa para executar um item do backlog seguindo o fluxo de 9 etapas — analise, localizacao, planejamento, implementacao, testes, validacao, lint, conclusao, atualizacao.
---
Para executar a tarefa 2.3 do backlog:

```
/execute-task 2.3
```

A skill le a spec, plan e tasks.md, executa a tarefa com os 9 passos obrigatorios
e marca `[x]` no tasks.md ao final. Sempre confirme que o tasks.md foi atualizado.

---
skill: execute-task
category: gotcha
text: Nao pule a etapa de lint (ETAPA 7) nem a atualizacao do tasks.md (ETAPA 9) — sao as causas #1 de regressao e drift documental.
---
Fluxo obrigatorio — nao abreviar:

```
ETAPA 7: shellcheck -s sh arquivo.sh   # ou lint do stack
ETAPA 9: marcar [x] no tasks.md       # SEMPRE ao final
```

Tarefa com codigo entregue mas sem `[x]` no tasks.md sera re-processada
na proxima onda — custo dobrado.

---
skill: execute-task
category: avancado
text: Para tarefas que envolvem multiplos modulos independentes, use o parametro de contexto para passar dependencias ja concluidas e evitar re-analise de codigo ja lido.
---
Ao executar tarefa que depende de modulo ja implementado:

```
/execute-task 4.2 context="modulo de autenticacao ja implementado em
auth/service.go (task 3.1 concluida). Reutilizar AuthService.ValidateToken()
sem reimplementar."
```

Isso evita que a skill re-leia e re-analise codigo ja conhecido, focando
no que e realmente novo na tarefa 4.2.

---
skill: initialize-docs
category: uso
text: Use /initialize-docs para criar a hierarquia padrao de documentacao (01-09 dirs, READMEs, briefing, UCs, DER, ADRs, APIs, tests, ops) em projetos novos.
---
No inicio de um projeto:

```
/initialize-docs
```

Cria a estrutura padrao de `docs/` com todos os diretorios padronizados
e arquivos README.md descritivos. Evita criar estrutura manual inconsistente.

---
skill: initialize-docs
category: gotcha
text: O /initialize-docs pula automaticamente se a estrutura ja existe — use --force apenas se quiser recriar diretorios que ja existem (cuidado com sobrescrita).
---
```
# Verificar antes:
ls docs/

# Se estrutura ja existe, a skill nao sobrescreve por padrao.
# Para forccar recreacao (CUIDADO — pode sobrescrever):
/initialize-docs --force
```

---
skill: model-selector
category: uso
text: Use /model-selector para obter uma sugestao deterministica de modelo (haiku/sonnet) baseada na complexidade da tarefa — util antes de invocar skills caras.
---
Para decidir qual modelo usar antes de uma tarefa longa:

```
/model-selector
Tarefa: revisar 15 arquivos de codigo Go para conformidade com convencoes
do projeto, gerar relatorio de gaps e sugerir refatoracoes prioritarias.
```

A skill classifica a tarefa em rasa/media/profunda e sugere o modelo
mais economico que cobre a complexidade — sem trocar o modelo silenciosamente.

---
skill: model-selector
category: gotcha
text: O /model-selector apenas SUGERE um modelo — nao troca automaticamente. Para aplicar, o orquestrador precisa usar o modelo sugerido explicitamente no spawn do subagente.
---
O model-selector emite uma sugestao com score e justificativa:

```json
{ "modelo": "haiku", "score_runtime": 3, "sinais_text": "tarefa rasa..." }
```

A troca de modelo e responsabilidade do orquestrador — a skill nao muda
o modelo da sessao corrente. Util para audit e model-routing por onda.

---
skill: owasp-security
category: uso
text: Use /owasp-security para revisao de seguranca cobrindo OWASP Top 10:2025, ASVS 5.0, LLM Top 10, OAuth 2.1 e NIST 800-63B-4 — ideal para codigo de autenticacao e APIs expostas.
---
Antes de fazer merge de PR com mudancas em autenticacao:

```
/owasp-security
```

A skill revisa o diff atual contra OWASP Top 10, verifica headers de
seguranca, validacao de input, secrets hardcoded e configuracao de CORS.

---
skill: owasp-security
category: gotcha
text: O /owasp-security e para revisao de seguranca — nao substitui /code-review para bugs de correctness ou /bugfix para problemas conhecidos.
---
```
# Para seguranca (injection, auth, exposicao de dados):
/owasp-security

# Para bugs de logica/correctness:
/bugfix  ou  /code-review

# Para revisao completa (seguranca + correctness):
/owasp-security  # depois  /code-review
```

---
skill: plan
category: uso
text: Use /plan para gerar um plano tecnico completo a partir da spec — arquitetura, modelo de dados, contratos de API, pesquisa e cenarios de teste.
---
Apos spec + clarify estarem completos:

```
/plan
```

Gera plan.md com: decisoes arquiteturais, estrutura de projeto, dependencias,
modelo de dados, contratos de API/CLI, pesquisa de alternativas e plano de testes.
Referencia a spec mas nao a duplica.

---
skill: plan
category: gotcha
text: O /plan cria o plano tecnico — nao use para decompor em tarefas (use /create-tasks) nem para criar a spec (use /specify).
---
```
/specify       # 1. criar spec com user stories e requisitos
/clarify       # 2. resolver ambiguidades da spec
/plan          # 3. plano tecnico (arquitetura, contratos)
/create-tasks  # 4. decompor em backlog de tarefas
/execute-task  # 5. executar cada tarefa
```

---
skill: plan
category: avancado
text: Para features com multiplos contratos de integracao, passe os contratos existentes como contexto — o plan os referencia em vez de recriar, mantendo consistencia cross-feature.
---
Ao planejar feature que integra com recall.sh e cstk:

```
/plan
context="contratos existentes em docs/specs/_archived/cstk-knowledge-db/contracts/
e cli/cstk dispatcher em cli/cstk linhas 190-260. A feature deve seguir o mesmo
padrao de despacho de cstk recall."
```

O plan referencia os contratos existentes e documenta apenas os pontos de
integracao novos — sem re-derivar contratos ja ratificados.

---
skill: review-features
category: uso
text: Use /review-features para um dashboard global do portfolio de features — compara progresso, identifica candidates para arquivar e sugere priorizacao.
---
Para visao geral de todas as features em andamento:

```
/review-features
```

Compara o progresso de todas as features (via state.json de cada uma),
lista features pausadas ha mais de X dias, sugere o que arquivar e o
que priorizar. Cross-feature — nao use para deep-dive em uma feature especifica.

---
skill: review-features
category: gotcha
text: O /review-features e para visao cross-feature do portfolio — para status detalhado de uma feature especifica use /review-task.
---
```
# Para visao geral de todas as features:
/review-features

# Para status detalhado de uma feature especifica:
/review-task    # le tasks.md da feature corrente
```

---
skill: review-task
category: uso
text: Use /review-task para um relatorio de status do backlog — identifica tarefas concluidas, em andamento, bloqueadas e prontas para comecar na proxima onda.
---
Para saber o que fazer a seguir:

```
/review-task
```

Retorna: progresso por fase, proximas tarefas desbloqueadas, tarefas criticas
pendentes e estimativa de conclusao. Ideal para comecar cada sessao de trabalho.

---
skill: review-task
category: gotcha
text: O /review-task reporta status — nao executa tarefas. Para executar, use /execute-task com o ID da proxima tarefa sugerida pelo review.
---
Fluxo correto:

```
/review-task        # identifica: "proxima tarefa: 3.2"
/execute-task 3.2   # executa a tarefa 3.2
/review-task        # confirma que 3.2 esta marcada [x]
```

---
skill: review-task
category: avancado
text: O /review-task detecta drift entre tarefas marcadas [x] e codigo realmente presente no repo — use apos retomadas de sessao para garantir consistencia.
---
Apos retomar uma feature depois de varios dias:

```
/review-task
```

A skill compara checkboxes [x] do tasks.md com git diff para detectar:
tarefas marcadas sem codigo correspondente, ou codigo presente sem [x].
Corrige drift documental antes de continuar o backlog.

---
skill: specify
category: uso
text: Use /specify para converter uma descricao em linguagem natural em uma spec SDD estruturada — user stories, requisitos funcionais e criterios de sucesso.
---
Para iniciar uma nova feature:

```
/specify "sistema de notificacoes push para usuarios mobile com suporte
a categorias e preferencias de silencio"
```

Gera spec.md com: user stories priorizadas (P1-P4), requisitos funcionais
(FR-NNN), criterios de sucesso mensuraveleis (SC-NNN) e edge cases.

---
skill: specify
category: gotcha
text: O /specify cria specs — use /clarify para refinar uma spec ja existente.
---
```
# Para spec nova:
/specify "descricao da feature"

# Para refinar spec existente:
/clarify   # opera em spec.md ja criada
```

---
skill: specify
category: avancado
text: Para features com restricoes tecnicas conhecidas, inclua-as na descricao inicial — o specify as captura como constraints nos requisitos nao-funcionais em vez de descobri-las na fase de clarify.
---
```
/specify "CLI POSIX para exibicao de dicas das skills do toolkit.
Constraints: POSIX sh puro (sem bash-isms), sem dependencias externas,
fail-silent absoluto (nunca interrompe onda), RNG via /dev/urandom+awk."
```

Constraints na descricao inicial viram requisitos nao-funcionais explicitamente
na spec, evitando surpresas durante o plan e a implementacao.

---
skill: validate-docs-rendered
category: uso
text: Use /validate-docs-rendered para verificar que os documentos RENDERIZAM corretamente — Mermaid parseavel, links internos resolvem, frontmatter YAML valido, code blocks com linguagem.
---
Antes de fazer push de documentacao:

```
/validate-docs-rendered
```

Verifica: diagramas Mermaid com sintaxe valida, links internos que nao
resultam em 404, frontmatter YAML consistente, code blocks com linguagem
especificada. Complementa /validate-documentation (que valida conteudo textual).

---
skill: validate-docs-rendered
category: gotcha
text: O /validate-docs-rendered valida RENDERIZACAO — nao valida conteudo textual (use /validate-documentation) nem consistencia cross-artifact (use /analyze).
---
```
# Para verificar se Mermaid renderiza, links funcionam:
/validate-docs-rendered

# Para verificar qualidade/completude textual de um documento:
/validate-documentation docs/specs/minha-feature/spec.md

# Para verificar consistencia entre spec/plan/tasks:
/analyze
```

---
skill: validate-documentation
category: uso
text: Use /validate-documentation para verificar a qualidade e completude de um documento individual — estrutura, secoes obrigatorias, sem TBDs, sem ambiguidades obvias.
---
Para validar a spec antes de avancar para plan:

```
/validate-documentation docs/specs/minha-feature/spec.md
```

Verifica: secoes obrigatorias presentes, sem "TBD" sem resolucao, requisitos
com criterios de aceitacao, user stories com cenarios de teste. Retorna lista
de gaps a resolver.

---
skill: validate-documentation
category: gotcha
text: O /validate-documentation valida um unico documento — para validar consistencia entre multiplos artefatos use /analyze.
---
```
# Para um documento:
/validate-documentation docs/specs/minha-feature/spec.md

# Para consistencia entre spec + plan + tasks + constitution:
/analyze
```

# ============================================================
# SECAO 2: Skills Go (7 skills)
# ============================================================

---
skill: commit
category: uso
text: Use /commit para criar um commit bem estruturado com mensagem convencional — a skill analisa o diff e gera mensagem seguindo as convencoes do projeto automaticamente.
---
Apos implementar uma mudanca:

```
/commit
```

A skill le o git diff, identifica o tipo de mudanca (feat/fix/docs/refactor),
gera uma mensagem convencional concisa e faz o commit. Lida com submodulos
e mudancas multi-servico.

---
skill: commit
category: gotcha
text: O /commit cria commits de mudancas staged e unstaged — verifique o que esta no working tree antes, para nao commitar arquivos indesejados (.env, secrets).
---
Antes de usar /commit:

```bash
git status        # verificar o que sera incluido
git diff --stat   # resumo das mudancas
```

O /commit nao filtra automaticamente arquivos sensiveis — certifique-se de
que .gitignore esta configurado corretamente para .env e credentials.

---
skill: go-add-consumer
category: uso
text: Use /go-add-consumer para adicionar um consumer RabbitMQ completo a um microsservico GOB — gera handler, wiring e configuracao seguindo as convencoes do projeto.
---
Para adicionar consumer de eventos em um servico GOB:

```
/go-add-consumer order-created payments-service
```

Gera: consumer handler, binding de exchange/queue, configuracao de retentativas,
dead-letter queue e wiring no container de dependencias. Segue convencoes GOB.

---
skill: go-add-consumer
category: gotcha
text: O /go-add-consumer e especifico para microsservicos GOB com RabbitMQ — nao use para outros brokers (Kafka, SQS) ou arquiteturas sem o padrao GOB.
---
O /go-add-consumer assume a estrutura GOB:

```
internal/
  consumers/     # onde o consumer e adicionado
  container/     # wiring automatico aqui
```

Para Kafka ou SQS, implemente manualmente seguindo o padrao do projeto.

---
skill: go-add-entity
category: uso
text: Use /go-add-entity para adicionar um CRUD vertical completo (domain, DTO, repository, service, handler, migration, factory wiring) a um microsservico GOB.
---
Para adicionar entidade Product ao servico de catalogo:

```
/go-add-entity Product catalog-service
```

Gera: domain model, DTOs de request/response, repository interface + implementacao
PostgreSQL, service com regras de negocio, handler REST, migration SQL e wiring
no container. Tudo seguindo convencoes GOB.

---
skill: go-add-entity
category: gotcha
text: O /go-add-entity gera o scaffold completo — ajuste regras de negocio especificas e validacoes apos a geracao, nao antes.
---
Fluxo correto:

```
# 1. Gerar scaffold:
/go-add-entity Order orders-service

# 2. Ajustar regras de negocio especificas:
# Editar internal/domain/order.go para adicionar validacoes de negocio
# Editar internal/service/order_service.go para logica customizada
```

Nao tente customizar antes de gerar — o scaffold ja cobre o padrao GOB
e voce so precisa adicionar o que e especifico do negocio.

---
skill: go-add-migration
category: uso
text: Use /go-add-migration para criar arquivos de migration PostgreSQL corretamente nomeados para microsservicos GOB — UP e DOWN com timestamp e descricao.
---
Para adicionar uma nova tabela:

```
/go-add-migration create_orders_table orders-service
```

Cria: `migrations/YYYYMMDDHHMMSS_create_orders_table.up.sql` e
`migrations/YYYYMMDDHHMMSS_create_orders_table.down.sql` com schema padrao.

---
skill: go-add-migration
category: gotcha
text: Sempre escreva o DOWN migration correto — migrations sem DOWN impedem rollback em producao e bloqueiam o pipeline de deploy.
---
Template obrigatorio:

```sql
-- UP: sempre reversivel
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ...
);

-- DOWN: sempre o inverso exato do UP
DROP TABLE IF EXISTS orders;
```

Migrations sem DOWN (ou com DOWN vazio) bloqueiam rollback. A skill gera
o template — voce e responsavel por completar o DOWN corretamente.

---
skill: go-add-test
category: uso
text: Use /go-add-test para gerar esqueleto de testes para handler/service em microsservico GOB — seguindo convencoes do projeto com mocks e assertions padronizados.
---
Para adicionar testes ao OrderService:

```
/go-add-test internal/service/order_service.go orders-service
```

Gera: arquivo de teste com casos happy path e error path, mocks de
dependencias via interfaces, e assertions seguindo o padrao GOB.

---
skill: go-add-test
category: gotcha
text: O /go-add-test gera o ESQUELETO de testes — adicione os casos de teste especificos do negocio manualmente apos a geracao.
---
Apos /go-add-test:

```go
// Gerado automaticamente — adicione casos especificos:
func TestOrderService_Create_DuplicateOrderNumber(t *testing.T) {
    // Arrange: setup de ordem duplicada
    // Act: tentar criar segunda ordem com mesmo numero
    // Assert: erro ErrDuplicateOrderNumber
}
```

A skill cobre happy path e error path genericos — casos de borda especificos
de negocio sao sua responsabilidade.

---
skill: go-review-pr
category: uso
text: Use /go-review-pr antes de abrir um PR em projeto GOB — revisa apenas o diff do branch contra convencoes GOB (naming, wiring, migrations, error handling).
---
Antes de abrir o PR:

```
/go-review-pr
```

Analisa somente o que mudou no branch (diff-aware), verifica conformidade
com convencoes GOB e lista findings por severidade. Mais rapido que /go-review-service
porque nao relei o codebase inteiro.

---
skill: go-review-pr
category: gotcha
text: O /go-review-pr e diff-aware e foca em convencoes GOB — para revisao de seguranca use /owasp-security, para correctness use /code-review.
---
```
# Para convencoes GOB no diff:
/go-review-pr

# Para seguranca no diff:
/owasp-security

# Para correctness + reuse no diff:
/code-review

# Para auditoria completa do servico (nao so o diff):
/go-review-service
```

---
skill: go-review-service
category: uso
text: Use /go-review-service para uma auditoria completa de um microsservico GOB contra todas as convencoes do projeto — nao apenas o diff.
---
Para auditoria completa do servico de pagamentos:

```
/go-review-service payments-service
```

Relei todo o servico e verifica: estrutura de diretorios, naming, wiring,
tratamento de erros, migrations, testes existentes. Mais completo que /go-review-pr
mas mais lento — use antes de releases ou apos refatoracoes grandes.

---
skill: go-review-service
category: gotcha
text: O /go-review-service le o codebase inteiro — pode ser lento para servicos grandes. Para revisao rapida pre-PR, use /go-review-pr que e diff-aware.
---
```
# Rapido (so o diff, pre-PR):
/go-review-pr

# Completo (codebase inteiro, pre-release):
/go-review-service payments-service
```
