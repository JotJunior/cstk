# Contract: Formato do Relatorio Final

Estrutura do arquivo `<projeto-alvo>/.claude/agente-00c-report.md`.

Gerado a cada termino de onda (relatorio parcial — sobrescrito) e a cada
termino de execucao (relatorio final — sobrescreve o parcial).

Toda execucao, incluindo as abortadas, **deve** produzir relatorio com
todas as seis secoes obrigatorias preenchidas (FR-011, SC-001).

---

## Estrutura obrigatoria

```markdown
# Relatorio do Agente-00C — <execucao_id>

**Gerado em**: <iso8601>
**Status no momento**: <em_andamento | aguardando_humano | abortada | concluida>
**Versao do schema**: 1.0.0

---

## 1. Resumo Executivo

| Campo | Valor |
|-------|-------|
| ID Execucao | exec-... |
| Projeto-Alvo | /path/absoluto |
| Descricao | ... |
| Stack final | ... ou "nao aplicavel — execucao abortada antes de definir" |
| Status | ... |
| Motivo termino | ... |
| Iniciada em | ... |
| Terminada em | ... ou "ainda em andamento" |
| Ondas executadas | N |
| Tool calls totais | N |
| Decisoes registradas | N |
| Bloqueios humanos | N |
| Sugestoes para skills globais | N |
| Issues abertas no toolkit | N |
| Profundidade max de subagentes | N |

[Paragrafo de 3-5 linhas resumindo o que aconteceu na execucao em texto
corrido — escrito pelo orquestrador no momento da geracao.]

## 2. Linha do Tempo

| Onda | Inicio | Fim | Etapas | Tool calls | Wallclock | Termino |
|------|--------|-----|--------|------------|-----------|---------|
| 001 | ... | ... | briefing | 42 | 28min | etapa_concluida_avancando |
| 002 | ... | ... | constitution, specify | 67 | 45min | threshold_proxy_atingido |
| ... |

## 3. Decisoes

Total: N decisoes registradas.

### 3.1 Por agente

| Agente | Quantidade |
|--------|------------|
| orquestrador-00c | ... |
| clarify-asker | ... |
| clarify-answerer | ... |
| executor-task-XXX | ... |

### 3.2 Lista detalhada

#### dec-001 — briefing — orquestrador-00c — 2026-05-05T14:31:22Z

**Contexto**: Briefing pergunta 4 — stakeholders.
**Opcoes consideradas**: Operador unico / Time pequeno / Multi-time
**Escolha**: Operador unico
**Justificativa**: ...
**Score**: (n/a — decisao do orquestrador)
**Referencias**: briefing.md#2-usuarios-e-stakeholders
**Artefato originador**: briefing.md

#### dec-002 — clarify — clarify-answerer — 2026-05-05T14:48:11Z

**Contexto**: Clarify pergunta 2 — escolha de banco de dados.
**Opcoes consideradas**: PostgreSQL / SQLite / MongoDB
**Escolha**: PostgreSQL
**Justificativa**: Briefing do projeto-alvo cita "dados relacionais com
joins"; constitution do projeto-alvo nao restringe; stack-sugerida vinha
omitida mas CLAUDE.md do projeto-alvo cita PostgreSQL.
**Score**: 2 (briefing + CLAUDE.md = 2 fontes)
**Referencias**: briefing.md, CLAUDE.md
**Artefato originador**: briefing.md

[continuar listando todas as decisoes — uma por subsecao H4]

## 4. Bloqueios Humanos

Total: N bloqueios.

### 4.1 Pendentes (aguardando resposta)

#### block-003 — disparado em 2026-05-05T15:02:33Z

**Pergunta**: O projeto-alvo precisa suportar autenticacao multi-tenant ou
unica?

**Contexto para resposta**: A descricao curta nao mencionou tenancy. Briefing
do projeto-alvo gerou hipotese de multi-tenant mas sem confirmacao. Se
multi-tenant, escopo do MVP cresce ~30%; se unica, podemos cortar 4 user
stories.

**Opcoes recomendadas pelo asker**:
- a) Unica
- b) Multi-tenant
- c) Decidir depois (deixar abstracao para suportar ambos no futuro)

**Status**: aguardando

### 4.2 Respondidos

[mesma estrutura, com campos adicionais `Resposta humana` e `Respondido em`]

### 4.3 Sem bloqueios

(Se zero, escrever explicitamente "Nenhum bloqueio humano nesta execucao.")

## 5. Sugestoes para Skills Globais

Total: N sugestoes.

### 5.1 Severidade impeditiva (viraram issues)

#### sug-001 — skill `clarify` — issue #42 aberta

**Diagnostico**: ...
**Proposta**: ...
**Issue**: https://github.com/JotJunior/claude-ai-tips/issues/42

### 5.2 Severidade aviso

[mesma estrutura, sem issue]

### 5.3 Severidade informativa

[mesma estrutura]

### 5.4 Sem sugestoes

(Se zero, escrever explicitamente "Nenhuma sugestao para skills globais
nesta execucao.")

## 6. Licoes Aprendidas

Secao livre, escrita pelo orquestrador no momento da geracao do relatorio
final (nao em relatorios parciais — fica como TODO ate execucao terminar).

Recomendacao de conteudo:

- O que funcionou bem na pipeline.
- O que nao funcionou e por que.
- 1-3 propostas concretas de melhoria das skills do toolkit, ja avaliadas
  contra a constitution do toolkit.
- Sinais para a proxima execucao do experimento.

Em relatorio parcial: `(Sera preenchido no relatorio final.)`.

---

**Apendice A — Caminhos relevantes**

- Estado: `<projeto-alvo>/.claude/agente-00c-state/state.json`
- Backups de estado: `<projeto-alvo>/.claude/agente-00c-state/state-history/`
- Sugestoes detalhadas: `<projeto-alvo>/.claude/agente-00c-suggestions.md`
- Whitelist: `<projeto-alvo>/.claude/agente-00c-whitelist`
- Artefatos da pipeline: `<projeto-alvo>/docs/specs/<feature>/`
```

---

## Regras de geracao

- **Verificacao automatica de completude**: o orquestrador valida que todas
  as 6 secoes (`## 1.` ate `## 6.`) existem antes de salvar. Secao ausente
  = falha de geracao.
- **Linguagem**: portugues. Tom: tecnico, conciso, direto.
- **Nao incluir secoes vazias com "N/A"**: se uma execucao tem 0 bloqueios,
  a subsecao 4.3 deve dizer "Nenhum bloqueio humano nesta execucao." (frase
  em portugues, nao "N/A").
- **Decisoes do clarify-answerer SEMPRE com campo Score**: outras decisoes
  podem omitir Score (escrever "n/a — decisao do orquestrador").
- **Toda referencia em **Referencias** deve ser path relativo ou URL clicavel**.
  Path relativo a partir do projeto-alvo.
