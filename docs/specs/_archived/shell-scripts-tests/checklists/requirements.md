# Requirements Checklist: shell-scripts-tests

**Purpose**: validar qualidade dos requisitos da spec antes de decompor em tarefas. "Unit tests for English" — testa o texto, nao a implementacao.
**Created**: 2026-04-19
**Feature**: [spec.md](../spec.md)

## Completude de Requisitos

- [x] CHK001 - O conjunto de scripts sob teste esta listado exaustivamente e e inequivoco? [Completude, Spec §Contexto]
- [ ] CHK002 - Existe requisito que cubra o que acontece quando um script e renomeado ou removido? [Gap, Spec §User Story 5]
- [ ] CHK003 - Requisitos cobrem tanto execucao completa da suite quanto execucao parcial (subconjunto)? [Completude, Spec §FR-002, Quickstart §7]
- [x] CHK004 - Ha requisito sobre o que acontece quando o test runner em si falha (ex: `mktemp` indisponivel, permissoes)? [Gap]
  → Resolvido: Clarifications Q5 + FR-003 introduziram status ERROR distinto
  de FAIL — "harness ou ambiente impediu a avaliacao (ex: ferramenta POSIX
  ausente, falha ao criar tmpdir, setup do teste crashou)". Exit code 0 exige
  zero FAILs E zero ERRORs.
- [x] CHK005 - A governanca (FR-009) cobre script adicionado SEM teste E script removido COM teste orfao? [Completude, Spec §FR-009]
  → Resolvido: FR-009 reescrito cobre os dois lados explicitamente — "Remocao
  de um script com teste orfao (teste apontando para arquivo inexistente)
  tambem DEVE ser reportada nos dois modos".

## Clareza e Mensurabilidade

- [x] CHK006 - E "tempo curto o suficiente para pre-commit" (FR-008) quantificado com numero absoluto na propria secao ou via link explicito a SC-003? [Clareza, Spec §FR-008]
- [ ] CHK007 - E "ambiente padrao de um dev do projeto" (FR-002) definido em algum lugar (ex: macOS + /bin/sh? Linux? ambos?)? [Ambiguity, Spec §FR-002]
- [ ] CHK008 - E "maquina de desenvolvimento tipica" (SC-003) qualificado com baseline (ex: CPU, RAM) ou assumido como "qualquer laptop moderno"? [Clareza, Spec §SC-003]
- [ ] CHK009 - Pode SC-004 ("95% das vezes a mensagem e suficiente para reproduzir") ser objetivamente medida, ou depende de julgamento subjetivo? [Mensurabilidade, Spec §SC-004]
- [x] CHK010 - SC-005 ("zero bugs da mesma classe em 6 meses") tem criterio claro de o que constitui "mesma classe"? [Ambiguity, Spec §SC-005]
  → Resolvido: SC-005 reformulado enumera classes especificas — (a) mau
  tratamento de saida de `grep -c` sem matches, (b) ausencia de argumento
  obrigatorio sem mensagem de uso clara. "Mesma classe" agora e referencia
  fechada, nao subjetiva.
- [x] CHK011 - FR-011 lista os campos minimos da mensagem de falha (script, cenario, comando, stdout, stderr, expectativa) — falta algum campo obviamente util (ex: exit code, tmpdir preservado para inspecao)? [Completude, Spec §FR-011]
  → Resolvido: FR-011 atualizado inclui "exit code observado" e ainda exige,
  para status ERROR, "a causa do erro de ambiente (ex: 'mktemp nao encontrado
  no PATH')".
- [x] CHK012 - E "determinista" (FR-007) definido como "mesmo veredito" ou "mesmo byte-a-byte na saida"? [Ambiguity, Spec §FR-007]
  → Resolvido: FR-007 explicitamente diz "produzem exatamente o mesmo
  veredito" — granularidade fixada em veredito (PASS/FAIL/ERROR por cenario),
  nao saida byte-a-byte.

## Consistencia

- [x] CHK013 - User Story 1 promete "status por script" — isso bate com FR-003 que pede granularidade "por cenario"? [Consistency, Spec §US1, §FR-003]
- [x] CHK014 - Edge case "Ctrl+C nao deixa tmpdir pendurado" esta refletido em algum FR, ou so vive na secao Edge Cases? [Gap, Spec §Edge Cases]
  → Resolvido: FR-005 reescrito enumera explicitamente "(c) interrupcao
  externa (Ctrl+C / SIGINT, SIGTERM)" como condicao em que o tmpdir nao pode
  permanecer.
- [x] CHK015 - Edge case "scripts rodam em bash/dash/zsh — falha vs warning" tem decisao refletida em FR, ou fica em aberto? [Ambiguity, Spec §Edge Cases]
  → Resolvido: FR-013 (novo) fixa iteracao 1 em `sh <script>` apenas e declara
  matriz multi-shell explicitamente fora de escopo, com extensao futura via
  variavel de configuracao. Tambem coberto em Clarifications Q4.
- [ ] CHK016 - Edge case "dois testes em paralelo colidem em tmpdir" esta coberto por FR-005, ou paralelismo e explicitamente fora de escopo? [Conflict, Spec §FR-005, §Edge Cases]
- [x] CHK017 - Diretiva "execucao local-only nesta iteracao" (FR-012) esta consistente com a ausencia de requisito que proiba side effects de rede (hoje implicito)? [Consistency, Spec §FR-012]

## Cobertura de Cenarios

- [x] CHK018 - Requisitos exigem que cada script tenha pelo menos UM caso de sucesso E UM caso de entrada invalida? FR-006 pede ambos — os 5 scripts terao cada um coberto? [Cobertura, Spec §FR-006]
- [x] CHK019 - A regressao do bug de `metrics.sh` (FR-004) esta enumerada com cenarios especificos suficientes para distinguir bug resolvido de bug disfarcado? [Clareza, Spec §FR-004]
- [ ] CHK020 - Ha cobertura de requisitos para scripts que aceitam flags mutuamente exclusivas ou combinadas (ex: `scaffold.sh --dry-run --force`)? [Gap]
- [ ] CHK021 - Ha requisito sobre testar scripts com entrada contendo caracteres especiais (espacos em path, UTF-8, BOM)? O edge case menciona mas nenhum FR formaliza. [Gap, Spec §Edge Cases]

## Requisitos Nao-Funcionais

- [ ] CHK022 - Performance (SC-003, <30s) esta expressa como target por execucao E permanece valida conforme mais scripts sao adicionados? [Cobertura, Spec §SC-003]
- [x] CHK023 - Determinismo (FR-007) aplica-se a stdout/stderr/exit code, ou tambem a ordem de execucao dos cenarios? [Ambiguity, Spec §FR-007]
  → Resolvido (junto com CHK012): FR-007 declara "exatamente o mesmo
  veredito" — granularidade fixada em veredito por cenario.
- [x] CHK024 - Isolamento (FR-005) cobre explicitamente falha do teste (limpeza via trap) E interrupcao externa (Ctrl+C)? [Completude, Spec §FR-005]
  → Resolvido: FR-005 enumera as 3 condicoes — (a) execucao bem-sucedida,
  (b) falha natural do teste, (c) interrupcao externa (Ctrl+C/SIGINT,
  SIGTERM) — em todas o tmpdir nao pode permanecer.

## Premissas e Dependencias

- [ ] CHK025 - Esta documentado que a suite depende de ferramentas POSIX disponiveis (`find`, `grep`, `awk`, `mktemp`) — ou isso e premissa implicita? [Assumption]
- [ ] CHK026 - Esta claro que a feature NAO altera contrato dos scripts existentes (so observa comportamento)? [Assumption]
- [x] CHK027 - Esta claro se o mantenedor deve rodar a suite manualmente (sem hook) ou se uma recomendacao de uso (ex: entrada no README, alias em Makefile) faz parte do escopo? [Gap, Spec §FR-012]
  → Resolvido: FR-012 declara "rodada manualmente pelo mantenedor antes de
  commitar. Nao ha integracao automatica com CI remoto ou hooks de Git nesta
  iteracao" — fluxo manual fica explicito.

## Ambiguidades e Gaps Residuais

- [x] CHK028 - SC-005 ("6 meses sem bug da mesma classe") e claramente nao-verificavel antes da implementacao — deveria ser reformulado como "a suite contem teste especifico que capturaria esta classe de bug"? [Mensurabilidade, Spec §SC-005]
  → Resolvido: Clarifications Q1 + SC-005 reformulado — agora exige presenca
  de testes nomeados que exercitariam cada classe de bug ja conhecida,
  verificavel imediatamente via `tests/run.sh --list`. Metrica retrospectiva
  substituida por verificacao de presenca.
- [x] CHK029 - O contrato de orfao na User Story 5 diz "ausencia e detectavel" — isso exige modo explicito (`--check-coverage`) ou deve aparecer tambem na execucao normal? A spec nao decide. [Ambiguity, Spec §US5, §FR-009]
  → Resolvido: Clarifications Q2 + FR-009 reescrito definem dois niveis —
  (a) execucao normal mostra orfaos como `ORPHANS: N` warning sem alterar
  exit code; (b) `--check-coverage` e gate estrito com exit !=0.
- [x] CHK030 - FR-012 fala em "compativel com CI futuro" sem definir criterio — que propriedades concretas a suite precisa preservar para ser CI-ready (ex: exit code fiel, sem TTY assumido, sem dependencia de editor)? [Ambiguity, Spec §FR-012]

## Notes

- Marque items com `[x]` quando validados.
- Items `[Gap]` e `[Ambiguity]` sao candidatos naturais a `/clarify` ou a atualizacao da spec antes de implementar.
- Items `[Mensurabilidade]` em SCs sugerem reformulacao da metrica — SC-004 e SC-005 em particular.

## Revisao — 2026-04-19

### Passam sem ressalva (7/30)

| ID | Evidencia na spec |
|----|-------------------|
| CHK001 | §Contexto lista os 5 scripts nominalmente com skill associada |
| CHK006 | FR-008 tem "(ver SC-003)" — link explicito ao numero absoluto 30s |
| CHK013 | FR-003 e estritamente mais granular que US1 — consistente, nao conflita |
| CHK017 | FR-012 atualizado diz "exclusivamente local" — rede fica proibida por construcao |
| CHK018 | FR-006 enumera a/b/c explicitamente para cada script |
| CHK019 | FR-004 cita "tasks.md sem checkboxes, tasks.md sem checkboxes de algum tipo" + US2 AS1-3 detalha 3 cenarios |
| CHK030 | FR-012 atualizado define CI-ready como "POSIX limpo, sem deps alem do requisito local" |

### Requerem atencao antes de `/create-tasks` (23/30)

Por ordem de impacto:

**Criticos** — bloqueiam qualidade do backlog se ignorados:

- CHK028 (SC-005 retrospectivo) — sugerir reformular para "a suite contem teste que capturaria esta classe".
- CHK029 (orfao: suite normal ou so `--check-coverage`?) — o plan.md ja escolheu `--check-coverage` sem warning na suite normal; a spec deveria refletir esta decisao em FR-009.
- CHK014 / CHK024 (Ctrl+C nao-coberto por FR) — tem impacto pratico (trap EXIT e decisao de design ja tomada no plan). Promover edge case para FR explicito.
- CHK015 (multi-shell — falha ou warning?) — research.md Decision 3 ja decidiu "so /bin/sh na iteracao 1". Refletir na spec.
- CHK004 (runner falha por ambiente) — adicionar FR que diga "falha de pre-requisito do harness deve ser distinguivel de falha do script sob teste" (edge case ja alerta).

**Medios** — podem ser resolvidos com ajuste textual simples:

- CHK007 / CHK008 (termos "ambiente padrao", "maquina tipica" sem baseline) — definir baseline: macOS ou Linux com `/bin/sh`, `find`, `grep`, `awk`, `mktemp` disponiveis.
- CHK009 / CHK010 (SC-004 e SC-005 subjetivos) — reformular ou aceitar como metricas indicativas nao-gate.
- CHK011 (campos de mensagem de falha) — acrescentar exit_code explicitamente a FR-011.
- CHK012 / CHK023 (determinismo nao define granularidade) — esclarecer que e "mesmo veredito e mesma lista de cenarios executados", nao byte-a-byte.
- CHK022 (SC-003 nao escala) — adicionar nota "SC-003 reexaminado quando N scripts > 15".

**Baixos** — registrar como assumption ou deixar para iteracao 2:

- CHK002 (renomeacao) — tratada como remocao+adicao, OK implicita.
- CHK003 (execucao parcial) — US4 AS3 menciona; elevar a FR se quiser reforco.
- CHK005 (remocao de teste orfao) — US5 AS2 ja cobre; so falta refletir em FR-009.
- CHK016 (paralelismo) — explicitar "execucao sequencial na iteracao 1".
- CHK020 / CHK021 (flags combinadas, caracteres especiais) — nao-MVP, backlog P3.
- CHK025 / CHK026 / CHK027 (assumptions implicitas) — adicionar secao §Premissas na spec.

### Recomendacao

Antes de `/create-tasks`:

1. Decidir sobre os 5 CHK `Criticos`. Alguns (Ctrl+C, multi-shell) ja tem decisao no research.md — basta promover a FR na spec para fechar o loop.
2. Reformular SC-004 e SC-005 (CHK009, CHK010, CHK028) para criterios verificaveis na implementacao, nao 6 meses depois.
3. Adicionar secao §Premissas com ambiente POSIX minimo (resolve CHK007, CHK008, CHK025).

Apos esses 3 passos, restam ~12 items de baixa prioridade que podem virar issues de iteracao 2 sem bloquear o backlog inicial.
