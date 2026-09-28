# Mapeamento de Fontes

De onde vem cada parte da apresentacao. Coluna "Fato" = extraido pelo
script (nunca pelo redator); coluna "Narrativa" = lido e resumido pelo
redator, sempre com `@source`.

## Fundacao

| Slide | Arquivo | Fato (inventario) | Narrativa (redator) |
|-------|---------|-------------------|---------------------|
| `cover` | briefing §1 | `project` | titulo, subtitulo e frase de impacto a partir da visao |
| `manifesto` | briefing §1, §8 | nao | o porque do projeto, em tom de conviccao |
| `briefing` | `docs/briefing.md` ou `docs/01-briefing-discovery/briefing.md` | `briefing` (path) | cartoes: Visao, Usuarios, Escopo (MVP / fora de escopo), Restricoes, Prioridades |
| `constitution` | `docs/constitution.md` | `constitution` (versao), `principle` (numeral, titulo, inegociavel) | um cartao por principio: titulo + o que ele protege, em uma frase |
| `closing` | briefing §8 (Visao de Futuro) e specs ativas | nao | horizonte e chamada final |

## Specs

| Secao do slide | Arquivos a ler | O que extrair |
|----------------|----------------|---------------|
| titulo + lead | `spec.md` (titulo, User Story P1) | o beneficio central |
| O que e | `spec.md` (User Stories, Requirements, Key Entities) | a capacidade em linguagem de quem usa |
| Como foi pensada | `research.md` (Decisions e alternativas), `plan.md` (Summary, Structure Decision) | o problema e a escolha central com o motivo |
| Como foi enriquecida | `spec.md` §Clarifications, `checklists/*.md`, `converge-report.md` | perguntas que fecharam ambiguidades, gaps corrigidos |
| Como foi implementada | `tasks.md` (fases, Escopo Coberto/Excluido), `converge-report.md` | o que foi entregue e o estado real |
| metricas | inventario | `tasks`, `clarify-questions`, `clarify-sessions`, `converge`, `artifacts`, `stage` |

Spec viva (`docs/specs/current/*.md`): so ha o arquivo de capability com
os requisitos vigentes. Leia os FRs e a linha "Introduzida por" para
ligar a capacidade as specs arquivadas que a criaram. Sem tarefas nem
clarify: nao use `@metric` dessas chaves (aparecem como "nao registrado").

Spec sem `spec.md` (diretorio arquivado com outros artefatos): leia o
que existir (`plan.md`, `tasks.md`) e cite esse arquivo em `@source`.

## Ordem de leitura sugerida por spec

1. Linha do inventario (estagio, tarefas, clarify, converge).
2. `spec.md`: titulo, Clarifications, User Story P1.
3. `research.md`: decisoes (so os titulos e o "Rationale").
4. `tasks.md`: titulos das fases e "Escopo Coberto".
5. `converge-report.md`: ultimo outcome e achados, se houver.

Leia so o necessario para as quatro secoes: o objetivo e sintese, nao
transcricao.
