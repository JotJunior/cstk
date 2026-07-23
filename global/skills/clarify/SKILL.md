---
name: clarify
description: 'Refine an existing spec via structured Q&A (max 5). Triggers: "clarify", "clarificar spec", "resolver ambiguidades", "refinar spec". Operates on existing spec.md; use specify to create one.'
argument-hint: "[caminho para spec ou feature name]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

# Skill: Clarificar Spec

Identifique e resolva ambiguidades em uma feature spec existente via perguntas
estruturadas, integrando as respostas diretamente no documento.

## Modos de invocacao

Esta skill suporta dois modos:

1. **Interativo (default)** — humano executa `/clarify`; skill faz Q&A
   direto com o usuario, uma pergunta por vez (ETAPA 4 deste documento).

2. **Padrao de dois atores (apenas dentro de `agente-00c`)** — o
   orquestrador spawna `agente-00c-clarify-asker` (gera perguntas) +
   `agente-00c-clarify-answerer` (responde com scoring 0..3) como
   subagentes irmaos. NAO chame esses subagentes diretamente via
   `/clarify` — eles sao primitivas do orquestrador.

   Dentro do modo dois-atores, se a tool Agent estiver indisponivel
   no harness (sintoma: spawn falha com erro de tool, nao com erro
   de prompt), o orquestrador faz downgrade EXPLICITO via Decisao
   auditada — nao silently fallback. Ver
   `agente-00c-orchestrator.md` §5.a (Dry-run da tool Agent).

## Pre-requisitos

**Obrigatorio**: `spec.md` ja existente (criado via `/specify` ou manualmente).
Sem spec, a skill aborta e instrui a rodar `/specify` primeiro.

**Opcional**: `docs/constitution.md` para validar respostas contra principios.

## Proximos passos

1. `/checklist` — gerar quality gate de requisitos apos clarificacao
2. `/plan` — spec agora esta pronta para gerar plano tecnico
3. `/clarify` novamente — apenas se Outstanding de alto impacto persistirem

## Argumentos

$ARGUMENTS

---

## Leitura de artefatos foundational (briefing + constitution)

Antes de ler `docs/01-briefing-discovery/briefing.md` ou `docs/constitution.md`
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
1. LOCALIZAR       Encontrar spec existente
     |
2. ESCANEAR        Scan de ambiguidades por taxonomia
     |
3. PRIORIZAR       Gerar fila de max 5 perguntas
     |
4. PERGUNTAR       Uma pergunta por vez (interativo)
     |
5. INTEGRAR        Atualizar spec apos cada resposta
     |
6. REPORTAR        Resumo de cobertura e proximos passos
```

---

## ETAPA 1: LOCALIZAR SPEC

### 1.1 Encontrar Spec

Use $ARGUMENTS para localizar a spec. Pode ser:

1. **Caminho direto**: `docs/specs/user-auth/spec.md`
2. **Nome da feature**: buscar via `docs/specs/*/spec.md`
3. **Vazio**: listar specs disponiveis e pedir ao usuario para escolher

Se spec nao encontrada: instruir usuario a rodar `/specify` primeiro.

### 1.2 Carregar Contexto

```
CARREGAR:
-- A spec encontrada (OBRIGATORIO)
-- docs/constitution.md (se existir, para validar principios)
```

---

## ETAPA 2: ESCANEAR AMBIGUIDADES

### 2.1 Taxonomia de Scan

Para cada categoria abaixo, marcar status: **Clear** / **Partial** / **Missing**:

**Escopo Funcional e Comportamento:**
- Objetivos core do usuario e criterios de sucesso
- Declaracoes explicitas de fora-de-escopo
- Diferenciacao de papeis/personas de usuario

**Dominio e Modelo de Dados:**
- Entidades, atributos, relacionamentos
- Regras de identidade e unicidade
- Transicoes de estado/lifecycle
- Premissas de volume/escala de dados

**Interacao e Fluxo UX:**
- Jornadas criticas do usuario
- Estados de erro/vazio/loading
- Notas de acessibilidade ou localizacao

**Qualidade Nao-Funcional:**
- Performance (latencia, throughput)
- Escalabilidade (limites)
- Confiabilidade e disponibilidade (uptime, recuperacao)
- Observabilidade (logging, metricas, tracing)
- Seguranca e privacidade (authN/Z, protecao de dados)
- Compliance/regulatorio

**Integracao e Dependencias Externas:**
- Servicos/APIs externos e modos de falha
- Formatos de import/export de dados
- Premissas de protocolo/versionamento

**Edge Cases e Tratamento de Falhas:**
- Cenarios negativos
- Rate limiting / throttling
- Resolucao de conflitos (ex: edicoes concorrentes)

**Constraints e Tradeoffs:**
- Restricoes tecnicas (linguagem, storage, hosting)
- Tradeoffs explicitos ou alternativas rejeitadas

**Decisoes de Infraestrutura Auditaveis (alta prioridade):**
- Politica de scheduling (`autoSchedule = cron|wakeup|manual|auto`)
- Politica de key rotation (versionamento `v1:<base64>` sim/nao)
- Refresh policy (on-demand vs job periodico; gap window aceitavel)
- Mutex multi-pod (lock advisory, redis, SELECT FOR UPDATE)
- Idempotencia (chave, TTL, escopo)
- Backup/restore (cron, retencao, RB-NNN de drill)

Cada item ausente do spec mas RELEVANTE para a feature (i.e. feature
tem runtime longo, persistencia, integracao com IdP) deve aparecer
**no topo da fila** de perguntas — antes de UX e detalhes tecnicos.
Razao: dec sobre key rotation ou scheduling descoberta apos `clarify`
vira retrabalho urgente na onda-007 (`execute-task` sem premissa). Ver
specify/SKILL.md §"Decisoes de Infraestrutura Auditaveis" para tabela
completa.

**Terminologia e Consistencia:**
- Termos canonicos do glossario
- Sinonimos evitados / termos deprecados

**Sinais de Completude:**
- Testabilidade dos criterios de aceite
- Indicadores mensuráveis de Definition of Done

**Placeholders e Pendencias:**
- Marcadores TODO, ???, `<placeholder>`
- Adjetivos ambiguos ("robusto", "intuitivo") sem quantificacao

### 2.2 Filtrar Oportunidades

Para cada categoria Partial ou Missing, adicionar candidato a pergunta EXCETO se:
- Clarificacao nao mudaria materialmente a implementacao ou estrategia de validacao
- Informacao e melhor resolvida na fase de planejamento (anotar internamente)

### 2.3 Sinalizar quando o ponto levantado e feature nova, nao clarificacao

Aplica o mesmo criterio de `specify/SKILL.md` ETAPA 0.4 (atualizar spec vs
abrir feature nova): se, ao escanear ambiguidades ou ao longo do diálogo com
o operador, um ponto levantado **muda a intencao original** da spec corrente
ou **expande o escopo** para atores/capacidades nao relacionados ao objetivo
que a spec ja ratificou — isso NAO e uma ambiguidade a resolver dentro da
spec atual, e o embriao de uma feature separada.

Nesse caso:
- **Nao** adicionar como candidato a pergunta desta rodada de `clarify`.
- Sinalizar ao operador citando o criterio aplicado (intencao mudou /
  escopo expandiu) e sugerir `/specify` para abrir a feature nova, em vez
  de forcar a resposta dentro da spec corrente.
- Se o ponto e ambiguo quanto a pertencer ou nao ao escopo original,
  preferir tratar como clarificacao normal (o overhead de errar para o
  lado de clarificar e menor do que fragmentar escopo em specs demais).

---

## ETAPA 3: PRIORIZAR PERGUNTAS

### 3.1 Gerar Fila

Gerar fila priorizada de **maximo 5 perguntas**. Criterios:

- Cada pergunta deve ser respondivel com:
  - **Multiple-choice** (2-5 opcoes mutuamente exclusivas), OU
  - **Resposta curta** (max 5 palavras)
- So incluir perguntas cujas respostas impactam materialmente: arquitetura, modelo de dados,
  decomposicao de tasks, design de testes, comportamento UX, prontidao operacional, ou compliance
- Balancear cobertura de categorias: priorizar areas de alto impacto nao resolvidas
- Se mais de 5 categorias nao resolvidas: selecionar top 5 por (Impacto x Incerteza)

**Ordem de prioridade (alta → baixa):**

1. **Decisoes de Infraestrutura Auditaveis** — scheduling, key rotation,
   refresh policy, mutex multi-pod, idempotencia. Custo de descobrir
   depois (`execute-task`) e alto.
2. **Escopo funcional** — fora-de-escopo declarado, papeis distintos
3. **Dominio e Modelo de Dados** — entidades, identidade, lifecycle
4. **Qualidade nao-funcional** — performance, seguranca, compliance
5. **UX e interacao** — jornadas criticas, edge cases
6. **Constraints tecnicas** — linguagem, storage, hosting

Aplicar essa ordem dentro do top-5 final.

### 3.2 Excluir

- Perguntas ja respondidas na spec
- Preferencias estilisticas triviais
- Detalhes de execucao do plan (a menos que bloqueiem corretude)

---

## ETAPA 4: PERGUNTAR (INTERATIVO)

### 4.1 Formato — Uma Pergunta por Vez

**Para perguntas multiple-choice:**

1. Analisar todas as opcoes e determinar a **mais adequada** baseado em:
   - Best practices para o tipo de projeto
   - Padroes comuns em implementacoes similares
   - Reducao de risco (seguranca, performance, manutencao)
   - Alinhamento com constitution (se existir)

2. Apresentar:

```markdown
## Pergunta [N]: [Topico]

**Contexto**: [Citar secao relevante da spec]

**O que precisamos saber**: [Pergunta especifica]

**Recomendado:** Opcao [X] - [raciocinio em 1-2 frases]

| Opcao | Descricao |
|-------|-----------|
| A     | [Descricao opcao A] |
| B     | [Descricao opcao B] |
| C     | [Descricao opcao C] |

Responda com a letra da opcao (ex: "A"), aceite a recomendacao com "sim",
ou forneca sua propria resposta curta.
```

**Para perguntas de resposta curta:**

```markdown
## Pergunta [N]: [Topico]

**Contexto**: [Citar secao relevante]

**Sugestao:** [resposta sugerida] - [raciocinio breve]

Formato: Resposta curta (max 5 palavras). Aceite a sugestao com "sim"
ou forneca sua propria resposta.
```

### 4.2 Apos Cada Resposta

- Se usuario responde "sim", "recomendado" ou "sugestao": usar a opcao recomendada/sugerida
- Validar que resposta mapeia a uma opcao ou cabe no constraint de 5 palavras
- Se ambiguo: pedir desambiguacao rapida (nao conta como nova pergunta)
- Registrar em memoria de trabalho e avancar para proxima pergunta

### 4.3 Parar Quando

- Todas as ambiguidades criticas resolvidas
- Usuario sinaliza conclusao ("pronto", "done", "sem mais")
- 5 perguntas feitas

---

## ETAPA 5: INTEGRAR RESPOSTAS

### 5.1 Apos CADA Resposta Aceita

Atualizar a spec imediatamente:

1. Garantir que secao `## Clarifications` existe (criar logo apos secao de contexto/overview)
2. Sob `### Session YYYY-MM-DD`, adicionar:
   ```markdown
   - Q: [pergunta] → A: [resposta final]
   ```

3. Aplicar clarificacao na secao mais apropriada:

| Tipo de Clarificacao | Secao Alvo |
|---------------------|------------|
| Ambiguidade funcional | Functional Requirements |
| Distincao de ator/interacao | User Stories ou Actors |
| Shape de dados/entidades | Key Entities |
| Constraint nao-funcional | Success Criteria ou nova secao NFR |
| Edge case/fluxo negativo | Edge Cases |
| Conflito de terminologia | Normalizar termo em toda a spec |

4. Se clarificacao invalida afirmacao anterior: **substituir** (nao duplicar)
5. Salvar spec **apos cada integracao** (atomic overwrite)
6. Preservar formatacao: nao reordenar secoes; manter hierarquia de headings

### 5.2 Validacao Apos Cada Write

- Secao Clarifications contem exatamente um bullet por resposta aceita
- Total de perguntas feitas <= 5
- Secoes atualizadas nao contem placeholders que a resposta deveria resolver
- Nenhuma afirmacao contradictoria anterior permanece
- Markdown valido; unicos headings novos permitidos: `## Clarifications`, `### Session YYYY-MM-DD`
- Consistencia terminologica: mesmo termo canonico em todas as secoes atualizadas

---

## ETAPA 6: REPORTAR

### 6.1 Relatorio de Conclusao

```markdown
## Clarificacao Concluida

**Spec**: [caminho]
**Perguntas feitas**: [N]
**Secoes atualizadas**: [lista]

### Cobertura

| Categoria | Status |
|-----------|--------|
| Escopo Funcional | Clear / Resolved / Deferred / Outstanding |
| Modelo de Dados | Clear / Resolved / Deferred / Outstanding |
| Fluxo UX | Clear / Resolved / Deferred / Outstanding |
| Qualidade Nao-Funcional | Clear / Resolved / Deferred / Outstanding |
| Integracoes | Clear / Resolved / Deferred / Outstanding |
| Edge Cases | Clear / Resolved / Deferred / Outstanding |
| Constraints | Clear / Resolved / Deferred / Outstanding |
| Terminologia | Clear / Resolved / Deferred / Outstanding |

**Legenda:**
- **Resolved**: Era Partial/Missing, resolvido nesta sessao
- **Deferred**: Excede cota de perguntas ou melhor resolvido no planejamento
- **Clear**: Ja estava suficiente
- **Outstanding**: Ainda Partial/Missing mas baixo impacto

### Proximo Passo

- `/plan` — Gerar plano tecnico de implementacao
- `/clarify` novamente — Se Outstanding de alto impacto restarem
```

### 6.2 Regras de Comportamento

- Se nenhuma ambiguidade significativa encontrada: "Nenhuma ambiguidade critica detectada." e sugerir prosseguir
- Se spec nao existe: instruir a rodar `/specify` primeiro
- Nunca exceder 5 perguntas totais (retries de desambiguacao nao contam)
- Evitar perguntas especulativas sobre tech stack (a menos que bloqueiem clareza funcional)
- Respeitar sinais de encerramento do usuario ("stop", "done", "prosseguir")
- Se cota esgotada com categorias Outstanding de alto impacto: flaggear explicitamente como Deferred com rationale

---

## Gotchas

### Maximo 5 perguntas TOTAL — nao "so mais uma"

Retries de desambiguacao (quando a resposta do usuario foi ambigua) nao contam, mas perguntas novas contam. Exceder o limite corroi o valor da skill — se 5 nao resolveu tudo, documente as ambiguidades restantes como Deferred e passe para o `/plan`.

### Uma pergunta por vez — esperar resposta antes de avancar

Despejar 5 perguntas de uma vez parece eficiente mas quebra a integracao incremental. Cada resposta aceita dispara um write na spec; perguntas em lote perdem esse ciclo.

### Atomic write apos cada resposta

Integre a resposta na spec IMEDIATAMENTE (atomic overwrite), nao acumule respostas para integrar no final. Se o usuario interromper na pergunta 3, as 2 respostas anteriores ja estao persistidas.

### Respostas devem mapear para opcoes ou <= 5 palavras

Respostas livres longas violam o contrato do formato. Se o usuario responder em texto longo, sintetize em resposta curta e confirme — nao integre o texto cru na spec.

### Se a spec nao existe, abortar e instruir /specify

Nao tente "clarificar do nada" inferindo o que a spec poderia ser. A skill opera sobre texto existente — sem texto, use `/specify` primeiro.

### Nao reordenar secoes nem reescrever heading hierarchy

As unicas adicoes permitidas sao `## Clarifications` e `### Session YYYY-MM-DD`. Alterar outros headings contamina o diff e quebra ferramentas downstream.
