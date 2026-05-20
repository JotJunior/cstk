---
name: review-task
description: |
  Use quando o usuario pedir status das tarefas, progresso do projeto,
  relatorio do backlog, ou quiser identificar tarefas prontas para comecar.
  Tambem quando mencionar "revisar tarefas", "status das tarefas", "review
  tasks", "progresso do projeto", "verificar tarefas", "relatorio de tarefas".
  NAO use para executar tarefas (use execute-task) ou criar novas
  (use create-tasks).
allowed-tools:
  - Read
  - Edit
  - Glob
  - Grep
  - Bash
  - Agent
---

# Skill: Revisar Status das Tarefas

Analise o arquivo de tarefas do projeto e gere um relatorio de status.

## Pre-requisitos

**Obrigatorio**: arquivo de tasks existente em alguma das localizacoes
suportadas (`docs/specs/*/tasks.md`, `docs/tasks.md`, `docs/tasks-*.md`,
`tasks.md`, `TODO.md`).

## Proximos passos

1. `/execute-task {id}` — iniciar a proxima tarefa recomendada pelo relatorio
2. Resolver dependencias apontadas como "bloqueadoras"
3. `/analyze` — se o relatorio revelar muitas tarefas sem evidencia de conclusao

---

## Instrucoes de Revisao

### 1. Deteccao de Contexto do Projeto

Identifique o tipo de projeto para contextualizar a analise:

| Tipo | Indicadores |
|------|-------------|
| **Documentacao** | `docs/` com `.md`, ausencia de `src/`, casos de uso (UC-*) |
| **Codigo** | `src/`, `app/`, `lib/`, `package.json`, `composer.json` |
| **Misto** | Contem tanto `docs/` quanto codigo-fonte |

### 2. Localizacao do Arquivo de Tarefas

Procure na seguinte ordem:
1. `docs/tasks.md`
2. `tasks.md`
3. `TODO.md`
4. `docs/TODO.md`
5. `.github/TODO.md`
6. Issues do repositorio (se aplicavel)

### 3. Analise das Tarefas

Para cada tarefa identificada, verifique:

#### Status Possiveis
- **Pendente**: Nao iniciada (`[ ]`)
- **Em Andamento**: Parcialmente concluida (`[~]`)
- **Concluida**: Finalizada (`[x]`)
- **Bloqueada**: Aguardando dependencia (`[!]`)

#### Checklist de Analise
- [ ] Identificar todas as tarefas e subtarefas
- [ ] Verificar status marcado vs status real
- [ ] Detectar inconsistencias (feito mas nao marcado)
- [ ] Identificar dependencias entre tarefas
- [ ] Calcular progresso por categoria/prioridade

### 4. Deteccao de Inconsistencias

**CRITICO**: Procure por tarefas que foram executadas mas nao marcadas:

#### Para Projetos de Documentacao:
```
SE tarefa pede "Criar UC-XXX-NNN"
E arquivo UC-XXX-NNN.md existe
E arquivo esta completo (nao tem TODOs)
ENTAO tarefa deve ser marcada como concluida
```

#### Para Projetos de Codigo:
```
SE tarefa pede "Implementar feature X"
E codigo da feature existe
E testes passam (se existirem)
ENTAO tarefa deve ser marcada como concluida
```

#### Extracao de Metricas

Preferir o script `scripts/metrics.sh` (mesmo diretorio desta skill) para
extrair contagens de forma deterministica:

```bash
bash skills/review-task/scripts/metrics.sh docs/tasks.md
# → tabela de metricas + linha JSON para consumo programatico
```

O script conta: fases, tarefas, subtarefas, concluidas/em andamento/pendentes/
bloqueadas, e criticidade por nivel [C]/[A]/[M].

#### Verificacao via Git (para projetos com historico):
```bash
# Ver commits recentes para identificar trabalho ja feito
git log --oneline -20

# Buscar commits relacionados a uma tarefa especifica
git log --oneline --grep="task-keyword"

# Verificar se o codigo compila/build passa (comando depende do stack)
# Exemplos: `go build ./...`, `npm run build`, `cargo build`, `mvn compile`
```

#### Para Monorepos Multi-Servico:
Use Agent para verificar tarefas em paralelo quando o arquivo de tarefas
cobre multiplos servicos — cada agente pode auditar um servico independentemente.

#### Atalhos de auditoria por stack

Para complementar a auditoria de tasks.md com auditoria de codigo no stack
detectado, invoque skills especializadas via tool Skill:

| Stack | Skill | Quando |
|-------|-------|--------|
| Go (servico individual) | `go-review-service` | Auditar UM microservico Go contra todas as convencoes do projeto (arquitetura, testes, factory, layout) — bom antes de marcar marco/release |
| Go (branch/PR) | `go-review-pr` | Auditar APENAS as mudancas do branch corrente vs `main`/`master` antes de abrir PR — diff-aware, nao re-audita o repo todo |

Essas skills produzem relatorios complementares ao review-task e ajudam
a flagar tarefas marcadas como concluidas que ainda tem violacoes de
convencao do projeto.

### 5. Acoes Automaticas

Ao identificar inconsistencias:

1. **Liste as evidencias** de que a tarefa foi concluida
2. **Atualize o arquivo de tarefas** marcando como [x]
3. **Documente no relatorio** as tarefas finalizadas nesta sessao

### 6. Priorizacao de Proximas Tarefas

Ordene tarefas pendentes por:
1. **Prioridade** (C > A > M)
2. **Dependencias** (sem bloqueios primeiro)
3. **Impacto** (maior valor de negocio)

---

## Formato do Relatorio

```markdown
# Relatorio de Status das Tarefas

**Data:** [YYYY-MM-DD]
**Projeto:** [nome do projeto]
**Tipo:** [Documentacao/Codigo/Misto]
**Arquivo de Tarefas:** [caminho]

---

## Resumo Executivo

| Metrica | Valor |
|---------|-------|
| Total de Tarefas | X |
| Concluidas | X (X%) |
| Finalizadas Nesta Sessao | X |
| Em Progresso | X (X%) |
| Pendentes | X (X%) |
| Bloqueadas | X (X%) |

---

## Tarefas Finalizadas Nesta Sessao

> Tarefas identificadas como completas e marcadas automaticamente

### [TASK-ID]: [Nome]
- **Evidencias:**
  - Arquivo criado: `path/to/file`
  - Conteudo completo
- **Acao:** Status atualizado

---

## Tarefas Pendentes - Prontas para Iniciar

### Top 3 Recomendadas

#### 1. [TASK-ID]: [Nome]
- **Prioridade:** [C|A|M]
- **Dependencias:** Nenhuma
- **Justificativa:** [por que comecar agora]
- **Comando:** `/execute-task [TASK-ID]`

---

## Tarefas Bloqueadas

### [TASK-ID]: [Nome]
- **Bloqueada por:** [TASK-ID da dependencia]
- **Para desbloquear:** Concluir [descricao]

---

## Progresso por Fase

| Fase | Total | Concluidas | % |
|------|-------|------------|---|
| 1 - Fundacao | X | X | X% |

---

## Recomendacoes

### Acoes Imediatas
1. **[Acao]** - `/execute-task [ID]`
2. **[Acao]** - `/execute-task [ID]`
```

---

## Checklist de Revisao

Antes de finalizar o relatorio:

- [ ] Li completamente o arquivo de tarefas
- [ ] Identifiquei TODAS as tarefas e status
- [ ] Verifiquei evidencias de trabalho concluido
- [ ] Marquei tarefas finalizadas mas nao registradas
- [ ] Analisei dependencias entre tarefas
- [ ] Priorizei tarefas pendentes
- [ ] Forneci top 3 recomendacoes acionaveis
- [ ] Relatorio esta claro e objetivo

---

**EXECUTE AGORA A REVISAO**

1. Detecte o contexto do projeto
2. Localize o arquivo de tarefas
3. Analise todas as tarefas
4. Identifique e corrija inconsistencias
5. Gere relatorio completo
6. Sugira proximos passos

---

## Gotchas

### Detectar inconsistencias e a razao de ser da skill

Tarefa feita mas nao marcada `[x]` e o erro mais frequente do fluxo. Se a skill so relata status sem cruzar com evidencias (arquivo existe, commit recente, build passa), nao agrega valor — vira `grep "[ ]"`.

### Procurar tasks em multiplas localizacoes, nao um path unico

Verificar nesta ordem: `docs/specs/*/tasks.md` (SDD), `docs/tasks.md`, `docs/tasks-*.md` (por servico/modulo), `tasks.md` raiz, `TODO.md`. Assumir apenas um path deixa fora projetos com SDD ou multi-servico.

### Marcar tarefas como [x] requer evidencia explicita no relatorio

Nunca marque silenciosamente. Cada auto-completion deve aparecer na secao "Tarefas Finalizadas Nesta Sessao" com bullet de evidencias (arquivo criado, commit X, build passa). Auditoria depende disso.

### Recomendacoes (top 3) devem respeitar criticidade e dependencias

A ordem e: `[C]` antes de `[A]` antes de `[M]`, e dentro do mesmo nivel, tarefas sem bloqueios primeiro. Recomendar uma `[M]` quando existem `[C]` pendentes desbloqueadas e erro de priorizacao.

### Monorepos multi-servico: paralelizar com Agent

Quando tasks.md cobre 5+ modulos/servicos, auditar sequencialmente multiplica o tempo. Lance agentes paralelos — cada um audita um servico, depois consolide.

### Nao confundir com execute-task

Esta skill LE e RELATA; nao executa trabalho pendente. Se o usuario pergunta "status" e recomenda uma tarefa, nao emenda `/execute-task` no mesmo turno — pergunte se quer prosseguir.