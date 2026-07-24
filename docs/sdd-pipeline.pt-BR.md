[English](./sdd-pipeline.md) · **Português (pt-BR)**

# Pipeline SDD (Spec-Driven Development)

> Documento por tópico do [README](../README.pt-BR.md). Catálogo resumido das skills
> na seção [Skills Globais](../README.pt-BR.md#skills-globais).

O pipeline SDD é a sequência recomendada para levar uma ideia desde o discovery
até a implementação. Cada skill consome os artefatos do anterior e alimenta o
próximo.

```text
 ┌──────────────┐
 │  DISCOVERY   │
 └──────┬───────┘
        │
   ① briefing          Entrevista de discovery → docs/01-briefing-discovery/briefing.md
        │                Coleta visão, usuários, escopo, restrições e stack.
        │                Pergunta UMA pergunta por vez (max 10).
        ▼
   ② constitution      Briefing → docs/constitution.md
        │                Define princípios MUST/SHOULD que governam todas as decisões.
        │                Validado contra artefatos existentes (propagação).
        ▼
 ┌──────────────┐
 │ ESPECIFICAÇÃO│
 └──────┬───────┘
        │
   ③ specify            Descrição natural → docs/specs/{feature}/spec.md
        │                Gera user stories priorizadas, requisitos funcionais,
        │                critérios de aceite e success criteria mensuráveis.
        │                Foco no QUE e POR QUÊ — nunca no COMO.
        │                Gate determinístico: todo requisito exige >=1 cenário
        │                (requirement-coverage.sh, v5.22.0). Seção opcional
        │                "## Delta Requirements" declara o delta a aplicar no
        │                corpus de specs vivas no archive (v5.23.0).
        ▼
   ④ clarify            Spec → Spec refinada (in-place)
        │                Escaneia ambiguidades por taxonomia (10 categorias).
        │                Faz max 5 perguntas com opções e recomendação.
        │                Integra respostas diretamente na spec.
        ▼
 ┌──────────────┐
 │ PLANEJAMENTO │
 └──────┬───────┘
        │
   ⑤ plan              Spec → docs/specs/{feature}/plan.md + research.md + data-model.md
        │                Pesquisa tecnologias, define modelo de dados,
        │                contratos de API e cenários de teste.
        │                Valida contra constitution (gate obrigatório).
        ▼
   ⑥ checklist          Plan + Spec → docs/specs/{feature}/checklists/{domain}.md
        │                "Unit Tests for English" — valida QUALIDADE dos requisitos,
        │                não da implementação. Domínios: ux, api, security, performance.
        │                Itens com dono {auto}/{humano}; gaps abertos viram
        │                tarefas no create-tasks (loop gap → ação).
        ▼
 ┌──────────────┐
 │ IMPLEMENTAÇÃO│
 └──────┬───────┘
        │
   ⑦ create-tasks      Plan → Backlog de tarefas estruturado por fases
        │                Tarefas com IDs, criticidade e matriz de dependências.
        ▼
   ⑧ analyze           Spec + Plan + Tasks + Constitution → Relatório de consistência
        │                Detecta duplicações, ambiguidades, gaps de cobertura
        │                e violações de princípios. Estritamente READ-ONLY.
        ▼
   ⑨ execute-task      Task → Código implementado (workflow de 9 etapas)
        │                Análise → Localização → Planejamento → Implementação →
        │                Testes → Validação → Lint → Conclusão → Atualização.
        ▼
   ⑩ review-task       Tasks → Relatório de status com métricas e próximas ações
```

## Quando usar cada skill

| Momento | Skill | Entrada | Saída |
|---------|-------|---------|-------|
| Projeto novo ou feature grande | `briefing` | Conversa interativa | `briefing.md` |
| Após briefing | `constitution` | Briefing + contexto | `constitution.md` |
| Nova feature | `specify` | Descrição em linguagem natural | `spec.md` |
| Spec com dúvidas | `clarify` | `spec.md` existente | `spec.md` atualizada |
| Spec pronta | `plan` | `spec.md` | `plan.md`, `data-model.md`, `contracts/` |
| Antes de implementar | `checklist` | Spec + Plan | `checklists/{domain}.md` |
| Plan pronto | `create-tasks` | `plan.md` | Backlog estruturado |
| Tasks criadas | `analyze` | Todos os artefatos | Relatório de consistência |
| Task específica | `execute-task` | ID da tarefa | Código + relatório |
| Implementação "pronta" | `converge` | Spec + Plan + Tasks + código real | Gaps acionáveis como nova fase de tasks |
| Acompanhamento | `review-task` | Arquivo de tasks | Relatório de progresso |

## Atalhos — nem sempre é preciso percorrer todo o pipeline

- **Feature simples**: `specify` → `plan` → `create-tasks` → `execute-task`
- **Bug fix**: `bugfix` (skill independente, não requer pipeline)
- **Projeto existente sem docs**: `initialize-docs` → `briefing` → `constitution`
- **Só precisa de tasks**: `create-tasks` direto (se já tem contexto suficiente)

A `specify` também traz um guia de triagem "atualizar spec existente vs abrir
feature nova" (v5.22.0): mesma intenção/refino → atualizar a spec; intenção
mudou ou escopo explodiu → nova feature.

## Specs vivas e Delta Requirements (v5.23.0)

As specs de feature descrevem MUDANÇAS e são arquivadas em
`docs/specs/_archived/YYYY-MM-DD-<feature>/` quando concluídas. Para o
conhecimento "como o sistema se comporta AGORA" não evaporar no archive,
existe um **corpus canônico de specs vivas** em `docs/specs/current/`
(um arquivo por capability):

- A spec de feature pode declarar uma seção opcional `## Delta Requirements`
  com subseções `ADDED/MODIFIED/REMOVED/RENAMED Requirements`.
- No momento do archive (ação da `review-features`), o delta é validado por
  `delta-gate.sh` (estrutura do corpus, referências, "feature sem delta é
  inválida salvo skip explícito") e aplicado ao corpus por `delta-merge.sh`
  (merge atômico por capability).
- Conflito NUNCA é mergeado silenciosamente — vira bloqueio com diagnóstico
  (no fluxo autônomo, registro via `bloqueios.sh`).

Origem do modelo: benchmark do [OpenSpec](https://github.com/Fission-AI/OpenSpec)
(separação `specs/` = comportamento atual vs `changes/` = deltas propostos).

## Workflow: execute-task

O skill `execute-task` impõe um workflow completo de 9 etapas:

1. **Análise** - Detectar contexto e ler documentação
2. **Localização** - Encontrar tarefa no arquivo de tarefas
3. **Planejamento** - Definir escopo e identificar padrões
4. **Implementação** - Executar a tarefa
5. **Testes** - Rodar testes se aplicável
6. **Validação** - Verificar qualidade e consistência
7. **Lint** - Checar formatação e padrões
8. **Conclusão** - Gerar relatório de execução
9. **Atualização** - Marcar tarefa como concluída

## Protocolo: bugfix

O skill `bugfix` implementa um protocolo de 8 etapas destilado da prática de
corrigir bugs em arquiteturas multi-serviço, com foco em eliminar ciclos de
"corrige-revela-corrige":

- Classifica complexidade (simples vs. multi-camada)
- Rastreia o fluxo de dados completo antes de qualquer alteração
- Mapeia DTOs, enums e nomes de campo em todas as fronteiras
- Implementa correções em todas as camadas afetadas de uma vez
