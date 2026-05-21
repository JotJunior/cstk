---
name: briefing
description: 'Structured project discovery interview (vision, users, constraints, stack). Triggers: "briefing", "discovery", "iniciar projeto", "kickoff". Skip if briefing already complete and user did not ask for update.'
argument-hint: "[descricao inicial do projeto ou vazio para entrevista completa]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
---

# Skill: Briefing de Projeto

Conduza uma entrevista estruturada de discovery para capturar a essencia do projeto,
produzindo um documento de briefing que serve de fundacao para todos os artefatos SDD.

## Pre-requisitos

Nenhum. Esta e tipicamente a primeira skill do pipeline SDD para novos projetos.
Se ja existe um briefing, esta skill pode atualiza-lo.

## Proximos passos

Apos salvar o briefing, o fluxo sugerido e:

1. `/constitution` — derivar principios de governanca a partir do briefing
2. `/specify` — especificar as features do MVP identificadas no briefing
3. `/initialize-docs` (se ainda nao feito) — garantir estrutura padrao de docs/

## Argumentos

$ARGUMENTS

---

## FLUXO DE EXECUCAO

```
1. CONTEXTO        Detectar projeto e artefatos existentes
     |
2. TRIAGEM         Determinar profundidade da entrevista
     |
3. ENTREVISTA      Perguntas estruturadas por dimensao (interativo)
     |
4. SINTESE         Consolidar respostas em documento de briefing
     |
5. VALIDACAO       Confirmar com usuario antes de salvar
     |
6. SALVAMENTO      Salvar e recomendar proximos passos
```

---

## ETAPA 1: CONTEXTO

### 1.1 Detectar Projeto

Leia os seguintes arquivos (se existirem) para entender o que ja se sabe:

```
SEMPRE LER (se existirem):
-- README.md
-- CLAUDE.md
-- docs/01-briefing-discovery/*.md (briefings anteriores)
-- docs/constitution.md
-- docs/specs/*/spec.md (specs existentes)
-- package.json, go.mod, pyproject.toml, Cargo.toml (stack tecnica)
```

### 1.2 Verificar Briefing Existente

Procurar briefings existentes:
1. `docs/01-briefing-discovery/briefing.md`
2. `docs/01-briefing-discovery/BRIEFING-*.md`
3. `docs/briefing.md`

Se encontrado:
- Carregar conteudo atual
- Identificar secoes incompletas ou marcadas com TODO
- Perguntar ao usuario: "Encontrei um briefing existente. Deseja **atualizar** ou **criar um novo**?"

Se nao encontrado:
- Seguir para entrevista completa (Etapa 2)

---

## ETAPA 2: TRIAGEM

### 2.1 Analisar Input

Analise $ARGUMENTS e o contexto coletado:

| Cenario | Acao |
|---------|------|
| Argumento vazio, projeto vazio | Entrevista COMPLETA (todas as dimensoes) |
| Argumento vazio, projeto existente | Entrevista FOCADA (apenas gaps detectados) |
| Argumento com descricao do projeto | Entrevista ADAPTADA (preencher o que falta da descricao) |
| Argumento com caminho para documento | Extrair contexto do documento + entrevista complementar |

### 2.2 Preencher o que ja se sabe

Para cada dimensao da entrevista, verificar se a informacao ja existe no contexto:
- Se inferivel de arquivos do projeto: preencher e marcar como `[inferido]`
- Se explicita no argumento: preencher e marcar como `[fornecido]`
- Se desconhecida: incluir na fila de perguntas

### 2.3 Calcular Fila de Perguntas

- **Entrevista completa**: ate 10 perguntas (todas as dimensoes)
- **Entrevista focada/adaptada**: apenas gaps, max 7 perguntas
- Nunca exceder 10 perguntas no total

---

## ETAPA 3: ENTREVISTA

### 3.1 Dimensoes de Discovery

A entrevista cobre 7 dimensoes, com 1-2 perguntas cada. O roteiro completo
(texto de cada pergunta, exemplos, formatos, regras) esta em
`references/discovery-guide.md`. Consultar sob demanda em vez de memorizar.

Dimensoes:

1. **Visao e Proposito** — elevator pitch
2. **Usuarios e Stakeholders** — atores e quem decide
3. **Escopo e Prioridades** — MVP vs pos-MVP, trade-offs
4. **Restricoes** — prazo, equipe, budget, tech
5. **Contexto Tecnico** — stack, infra, integracoes
6. **Qualidade e Padroes** — testes, seguranca, observabilidade, compliance
7. **Visao de Futuro** — evolucao em 6-12 meses

**Perguntas sao feitas UMA POR VEZ**, aguardando resposta antes de avancar.

### 3.2 Regras da Entrevista

Ver detalhamento em `references/discovery-guide.md#regras-da-entrevista`.
Resumo: uma pergunta por vez, maximo 10 total, adaptar ao contexto, confirmar
inferencias, nao julgar respostas.

### 3.3 Transicao entre Perguntas

Apos cada resposta:
- Agradecer brevemente (1 linha max, sem ser efusivo)
- Se a resposta levantar aspecto nao coberto: adicionar pergunta de follow-up (dentro do limite)
- Apresentar proxima pergunta

---

## ETAPA 4: SINTESE

### 4.1 Template do Briefing

Apos encerrar a entrevista, consolidar todas as respostas usando
`templates/briefing.md` (mesmo diretorio desta skill). Estrutura:

1. Visao e Proposito
2. Usuarios e Stakeholders
3. Escopo (MVP / Pos-MVP / Fora de Escopo)
4. Prioridades e Trade-offs
5. Restricoes (prazo, equipe, budget, tecnica)
6. Stack Tecnica
7. Qualidade e Padroes
8. Visao de Futuro
+ Itens a Definir (pendencias)

### 4.2 Regras de Sintese

- **Usar as palavras do usuario** — nao reescrever em jargao tecnico
- **Marcar inferencias** — se algo foi inferido (nao dito explicitamente), indicar com `[inferido]`
- **Marcar pendencias** — itens sem resposta vao para "Itens a Definir"
- **Remover secoes vazias** — se dimensao inteira nao se aplica, remover (nao deixar "N/A")
- **Nao inventar** — se o usuario nao mencionou, nao adicionar

---

## ETAPA 5: VALIDACAO

### 5.1 Apresentar Resumo

Antes de salvar, apresentar ao usuario um resumo executivo:

```markdown
## Resumo do Briefing

**Projeto**: [Nome]
**Resumo**: [1-2 frases]
**Atores**: [N] identificados
**Features MVP**: [N] features
**Stack**: [resumo da stack]
**Restricoes criticas**: [lista curta]
**Itens a definir**: [N] pendencias

Deseja que eu salve este briefing? Ou ha algo a corrigir/complementar?
```

### 5.2 Iterar se Necessario

- Se usuario pedir correcoes: aplicar e re-apresentar resumo
- Se usuario pedir mais perguntas: retomar entrevista (respeitando limite de 10)
- Se usuario aprovar: prosseguir para salvamento

---

## ETAPA 6: SALVAMENTO

### 6.1 Criar Diretorio

Se `docs/01-briefing-discovery/` nao existir, criar.

### 6.2 Salvar Briefing

Salvar em `docs/01-briefing-discovery/briefing.md`.

Se ja existe um briefing:
- Salvar como `docs/01-briefing-discovery/briefing-[DATE].md`
- Ou sobrescrever se usuario pediu atualizacao

### 6.3 Reportar

```markdown
## Briefing Salvo

**Arquivo**: docs/01-briefing-discovery/briefing.md
**Dimensoes cobertas**: [N]/7
**Itens a definir**: [N]

### Proximos Passos (fluxo SDD recomendado)

1. `/constitution` — Definir principios de governanca baseados no briefing
2. `/specify [feature]` — Especificar features do MVP identificadas
3. `/clarify` — Resolver ambiguidades nas specs geradas
4. `/plan` — Gerar planos tecnicos de implementacao
5. `/create-tasks` — Decompor planos em tarefas executaveis
```

---

## Pre-flight de Bootstrap (apos briefing + plan)

Stacks multi-workspace (monorepo npm/pnpm, Go modules multiplos, Cargo
workspaces, etc) historicamente geram um bloqueio humano cirurgico
`npm install` por workspace — 5 bloqueios em uma so execucao na rodada
de validacao do agente-00c. Cada bloqueio tem mesmo formato e mesma
resposta. Atrito mecanico previsivel deve ser amortizado em batch,
nao resolvido onda-a-onda.

Quando o briefing identificar stack multi-workspace, o agente DEVE
materializar um script de bootstrap antes de declarar o briefing
concluido:

### Passos

1. Identificar workspaces declarados (lendo `plan.md §Project Structure`
   se ja existe, ou pedindo ao usuario no proprio briefing).
2. Gerar `scripts/bootstrap-deps.sh` na raiz do projeto-alvo com uma
   linha por workspace agrupando as dependencias canonicas. Formato:

   ```sh
   #!/bin/sh
   # bootstrap-deps.sh — pre-flight de dependencias para evitar bloqueios
   # cirurgicos npm install no meio da pipeline agente-00c.
   #
   # Rode UMA VEZ antes de /agente-00c (ou apos /initialize-docs).
   #
   # Gerado por: briefing skill (pre-flight de bootstrap)
   # Data: <ISO>
   # Workspaces: <lista>

   set -eu

   echo "==> auth-service"
   npm install --workspace=services/auth-service \
     express@5 zod@3 jsonwebtoken pino

   echo "==> frontend-staff"
   npm install --workspace=services/frontend-staff \
     react@18 react-dom@18 @tanstack/react-query @radix-ui/react-dialog

   # ...
   ```

   Para monorepos com `package.json` na raiz que ja declara workspaces,
   uma alternativa equivalente e listar `npm install` (raiz) +
   `npm install --workspace=<nome> <dep>` para cada workspace.

3. Adicionar nota no `briefing.md` (secao "Setup / Bootstrap"):

   > **Pre-flight obrigatorio**: rode `bash scripts/bootstrap-deps.sh`
   > UMA VEZ antes de invocar `/agente-00c`. Stacks multi-workspace
   > exigem instalacao de dependencias previa para evitar N bloqueios
   > humanos cirurgicos durante a pipeline (FR-018 nao permite
   > `npm install` autonomo).

4. Se o briefing identifica que o projeto **NAO** e multi-workspace,
   pular esse passo — `bootstrap-deps.sh` so faz sentido quando ha 2+
   workspaces. Para single-package, o agente lida com `npm install`
   onda-a-onda sem atrito amplificado.

### Quando aplicar

| Sinal | Aplicar pre-flight? |
|-------|---------------------|
| `package.json` declara `workspaces: [...]` | Sim |
| Multiplos `package.json` em subdiretorios | Sim |
| Go modules multiplos (`go.work`) | Sim (com `go mod download` por modulo) |
| Cargo workspace (`Cargo.toml [workspace]`) | Sim (com `cargo fetch -p <crate>`) |
| Repo single-package | Nao |

### Quando NAO aplicar

- Projetos puramente documentais (sem `package.json`, `go.mod`, etc).
- Briefing identifica que a stack ainda nao esta decidida — gerar
  `bootstrap-deps.sh` antes da decisao de stack vira lixo. Aplicar apos
  o `plan.md` materializar `§Project Structure`.

### Criterio de aceitacao

Apos briefing salvo, executar `bash scripts/bootstrap-deps.sh` (se
gerado) instala todas as dependencias com zero erros. A primeira onda
do `/agente-00c` NAO encontra bloqueio `npm install`.

---

## DIRETRIZES RAPIDAS

- **Entrevista, nao interrogatorio** — tom conversacional, sem pressao
- **Capturar, nao julgar** — o briefing registra; o `/advisor` critica
- **Adaptar, nao seguir cegamente** — se o projeto e simples, pular dimensoes irrelevantes
- **Priorizar MVP** — focar no que importa AGORA, nao no que pode importar depois
- **Respeitar o usuario** — se ele ja sabe o que quer, nao forcar reflexao desnecessaria
- **Alimentar o pipeline** — o briefing deve ser util para `/constitution` e `/specify`

### Relacao com Outras Skills

| Skill | Relacao com Briefing |
|-------|---------------------|
| `constitution` | Consome briefing para derivar principios de governanca |
| `specify` | Consome briefing para contextualizar features |
| `clarify` | Pode refinar ambiguidades do briefing se necessario |
| `advisor` | Pode criticar decisoes registradas no briefing |
| `plan` | Usa briefing como contexto tecnico de alto nivel |
| `initialize-docs` | Cria o diretorio onde o briefing e salvo |

---

## Gotchas

### Uma pergunta por vez — aguardar resposta antes de avancar

Despejar 7 perguntas de uma vez quebra a entrevista. O valor esta no ciclo pergunta-resposta-reflexao-proxima. Enviar bloco significa que o usuario responde em batch, sem reflexao.

### Maximo 10 perguntas TOTAL

Nao exceda por "mais uma coisa importante". Se 10 nao resolveram, registre o que tem e marque o resto como "A Definir" — o briefing e draft, pode ser atualizado depois.

### Inferencias devem ser marcadas `[inferido]` e confirmadas

Quando preencher algo derivado do codigo (ex: stack detectada de `go.mod`), marque `[inferido]` e confirme com uma linha: "Detectei X, correto?". Assumir sem confirmar e arriscar registrar premissa errada como fato.

### Se o usuario responder varias dimensoes de uma vez, registre TODAS

Usuario pragmatico frequentemente responde em texto corrido cobrindo 3 dimensoes. Capture tudo e pule as perguntas equivalentes — nao repita o que ja foi dito so para seguir o roteiro.

### NAO julgar respostas — briefing registra, advisor critica

Se o usuario diz "vou lancar sem testes para ganhar velocidade", registre fielmente. Criticar aqui quebra a confianca da entrevista. A critica e papel do `/advisor`, se o usuario pedir.

### Remover secoes inteiras quando a dimensao nao se aplica

Se o projeto e uma biblioteca interna sem usuarios finais, remover a secao "Usuarios e Stakeholders" em vez de deixar "N/A". Secoes vazias sao ruido para `/constitution` e `/specify` downstream.

### Nunca reescrever em jargao tecnico

Usar as palavras do usuario. Se ele disse "app de caixa", nao trocar por "sistema de ponto-de-venda transacional". O briefing preserva linguagem; o `/plan` traduz em tecnico.
