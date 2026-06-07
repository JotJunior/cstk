---
name: cstk-specify
description: "Convert a natural-language feature description into SDD spec (user stories, FRs, success criteria). Triggers: \"specify\", \"criar spec\", \"nova feature\", \"feature spec\". Skip for refining an existing spec (clarify)."
---

# CSTK Adaptation

Adapted from `JotJunior/cstk` skill `specify` at commit `35922cf`.
Use this as a Codex skill; follow local repository instructions and Codex tool names when source text mentions Claude-specific commands or slash commands.

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

the user's request

---

## Leitura de artefatos foundational (briefing + constitution)

Antes de ler `docs/01-briefing-discovery/briefing.md` ou `docs/constitution.md`
direto do disco, verifique se ha cache valido populado pelo agente-00c
ou feature-00c. Aditivo — se nao houver cache, leia direto do disco
conforme comportamento padrao (FR-CACHE-014).

1. **Detectar agente ativo**: variavel `AGENTE_00C_STATE_DIR` setada,
   OU `<projeto-alvo>/.codex/agente-00c-state/state.json` existente,
   OU `<projeto-alvo>/.codex/feature-00c-state/<short>/state.json`.

2. **Se ativo**, tente consumir o resumo via Bash:
   ```bash
   ~/.codex/skills/cstk-agente-00c-runtime/scripts/state-cache.sh get-resumo \
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
   ~/.codex/skills/cstk-agente-00c-runtime/scripts/state-cache.sh metrics-bump \
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

### 0.1 Classificar o pedido

Analise `the user's request` e classifique em uma das categorias:

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

**NUNCA prosseguir para ETAPA 1 sem confirmacao explicita do usuario.**
Se o usuario escolher opcao 1 ou 3, encerrar a skill e executar o caminho
escolhido (ou delegar para skill apropriada).

---

## ETAPA 1: ANALISE

### 1.1 Parsear Descricao

Extraia do input (the user's request):
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

## Source License

This skill includes material adapted from `JotJunior/cstk`, licensed under MIT. The copyright and permission notice are included in `references/cstk-license.md`.

