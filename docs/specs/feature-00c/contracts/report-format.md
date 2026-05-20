# Contract: Formato do Relatorio Feature-00C

Define o conteudo detalhado das 6 secoes obrigatorias do
`feature-00c-report.md` (FR-018). Espelha o contrato do agente-00c
(`docs/specs/agente-00c/contracts/report-format.md`) com adaptacoes ao
escopo de feature individual.

**Localizacao do arquivo gerado**:
`<projeto-alvo>/.claude/feature-00c-state/<short_name>/feature-00c-report.md`

**Header obrigatorio**:

```markdown
# Relatorio Feature-00C: <short_name>

**Feature**: `<short_name>`
**Projeto-alvo**: `<projeto_alvo_path>`
**Status**: <em_andamento|aguardando_humano|abortada|concluida>
**Iniciada**: <ISO 8601>
**Terminada**: <ISO 8601 ou "em andamento">
**Ondas**: <N>
**Decisoes**: <M>

---
```

---

## Secao 1: Resumo Executivo

**Proposito**: dar ao leitor (joao ou um auditor futuro) o contexto
completo em 2-3 paragrafos, sem precisar ler o resto.

**Conteudo obrigatorio**:
- O que se pediu (`descricao_curta` literal, com aspectos-chave extraidos
  destacados)
- O que aconteceu (final state em 1 frase: "concluida com X tasks
  implementadas", "abortada por motivo Y", "pausada aguardando resposta
  Z")
- Por que aconteceu (rationale curto)
- Pre-requisitos validados (briefing version, constitution version)

**Exemplo (sucesso)**:

```markdown
## 1. Resumo Executivo

Pedido: "Adicionar autenticacao via email/senha ao app".
Aspectos-chave detectados: autenticacao, email, senha, sessao.

Execucao concluida apos 12 ondas. Pipeline atravessou as 7 fases sem
retro-execucoes. 4 decisoes audit-relevantes registradas no clarify,
0 bloqueios humanos. Spec final tem 8 functional requirements e 5
success criteria.

Pre-requisitos: briefing v(sha:abc...), constitution v1.1.0 (sha:def...).
```

**Exemplo (aborto)**:

```markdown
## 1. Resumo Executivo

Pedido: "Refatorar storage layer para multi-tenant".

Execucao abortada na onda 7, fase execute-task, motivo "tendencia a loop"
(6o ciclo na mesma fase sem progresso mensuravel). Pipeline atravessou
specify/clarify/plan/checklist/create-tasks com sucesso; falhou ao
implementar T003 (migracao de schema). Recomendacao: simplificar T003
ou abrir bloqueio humano explicito.

Pre-requisitos: briefing v(sha:xyz...), constitution v1.1.0.
```

---

## Secao 2: Linha do Tempo

**Proposito**: visao cronologica do que aconteceu por onda.

**Conteudo obrigatorio**: tabela com uma linha por onda, ordenada
crescentemente:

```markdown
## 2. Linha do Tempo

| Onda | Periodo | Fase inicial → final | Decisoes | Skills invocadas | Motivo fim |
|------|---------|----------------------|----------|------------------|-----------|
| 1 | 14:00–14:42 | specify → clarify | 2 | specify, clarify | threshold_atingido |
| 2 | 14:50–15:15 | clarify → plan | 3 | clarify, plan | threshold_atingido |
| ... | ... | ... | ... | ... | ... |
```

Wallclock em horario local do projeto-alvo (ou UTC se nao detectavel).

Apos a tabela, secao "Fases percorridas" com checklist visual:

```markdown
### Fases percorridas

- [x] specify (1 onda, 2 decisoes)
- [x] clarify (2 ondas, 4 decisoes)
- [x] plan (1 onda, 1 decisao)
- [x] checklist (1 onda, 0 decisoes)
- [x] create-tasks (1 onda, 1 decisao)
- [x] execute-task (5 ondas, 4 decisoes — 8 tasks completas)
- [x] review-task (1 onda, 0 decisoes)
```

Aborto antes do termino = checklist com `[ ]` para fases nao atingidas
+ frase "abortada na fase X".

---

## Secao 3: Decisoes

**Proposito**: registro audit-relevante. Cada Decisao com os 5 campos
obrigatorios + auxiliares.

**Formato**: uma subsecao por Decisao, ordenadas por timestamp:

```markdown
## 3. Decisoes

### dec-001 — Escolha de modelo de hash de senha

- **Contexto/Fase**: clarify (onda 1)
- **Agente responsavel**: feature-00c-clarify-answerer
- **Opcoes consideradas**:
  - A: bcrypt cost=12
  - B: argon2id (default params)
  - C: scrypt
- **Escolha**: B (argon2id)
- **Justificativa**: constitution v1.1.0 §III.2 requer "PHC string format"
  e "memory-hard"; argon2id e o unico das 3 opcoes que satisfaz ambos.
  Score: 3/3.
- **Referencias**: `docs/constitution.md` §III.2, `spec.md` §FR-007
- **Score**: 3
- **Timestamp**: 2026-05-20T14:28:00Z

---

### dec-002 — ...
```

Decisoes sem `score_justificativa` (nao vindas do answerer) omitem o
campo Score.

Decisoes em conflito (retro-execucao) sao marcadas:

```markdown
### dec-005 — Reaberta apos retro-execucao

> Esta decisao SUPERSEDE dec-003 apos retro-execucao decidida na onda 4.
```

---

## Secao 4: Bloqueios Humanos

**Proposito**: registrar onde a pipeline pediu intervencao + status.

**Conteudo**:

```markdown
## 4. Bloqueios Humanos

### blq-001 — Conflict entre spec e constitution

- **Pergunta**: A spec propoe armazenar senhas em plain-text para
  facilitar debug em dev. Constitution §III.2 proibe. Como prosseguir?
- **Contexto**: detectado pelo pre-flight check entre clarify e plan
  (FR-010A). Spec linha 142.
- **Opcoes sugeridas**:
  - A: Manter constitution; corrigir spec para usar hash
  - B: Emendar constitution adicionando carve-out para ambiente dev
  - C: Abortar
- **Status**: respondido (A)
- **Resposta**: "A — corrigir spec; usar argon2id em todos os ambientes"
- **Decisao resultante**: dec-005
- **Respondido em**: 2026-05-20T15:30:00Z
```

Bloqueios `aguardando` sao listados no topo desta secao com banner:

```markdown
## 4. Bloqueios Humanos

> **PENDENTE**: 1 bloqueio aguardando resposta humana.
> Resolva via `/feature-00c-resume <short_name> --resposta-bloqueio "..."`.
```

Se nenhum bloqueio: `> Nenhum bloqueio humano registrado.`

---

## Secao 5: Sugestoes para Skills Globais

**Proposito**: alimentar evolucao do toolkit. Apenas sugestoes geradas
DURANTE esta execucao (nao append historico).

**Conteudo**:

```markdown
## 5. Sugestoes para Skills Globais

### sug-001 — Skill `clarify` poderia detectar perguntas redundantes

- **Skill afetada**: `clarify`
- **Severidade**: informativa
- **Diagnostico**: na onda 2, o asker gerou 2 perguntas que
  basicamente perguntavam o mesmo (auth method vs auth library).
- **Proposta**: deduplicar perguntas via similaridade semantica antes
  de devolver para o orquestrador.
- **Link**: appendado em
  `<projeto-alvo>/.claude/feature-00c-suggestions.md` como sug-001.
```

Sugestao `impeditiva` aponta para issue:

```markdown
### sug-005 — Skill `plan` retorna data-model.md com YAML invalido

- **Skill afetada**: `plan`
- **Severidade**: impeditiva
- **Diagnostico**: ...
- **Proposta**: ...
- **Issue aberta**: https://github.com/JotJunior/claude-ai-tips/issues/123
- **Link**: sug-005 em suggestions.md
```

Se nenhuma sugestao: `> Nenhuma sugestao gerada nesta execucao.`

---

## Secao 6: Licoes Aprendidas

**Proposito**: aprendizado pessoal de joao + alimentacao do experimento
longitudinal (SC-010 do agente-00c).

**Conteudo**: 2-5 licoes em bullets, cada uma com:
- O que aconteceu (1 frase)
- Por que e licao (1 frase)
- Proposta para futuro (1 frase, acionavel)

```markdown
## 6. Licoes Aprendidas

- **Licao 1**: `execute-task` para tasks com migracao de schema
  consumiu 3x mais tool calls que a media. **Por que e licao**: tasks
  envolvendo SQL precisam de checklist especifico de validacao
  (rollback). **Proposta**: split de tasks de migracao em duas (forward
  + rollback) no `/create-tasks`.

- **Licao 2**: clarify-answerer fez score 3/3 em 5 das 6 perguntas
  ancorando em constitution §III. **Por que e licao**: constitution
  bem detalhada reduz drift de decisao. **Proposta**: documentar como
  best practice no readme do agente-00c.
```

Se execucao curta sem licoes claras: `> Sem licoes substantivas nesta
execucao.`

---

## Regras gerais

1. **Filtro de secrets**: aplicar `secrets-filter.sh --redact` em TODO o
   conteudo do relatorio antes de gravar.
2. **Encoding**: UTF-8, line endings LF.
3. **Heading hierarchy**: secoes em `##`, subsecoes em `###`, sub-sub
   em `####`. Sem `#` (reservado para titulo do arquivo).
4. **Links**: paths relativos ao projeto-alvo quando referenciando
   artefatos (`docs/specs/<short_name>/spec.md`). URLs externas apenas
   para issues do toolkit.
5. **Idempotencia**: re-geracao sobrescreve o arquivo sem mesclar.
   Sempre escrever o relatorio inteiro a partir do state.json corrente.
6. **Tamanho**: relatorio pode crescer; nao truncar. Se >10MB, emitir
   warning + sugerir purge de decisoes antigas em uma proxima execucao
   (NAO automatico).
