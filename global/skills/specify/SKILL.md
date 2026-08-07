---
name: specify
description: 'Convert a natural-language feature description into SDD spec (user stories, FRs, success criteria). Triggers: "specify", "criar spec", "nova feature", "feature spec". Skip for refining an existing spec (clarify).'
argument-hint: "[descricao da feature em linguagem natural]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
---

# Skill: Especificar Feature (SDD)

Transforme uma descricao em linguagem natural em uma feature spec completa seguindo
o formato Spec-Driven Development. Foco no QUE e POR QUE — nunca no COMO implementar.

## Pre-requisitos

**Opcional mas recomendado**:
- `/briefing` — contextualiza a feature dentro do projeto
- `/constitution` — principios ajudam a calibrar escopo e padroes de qualidade

Sem esses, a skill funciona mas pode precisar de mais `[NEEDS CLARIFICATION]`.

## Proximos passos

1. `/clarify` — resolver ambiguidades da spec (se houver `[NEEDS CLARIFICATION]`)
2. `/plan` — gerar plano tecnico de implementacao
3. `/checklist` — validar qualidade dos requisitos antes de implementar

## Argumentos

$ARGUMENTS

---

## Leitura de artefatos foundational (briefing + constitution)

Antes de ler `docs/briefing.md` (ou o legado
`docs/01-briefing-discovery/briefing.md`) ou `docs/constitution.md`
direto do disco, verifique se ha cache valido populado pelo agente-00c
ou feature-00c. Aditivo — se nao houver cache, leia direto do disco
conforme comportamento padrao (FR-CACHE-014).

1. **Detectar agente ativo**: variavel `AGENTE_00C_STATE_DIR` setada,
   OU `<projeto-alvo>/.claude/agente-00c-state/state.json` existente,
   OU `<projeto-alvo>/.claude/feature-00c-state/<short>/state.json`.

2. **Se ativo**, tente consumir o resumo via Bash:
   ```bash
   ~/.claude/skills/agente-00c-runtime/scripts/state-cache.sh get-resumo \
     --state-dir "$SD" --artifact briefing
   ```
   - **Exit 0** + stdout nao-vazio: use o resumo como conteudo.
   - **Exit 1**: cache miss (campo ausente, estrategia=passthrough,
     drift detectado) — caia em leitura direta.
   - **Exit 2**: erro fatal (state.json corrompido) — aborte com
     diagnostico do stderr.

   Mesmo protocolo para `--artifact constitution`.

3. **Apos consumo** (hit ou miss), registre metrica via:
   ```bash
   ~/.claude/skills/agente-00c-runtime/scripts/state-cache.sh metrics-bump \
     --state-dir "$SD" --tipo <hit|miss-drift|miss-disabled> \
     [--chars-economizados N]
   ```
   onde N = `source_chars - resumo_chars` quando hit, ou 0 caso contrario.

4. **Standalone** (sem state.json): leia direto do disco. Comportamento
   identico a versao pre-cache.

Spec: `docs/specs/_archived/agente-00c-artifact-cache/spec.md` FR-CACHE-008.

---

## FLUXO DE EXECUCAO

```
0. TRIAGEM         Classificar pedido e confirmar relevancia do SDD
     |
1. ANALISE         Parsear descricao e extrair conceitos
     |
2. ESTRUTURA       Criar diretorio e gerar short name
     |
3. ESPECIFICACAO   Preencher template com conteudo concreto
     |
4. VALIDACAO       Checar qualidade contra criterios internos
     |
5. CLARIFICACAO    Resolver ambiguidades criticas com o usuario
     |
6. SALVAMENTO      Salvar e reportar proximos passos
```

---

## ETAPA 0: TRIAGEM (OBRIGATORIA ANTES DE PROSSEGUIR)

Antes de gerar qualquer artefato, classifique o pedido e valide com o usuario
se o fluxo SDD completo faz sentido para o escopo. O fluxo SDD (spec → clarify
→ plan → tasks) tem custo real e nem todo pedido justifica esse overhead.

### 0.0 Atalho de modo autonomo (agente-00c / feature-00c)

A confirmacao interativa de 0.1-0.3 pressupoe um usuario presente para
responder o menu. Em execucao autonoma nao ha — e a triagem JA aconteceu:
o operador decidiu rodar a pipeline SDD completa quando invocou
`/agente-00c` ou `/feature-00c`.

1. **Detectar execucao autonoma ativa** — mesmos sinais da secao "Leitura
   de artefatos foundational", com um refinamento para os state.json em
   disco: exigir status ATIVO (um state antigo/concluido no repo NAO pode
   pular a triagem de uma invocacao manual):
   - `AGENTE_00C_STATE_DIR` setada; OU
   - `<projeto-alvo>/.claude/agente-00c-state/state.json` com
     `.execution.status` em {`em_andamento`, `aguardando_humano`}; OU
   - `<projeto-alvo>/.claude/feature-00c-state/<short>/state.json` com
     `.execution.status` em {`em_andamento`, `aguardando_humano`}.

2. **Se detectado**: a invocacao pelo orquestrador pai VALE como a
   confirmacao explicita exigida em 0.3 (equivalente a escolher a opcao 2,
   "Criar feature SDD completa"). NAO apresentar o menu nem aguardar
   resposta. Executar 0.1 mesmo assim (classificacao e barata e util como
   auditoria), registrar o pressuposto em UMA linha no output e prosseguir
   direto a ETAPA 1:

   ```
   Triagem 0.0: modo autonomo detectado (<sinal>) — confirmacao herdada
   da invocacao do orquestrador; classificacao: <categoria>.
   ```

   Se a classificacao 0.1 resultar em **Bugfix** ou **Refactor**, NAO
   abortar nem trocar de skill: a decisao de rodar a pipeline foi do
   operador. Apenas registrar a divergencia na mesma linha
   (`classificacao: bugfix — divergencia registrada para auditoria`) para
   aparecer no sumario da onda.

3. **Se NAO detectado**: seguir 0.1-0.3 normalmente (fluxo interativo).

### 0.1 Classificar o pedido

Analise `$ARGUMENTS` e classifique em uma das categorias:

- **Feature nova**: comportamento/capacidade que o sistema nao tem hoje,
  com multiplos atores, fluxos ou regras de negocio → SDD completo se paga.
- **Ajuste/extensao pontual**: mudanca pequena em feature existente, uma
  regra nova, um campo a mais → SDD provavelmente e overkill.
- **Bugfix**: correcao de comportamento incorreto → NAO usar specify,
  sugerir a skill `bugfix`.
- **Refactor/tarefa tecnica**: mudanca interna sem impacto funcional
  observavel → NAO usar specify, sugerir execucao direta ou `execute-task`.

### 0.2 Avaliar relevancia do SDD

Considere sinais de que o SDD completo vale o custo:
- Feature tem 2+ user stories independentes? 
- Envolve multiplos atores ou papeis?
- Tem regras de negocio ou edge cases nao triviais?
- Precisa alinhar stakeholders antes de implementar?
- Vai gerar backlog de tarefas para mais de uma sessao de trabalho?

Se a maioria e "nao", provavelmente o pedido pode ser resolvido inline ou
com um UC/ADR pontual, sem passar pelo pipeline SDD.

### 0.3 Apresentar a analise e deixar o usuario decidir

Antes de criar diretorio ou arquivos, apresentar ao usuario:

```markdown
## Triagem do pedido

**Classificacao**: [Feature nova | Ajuste pontual | Bugfix | Refactor]

**Analise de relevancia SDD**:
- [Justificar por que vale ou nao vale gerar spec completa]
- [Citar sinais especificos do pedido]

**Opcoes**:

1. **Executar direto** — resolver o pedido sem gerar artefatos SDD
   (recomendado se: escopo pequeno, bugfix, refactor, ajuste inline)
2. **Criar feature SDD completa** — gerar spec + seguir pipeline
   (recomendado se: feature com stories multiplas, stakeholders, backlog)
3. **Alternativa sugerida**: [ex: criar UC classico, ADR, rodar bugfix]

Qual caminho prefere?
```

**NUNCA prosseguir para ETAPA 1 sem confirmacao explicita do usuario** —
unica excecao: o atalho 0.0, onde a confirmacao e herdada da invocacao do
orquestrador. Se o usuario escolher opcao 1 ou 3, encerrar a skill e
executar o caminho escolhido (ou delegar para skill apropriada).

### 0.4 Atualizar spec existente vs abrir feature nova

Antes de criar qualquer artefato (mesmo apos o usuario confirmar "Feature
nova" em 0.3), verifique se o pedido de fato pede uma feature nova ou se e
um refinamento de uma spec ja existente do portfolio (`docs/specs/*/spec.md`,
excluindo `_archived/`):

- **Mesma intencao / refinamento** — o pedido mantem os mesmos
  atores/objetivo de uma spec existente e apenas adiciona detalhe, ajusta
  escopo ou corrige um requisito dela → recomende **atualizar** essa
  `spec.md` existente (ela pode entrar em `clarify` para incorporar o
  ajuste) em vez de abrir um diretorio novo.
- **Intencao mudou / escopo expandiu** — o pedido introduz atores novos,
  uma capacidade nao relacionada ao objetivo original de nenhuma spec
  existente, ou expande o escopo alem do que qualquer spec ja ratificada
  cobre → prossiga com a **feature nova** normalmente.
- **Nenhuma spec existente se relaciona ao pedido** (caso mais comum) →
  prossiga direto para a feature nova, **sem** overhead de comparacao
  spec-a-spec — este criterio so se aplica quando ha candidata plausivel.

Ao recomendar "atualizar spec existente", **cite o criterio aplicado**
explicitamente na resposta ao usuario, por exemplo:

```
Este pedido parece um refinamento de `docs/specs/{existing}/spec.md`
(mesma intencao/objetivo, apenas detalha escopo) — recomendo atualizar
essa spec via /clarify em vez de abrir uma feature nova. Prefere seguir
assim ou ainda quer uma feature nova separada?
```

O mesmo criterio e aplicado pela skill `clarify` (ver
`global/skills/clarify/SKILL.md` ETAPA 2) quando a ambiguidade levantada
durante a clarificacao poderia, de fato, constituir uma feature nova.

---

## ETAPA 1: ANALISE

### 1.1 Parsear Descricao

Extraia do input ($ARGUMENTS):
- **Atores**: Quem usa a feature (usuarios, admins, sistemas)
- **Acoes**: O que a feature permite fazer
- **Dados**: Que entidades/informacoes estao envolvidas
- **Restricoes**: Limites, regras, condicoes

### 1.2 Ler Contexto do Projeto

```
SEMPRE LER (se existirem):
-- README.md
-- CLAUDE.md
-- docs/constitution.md (para alinhar com principios)
-- docs/specs/ (para verificar IDs existentes e evitar duplicatas)
```

---

## ETAPA 2: ESTRUTURA

### 2.1 Gerar Short Name

Crie um nome curto (2-4 palavras, kebab-case) que capture a essencia da feature:
- Formato acao-substantivo quando possivel
- Preservar termos tecnicos e siglas
- Exemplos:
  - "Quero adicionar autenticacao de usuario" → `user-auth`
  - "Implementar integracao OAuth2 para a API" → `oauth2-api-integration`
  - "Criar dashboard de analytics" → `analytics-dashboard`

### 2.2 Criar Diretorio

Criar `docs/specs/{short-name}/` (ou caminho sugerido pelo usuario).

---

## ETAPA 3: ESPECIFICACAO

### 3.1 Template da Feature Spec

Ler o template em `templates/feature-spec.md` (mesmo diretorio desta skill) e
preencher com conteudo concreto derivado da descricao. Estrutura:

- **User Scenarios & Testing** — stories priorizadas (P1..Pn) + edge cases
- **Requirements** — functional requirements e key entities
- **Success Criteria** — measurable outcomes, technology-agnostic

Para ver exemplos de spec bem escrita vs mal escrita:
- `examples/spec-good.md` — ilustra stories independentes, success criteria mensuraveis, zero detalhes de implementacao
- `examples/spec-bad.md` — catalogo de anti-patterns (jargao tecnico em SC, stories acopladas, adjetivos vagos, excesso de [NEEDS CLARIFICATION])

### 3.2 Regras de Preenchimento

**User Stories:**
- Priorizadas como jornadas de usuario ordenadas por importancia
- Cada story deve ser INDEPENDENTEMENTE TESTAVEL
- Se implementar apenas UMA story, ainda deve haver um MVP viavel
- Adicionar quantas stories forem necessarias (P1, P2, P3, P4...)

**Functional Requirements:**
- Cada requisito deve ser testavel
- Foco no QUE o sistema faz, nao COMO implementar
- Usar defaults razoaveis para detalhes nao especificados:
  - Retencao de dados: praticas padrao da industria
  - Performance: expectativas padrao para web/mobile
  - Tratamento de erros: mensagens user-friendly com fallbacks
  - Autenticacao: session-based ou OAuth2 para web apps
- Para ambiguidades criticas, marcar com `[NEEDS CLARIFICATION: pergunta especifica]`
- **MAXIMO 3 marcadores [NEEDS CLARIFICATION]** no total
- Prioridade de clarificacao: escopo > seguranca > UX > detalhes tecnicos

> **INEGOCIAVEL — defaults NAO valem para dado factual (Constitution VI).** A regra
> "usar defaults razoaveis" acima cobre POLITICAS de design nao especificadas (retencao,
> performance, tratamento de erro, auth). Ela **NUNCA** autoriza inventar dado factual de
> um sistema externo: nomes de propriedades de payload, assinaturas de request/response,
> URLs/endpoints/querystrings, valores concretos (financeiros, status, IDs, datas). Esses
> so entram na spec se vierem de fonte rastreavel (codigo, OpenAPI, doc, resposta real).
> Sem fonte → `[NEEDS CLARIFICATION]`; nunca um nome de campo ou endpoint suposto.

**Decisoes de Infraestrutura Auditaveis (obrigatorio para features
com runtime de longo prazo):**

Features que envolvem schedulers, sessoes persistentes, refresh de
tokens externos ou rotacao de chaves DEVEM declarar essas politicas
como FRs explicitos no spec — NAO como divida descoberta na execucao.
Razao: a execucao-fonte do agente-00c teve scheduling (sug-016),
encryption key rotation (sug-011) e refresh policy (sug-015)
descobertos na onda-007 como pendencias urgentes; deveriam ter sido
FRs desde o spec.

Checklist minimo (cada item vira FR explicito quando aplicavel):

| Tipo de decisao | FR explicito sugerido | Quando aplicar |
|-----------------|------------------------|----------------|
| Politica de scheduling | `FR-NN-INFRA-SCHED: autoSchedule = 'cron' \| 'wakeup' \| 'manual' \| 'auto' (default <X>)` | Feature dispara trabalho periodico ou agendado |
| Politica de key rotation | `FR-NN-INFRA-KEY: SESSION_ENCRYPTION_KEY suporta versionamento (v1:<base64>, v2:<base64>) — rotacao sem downtime` | Feature criptografa dados persistentes |
| Refresh policy (token externo) | `FR-NN-INFRA-REFRESH: refresh on-demand + job periodico a cada Xmin; gap window aceitavel: Y min` | Feature consome IdP, OAuth, ou recurso com TTL |
| Mutex multi-pod | `FR-NN-INFRA-LOCK: serializacao cross-pod via <pg_try_advisory_xact_lock\|redis lock\|SELECT FOR UPDATE>` | Deploy multi-replica + estado compartilhado |
| Backup / restore | `FR-NN-INFRA-BACKUP: snapshot cron Xh, retencao Yd, restore tested via RB-NNN` | Feature persiste dados criticos |
| Idempotencia | `FR-NN-INFRA-IDEMP: <chave de idempotencia, TTL, scope>` | Feature aceita request retry |

Se a feature NAO toca nenhum desses, anotar explicitamente uma linha
`> Decisoes de infraestrutura: N/A (feature stateless, sem scheduling)`.
NAO deixar implicito — `N/A explicito > silencio`.

**Success Criteria:**
- DEVEM ser mensuráveis (tempo, porcentagem, contagem, taxa)
- DEVEM ser technology-agnostic (sem frameworks, linguagens, databases)
- DEVEM ser user-focused (perspectiva do usuario/negocio)
- DEVEM ser verificaveis sem conhecer detalhes de implementacao

**Exemplos de Success Criteria BEM escritos:**
- "Usuarios completam checkout em menos de 3 minutos"
- "Sistema suporta 10.000 usuarios concorrentes"
- "95% das buscas retornam resultados em menos de 1 segundo"

**Exemplos de Success Criteria MAL escritos (implementation-focused):**
- "API response time under 200ms" (muito tecnico)
- "Database handles 1000 TPS" (detalhe de implementacao)
- "React components render efficiently" (framework-specific)

**Delta Requirements (opcional — secao `## Delta Requirements`):**

Preencher quando a feature adiciona, muda, remove ou renomeia
comportamento HOJE ATIVO do sistema-alvo (algo ja documentado no corpus
canonico `docs/specs/current/`) — contrato completo em
`docs/specs/living-specs/contracts/delta-section-format.md`.

- Antes de declarar uma `### Capability: <slug>` NOVA, rodar
  `ls docs/specs/current/*.md 2>/dev/null` (lista vazia e resultado
  valido — corpus pode nao existir ainda) e reusar o slug ja existente
  sempre que a feature tocar o MESMO conceito, em vez de fragmentar em
  um slug novo semanticamente equivalente (ex.: `commit-mode` vs
  `commit-staging` referindo-se ao mesmo mecanismo). Essa decisao e
  julgamento do autor da spec — a validacao de FORMA do slug fica a
  cargo de `delta-gate.sh`, rodado apenas no momento do archive
  (`specify` nunca invoca o gate diretamente).
- Feature que nao toca comportamento ativo (puramente nova, ou
  doc-only/meta) usa o marcador de Skip em vez dos blocos
  `### Capability:` (mutuamente exclusivos): `**Skip**: <justificativa
  nao-vazia> — <autor>, <YYYY-MM-DD>` — os 3 campos sao obrigatorios.
- Exemplo minimo de bloco preenchido:

  ```markdown
  ## Delta Requirements

  ### Capability: commit-mode

  #### ADDED

  - **FR-018**: Sistema MUST suportar staging por allowlist derivada no
    modo atomic-commit
  ```

---

## ETAPA 4: VALIDACAO

### 4.1 Checklist de Qualidade Interna

Valide a spec contra estes criterios:

- [ ] Nenhum detalhe de implementacao (linguagens, frameworks, APIs)
- [ ] Focado no valor para o usuario e necessidades do negocio
- [ ] Escrito para stakeholders nao-tecnicos
- [ ] Todas as secoes obrigatorias preenchidas
- [ ] Requisitos sao testaveis e nao-ambiguos
- [ ] Success criteria sao mensuráveis
- [ ] Success criteria sao technology-agnostic
- [ ] Acceptance scenarios definidos para todas as stories
- [ ] Edge cases identificados
- [ ] Escopo claramente delimitado

### 4.2 Auto-Correcao

Se itens falham na validacao:
1. Listar itens que falharam e problemas especificos
2. Atualizar a spec para corrigir cada problema
3. Re-validar (max 3 iteracoes)
4. Se ainda falhando apos 3 iteracoes: documentar problemas restantes e avisar usuario

### 4.3 Gate de cobertura de cenarios (requirement-coverage.sh)

Antes de reportar conclusao bem-sucedida (ETAPA 6.2), garanta que o `spec.md`
corrente esteja persistido em `docs/specs/{short-name}/spec.md` (escreva/
atualize o arquivo agora se a 6.1 formal ainda nao rodou) e rode o gate
deterministico:

```bash
global/skills/checklist/scripts/requirement-coverage.sh docs/specs/{short-name}/spec.md
```

- Exit 0 (zero `FINDING`): seguir normalmente para ETAPA 5/6.
- Exit 1 (>=1 `FINDING|error|fr-no-scenario|...`): a falha **impede** o
  relatorio de sucesso da ETAPA 6.2. Reportar cada `FINDING` ao usuario
  (ID exato + sugestao de correcao) e voltar para 3.2/4.2: adicionar um
  Acceptance Scenario ou Edge Case cobrindo os termos centrais do
  requisito apontado, depois re-rodar o gate (mesmo limite de 3 iteracoes
  da 4.2).
- Exit 2 (uso incorreto/arquivo ausente): reportar o erro ao usuario; nao
  bloqueia por si so (indica problema no proprio script ou no path, nao na
  spec).
- Em execucao autonoma (`agente-00c`/`feature-00c`), registrar a invocacao
  via `state-ondas.sh record-skill --skill requirement-coverage --kind gate`
  (script deterministico, nao tool Skill).

---

## ETAPA 5: CLARIFICACAO

### 5.1 Resolver [NEEDS CLARIFICATION]

Se existem marcadores `[NEEDS CLARIFICATION]` na spec:

1. Extrair todos os marcadores
2. Se mais de 3: manter apenas os 3 mais criticos e fazer guesses informados para o resto
3. Para cada marcador, apresentar ao usuario:

```markdown
## Questao [N]: [Topico]

**Contexto**: [Citar secao relevante da spec]

**O que precisamos saber**: [Pergunta especifica]

**Respostas Sugeridas**:

| Opcao | Resposta | Implicacoes |
|-------|----------|-------------|
| A     | [Primeira opcao] | [O que significa para a feature] |
| B     | [Segunda opcao] | [O que significa para a feature] |
| C     | [Terceira opcao] | [O que significa para a feature] |

**Sua escolha**: _[Aguardar resposta]_
```

4. Apos respostas: atualizar spec substituindo marcadores pelas respostas

---

## ETAPA 6: SALVAMENTO

### 6.1 Salvar Spec

Salvar em `docs/specs/{short-name}/spec.md`.

### 6.2 Reportar

```markdown
## Spec Criada

**Feature**: {short-name}
**Arquivo**: docs/specs/{short-name}/spec.md
**Status**: Draft
**User Stories**: {N} stories (P1-P{N})
**Requisitos**: {N} functional requirements
**Clarificacoes pendentes**: {N}

### Proximos Passos

1. `/clarify` — Refinar ambiguidades na spec (se houver NEEDS CLARIFICATION)
2. `/plan` — Gerar plano tecnico de implementacao
```

---

## DIRETRIZES RAPIDAS

- Foco no **QUE** usuarios precisam e **POR QUE**
- Evitar COMO implementar (sem tech stack, APIs, estrutura de codigo)
- Escrito para stakeholders de negocio, nao desenvolvedores
- Quando secao nao se aplica: remover inteiramente (nao deixar como "N/A")
- Pensar como tester: todo requisito vago deve falhar no checklist de qualidade

---

## Gotchas

### ZERO detalhes de implementacao na spec

Sem linguagens, frameworks, APIs, estrutura de codigo, nomes de bibliotecas, classes. A spec responde QUE e POR QUE — o COMO vai para `/plan`. Se aparece "em React" ou "com PostgreSQL" na spec, esta errado.

### Success Criteria devem ser technology-agnostic E mensuraveis

Correto: "Usuario completa checkout em <3 minutos", "95% das buscas retornam <1s", "Sistema suporta 10k usuarios concorrentes".
Errado: "API responde <200ms" (tecnico), "Database aguenta 1000 TPS" (implementacao), "Componentes React renderizam rapido" (framework).

### Maximo 3 `[NEEDS CLARIFICATION]` — priorizar escopo > seguranca > UX > tech

Mais de 3 marcadores indica que a spec deveria voltar ao usuario antes de escrever. Priorize o que impacta corretude e use defaults informados para o resto.

### Cada user story deve ser INDEPENDENTEMENTE TESTAVEL

Se implementar apenas P1 nao ha MVP viavel, as stories estao acopladas demais. Cada story precisa ter valor isolado para o usuario.

### Nao deixar secoes vazias com "N/A"

Se a feature nao envolve entidades de dados, remover a secao "Key Entities" inteira — nao deixar header com "N/A" abaixo. Secoes vazias sao ruido para o `/plan` e `/create-tasks` downstream.

### Defaults razoaveis ao inves de [NEEDS CLARIFICATION] para tudo

Retencao de dados, tratamento de erros padrao, autenticacao web-padrao — se nao critico, use o default da industria e documente a suposicao. Marcar tudo como pendente trava o fluxo.
