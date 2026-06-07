---
name: cstk-analyze
description: "Cross-artifact SDD consistency analysis (spec/plan/tasks/constitution) — read-only. Triggers: \"analyze\", \"cross-check\", \"auditar artefatos\", \"validar spec vs tasks\". Skip for single-document validation (use validate-documentation)."
---

# CSTK Adaptation

Adapted from `JotJunior/cstk` skill `analyze` at commit `35922cf`.
Use this as a Codex skill; follow local repository instructions and Codex tool names when source text mentions Claude-specific commands or slash commands.

# Skill: Analise de Consistencia Cross-Artifact

Analise read-only que identifica inconsistencias, duplicacoes, ambiguidades e gaps
de cobertura entre os artefatos de uma feature (spec, plan, tasks, constitution).

**STRICTLY READ-ONLY**: NAO modifica nenhum arquivo. Produz relatorio estruturado.

## Pre-requisitos

**Obrigatorio**: `spec.md` E `tasks.md` existentes na feature a analisar.
Sem ambos, a skill aborta e indica qual comando rodar primeiro.

**Opcional**: `plan.md` e `docs/constitution.md` aumentam a cobertura da analise.

## Proximos passos

1. Se issues CRITICAL: resolver antes de `/execute-task`
2. Se apenas LOW/MEDIUM: prosseguir com `/execute-task` mas agendar cleanup
3. `/specify`, `/clarify` ou `/plan` — conforme findings apontem onde corrigir

## Argumentos

the user's request

---

## FLUXO DE EXECUCAO

```
1. INICIALIZAR     Localizar e carregar artefatos
     |
2. MODELAR         Construir modelos semanticos
     |
3. DETECTAR        6 passes de deteccao
     |
4. CLASSIFICAR     Atribuir severidade
     |
5. REPORTAR        Gerar relatorio compacto
     |
6. RECOMENDAR      Proximas acoes
```

---

## ETAPA 1: INICIALIZAR

### 1.1 Localizar Artefatos

Use the user's request para encontrar o diretorio da feature.
Derivar paths absolutos:

- `SPEC` = {feature_dir}/spec.md
- `PLAN` = {feature_dir}/plan.md
- `TASKS` = {feature_dir}/tasks.md (ou `docs/tasks*.md` se fora do padrao specs/)

Se the user's request vazio: listar diretorios em `docs/specs/` e pedir ao usuario para escolher.

**Artefatos obrigatorios**: spec.md E tasks.md (ou equivalente).
Se algum esta ausente: abortar com mensagem indicando qual comando rodar primeiro.

### 1.2 Carregar Artefatos (Progressive Disclosure)

**Da spec.md:**
- Overview/Contexto
- Functional Requirements
- Non-Functional Requirements
- User Stories
- Edge Cases (se presente)

**Do plan.md (se existir):**
- Arquitetura/stack choices
- Referências a Data Model
- Fases
- Constraints tecnicos

**Do tasks.md:**
- Task IDs
- Descricoes
- Agrupamento por fase
- Marcadores [P] de paralelismo
- Paths de arquivo referenciados

**Da constitution (se existir):**
- Carregar `docs/constitution.md`
- Extrair principios MUST/SHOULD

---

## ETAPA 2: MODELAR

### 2.1 Construir Modelos Semanticos

Criar representacoes internas (nao incluir artefatos raw no output):

**Inventario de Requisitos:**
- Cada requisito funcional + nao-funcional com chave estavel
- Derivar slug do verbo imperativo (ex: "User can upload file" → `user-can-upload-file`)

**Inventario de User Stories/Acoes:**
- Acoes discretas do usuario com criterios de aceite

**Mapeamento de Cobertura de Tasks:**
- Mapear cada task a um ou mais requisitos/stories
- Inferencia por keyword / padroes de referencia explicita (IDs, frases-chave)

**Conjunto de Regras da Constitution:**
- Extrair nomes de principios e afirmacoes MUST/SHOULD

---

## ETAPA 3: DETECTAR

### 3.1 Passes de Deteccao

Executar 6 passes sobre os modelos semanticos. Detalhamento completo de cada
pass (o que flaggear, severidade tipica, exemplos) em
`references/consistency-checks.md` (mesmo diretorio desta skill):

- **A. Duplicacao** — requisitos near-duplicate
- **B. Ambiguidade** — adjetivos vagos, placeholders nao resolvidos
- **C. Sub-especificacao** — verbos sem objeto, criterios incompletos
- **D. Alinhamento com Constitution** — violacoes MUST sao automaticamente CRITICAL
- **E. Gaps de Cobertura** — requisitos orfaos, tasks orfas
- **F. Inconsistencia** — drift de terminologia, contradicoes entre artefatos
- **G. Convencoes de Borda (case style)** — comparar `plan.md §Convencoes
  de Borda` contra uso real em `data-model.md`, `contracts/*.md` e
  payload examples. Se plan declara DB=snake_case mas `data-model.md`
  cita coluna `userName`, flag MAJOR. Se contracts declara
  camelCase mas exemplo de payload usa `user_name`, flag MAJOR.
  Razao: dec-172/173 historicos resolveram em FASE 8 (onda-040) uma
  divergencia que existia desde onda-014 — 40 ondas de retrabalho
  porque a convencao nao foi cross-checked upfront.

Focar em findings de alto sinal. Limite: **50 findings total**. Agregar
restante em resumo de overflow.

---

## ETAPA 4: CLASSIFICAR

### 4.1 Heuristica de Severidade

Tabela completa em `references/consistency-checks.md#heuristica-de-severidade`.
Resumo:

| Severidade | Criterio |
|------------|----------|
| **CRITICAL** | Violacao de MUST na constitution, artefato core ausente, requisito core sem cobertura |
| **HIGH** | Duplicacao/conflito, seguranca/performance ambigua, criterio nao-testavel |
| **MEDIUM** | Drift de terminologia, NFR parcialmente coberto, edge case sub-especificado |
| **LOW** | Estilo, redundancia menor |

---

## ETAPA 5: REPORTAR

### 5.1 Formato do Relatorio

Produzir relatorio Markdown (NO FILE WRITES — apenas output na conversa):

```markdown
## Specification Analysis Report

### Findings

| ID | Categoria | Severidade | Localizacao | Resumo | Recomendacao |
|----|-----------|-----------|-------------|--------|--------------|
| A1 | Duplicacao | HIGH | spec.md §FR-3, §FR-7 | Requisitos similares sobre... | Merge, manter versao mais clara |
| B1 | Ambiguidade | MEDIUM | spec.md §SC-002 | "rapido" sem metrica | Quantificar com threshold |
| D1 | Constitution | CRITICAL | plan.md §Tech | Viola principio Test-First | Adicionar fase de testes |
| E1 | Cobertura | HIGH | spec.md §FR-005 | Zero tasks mapeadas | Adicionar tasks em Phase 3 |

### Coverage Summary

| Requisito | Tem Task? | Task IDs | Notas |
|-----------|-----------|----------|-------|
| FR-001 | Sim | T012, T014 | |
| FR-002 | Sim | T015 | |
| FR-003 | Nao | — | Gap: sem tasks |

### Constitution Alignment

[Lista de violacoes ou "Todos os principios atendidos"]

### Unmapped Tasks

[Tasks sem requisito/story correspondente ou "Todas as tasks mapeadas"]

### Metricas

- **Total de Requisitos**: [N]
- **Total de Tasks**: [N]
- **Cobertura**: [N]% (requisitos com >= 1 task)
- **Ambiguidades**: [N]
- **Duplicacoes**: [N]
- **Issues Criticas**: [N]
```

---

## ETAPA 6: RECOMENDAR

### 6.1 Proximas Acoes

Baseado nos findings:

- **Se issues CRITICAL existem**: Recomendar resolver antes de `/execute-task`
- **Se apenas LOW/MEDIUM**: Usuario pode prosseguir, mas fornecer sugestoes de melhoria
- **Comandos sugeridos concretos**:
  - "Rodar `/specify` para refinar requisito FR-003"
  - "Rodar `/plan` para ajustar arquitetura"
  - "Editar tasks.md para adicionar cobertura para 'performance-metrics'"
  - "Rodar `/clarify` para resolver ambiguidades na spec"

### 6.2 Oferecer Remediacao

Perguntar ao usuario:

"Deseja que eu sugira edicoes concretas de remediacao para os top N issues?"

**NAO aplicar automaticamente** — apenas sugerir se usuario aprovar explicitamente.

---

## REGRAS IMPORTANTES

- **NUNCA modificar arquivos** (analise estritamente read-only)
- **NUNCA hallucinar secoes ausentes** (se ausente, reportar com precisao)
- **Priorizar violacoes de constitution** (sempre CRITICAL)
- **Usar exemplos sobre regras exaustivas** (citar instancias especificas)
- **Reportar zero issues gracefully** (emitir relatorio de sucesso com estatisticas de cobertura)
- **Resultados deterministicos**: re-rodar sem mudancas deve produzir IDs e contagens consistentes
- **Max 50 findings**: agregar overflow em resumo

### Diferenca do validate-documentation

- `validate-documentation`: Valida UM documento (UC) contra padroes de qualidade estrutural
- `analyze`: Valida MULTIPLOS artefatos ENTRE SI (spec vs plan vs tasks vs constitution)
- Ambos coexistem — validate-docs para documentos individuais, analyze para consistencia cross-artifact

---

## Gotchas

### STRICTLY READ-ONLY — quebrar isso invalida o contrato

A skill NAO escreve nem edita arquivos. Se uma correcao parece obvia, sugira no relatorio e aguarde aprovacao explicita do usuario. Aplicar fixes automaticamente viola o proposito da analise.

### Violacoes de constitution sao SEMPRE CRITICAL

Nao importa o quao pequena a violacao parece. Se conflita com um principio MUST, a severidade e CRITICAL e bloqueia `/execute-task` ate resolver. Nao rebaixe para HIGH por "contexto".

### Max 50 findings — o resto vai para overflow

Ultrapassar esse limite dilui o sinal. Se mais de 50 candidatos, priorizar por (Impacto x Incerteza) e agregar o restante num resumo no final do relatorio.

### Nao inventar secoes ausentes

Se a spec nao tem "Edge Cases", reporte como **Gap** (E. Gaps de Cobertura) — nao alucine conteudo "como deveria ser". O papel da skill e detectar, nao preencher.

### Resultados devem ser deterministicos

Re-rodar a analise sem mudancas nos artefatos deve produzir os mesmos IDs, contagens e severidades. Se duas execucoes consecutivas divergem, o modelo interno esta instavel — rever heuristicas.

## Source License

This skill includes material adapted from `JotJunior/cstk`, licensed under MIT. The copyright and permission notice are included in `references/cstk-license.md`.

