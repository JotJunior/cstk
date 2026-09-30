# Requirements Checklist: Code Reconciliation (`reconcile-docs`)

**Purpose**: Validar a qualidade (completude, clareza, consistencia, mensurabilidade) dos requisitos de `spec.md` + `plan.md` antes de `create-tasks`. Nao testa implementacao.
**Created**: 2026-09-30
**Feature**: [spec.md](../spec.md)

Gate deterministico `requirement-coverage.sh spec.md`: `RESULT|requirements=18|covered=18|errors=0` (exit 0, zero FINDING) — todos os 18 FR tem cenario associado.

## Completude

- [x] CHK001 - Cada um dos 18 FR possui ao menos um cenario de aceite ou edge case associado? [Completude, Spec §FR-001..FR-018; gate requirement-coverage.sh 18/18] {auto}
- [x] CHK002 - Os documentos reconciliados e os NAO reconciliados (`research.md`, `checklists/`, `tasks.md`, `docs/specs/current/`) estao enumerados? [Completude, Spec §Assumptions "Escopo de documentos", FR-005, FR-017] {auto}
- [x] CHK003 - O comportamento para feature inexistente, nome ambiguo, `docs/specs/` vazio e feature sem `spec.md` esta definido? [Cobertura de Cenarios, Spec §US1-4, US2-3, Edge Cases, FR-014] {auto}
- [x] CHK004 - O comportamento sem argumentos, e com `--all` junto de `<feature>`, esta definido? [Completude, Plan contracts/cli-invocation.md §1 (mutuamente exclusivo; nenhum argumento = erro de uso)] {auto}
- [x] CHK005 - O destino do relatorio (onde e exibido) esta definido? [Completude, Plan contracts/cli-invocation.md "relatorio na conversa"; Spec FR-018 "sem duplicar o relatorio completo"] {auto}
- [x] CHK006 - O comportamento de `--dry-run` quanto a `reconciliation.md` (nao gravar) esta definido? [Completude, Spec §FR-011 "nenhum arquivo"; Plan contracts/cli-invocation.md `--dry-run`] {auto}
- [ ] CHK007 - O comportamento quando a `constitution` do projeto e inexistente ou ilegivel esta definido, dado que FR-007 depende dela para classificar "possivel regressao"? [Gap, Spec §FR-007; ausente em Edge Cases, plan e contratos (grep "constitution ausente" sem resultado)] {auto}

## Clareza

- [x] CHK008 - Os tipos de divergencia estao enumerados de forma fechada? [Clareza, Spec §Key Entities "Divergencia": desatualizada, removida, nao documentada, possivel regressao, nao verificavel] {auto}
- [x] CHK009 - "Ambiguo" no nome da feature esta definido operacionalmente (exato vs. substring)? [Clareza, Spec §Edge Cases "prefixo comum"; Plan contracts/cli-invocation.md §2: exato = unico; sem exato = candidatos por substring, exit 3; multiplos exatos = exit 4; research.md Decision sobre identidade] {auto}
- [x] CHK010 - O criterio de "possivel regressao" esta restrito e nao subjetivo? [Clareza, Spec §FR-007 "MUST/MUST NOT da feature ou principio da constitution"; Clarifications Q3] {auto}
- [x] CHK011 - Os marcadores inline (tokens, data, evidencia) estao especificados de forma parseavel? [Clareza, Spec §FR-009 delega ao plan; Plan §Summary `[reconciled:<kind> <date> evidence=<ref>]`; contracts/markers.md] {auto}
- [x] CHK012 - "Evidencia" tem formato verificavel (arquivo e trecho)? [Clareza, Spec §FR-008, SC-004; Plan §Riscos "`arquivo:linha` ou `absent:<path>`"] {auto}
- [ ] CHK013 - "Acerto pontual" (denominador de SC-005) esta definido de modo a separar casos elegiveis dos nao elegiveis? [Ambiguity, Spec §SC-005] {auto}

## Consistencia

- [x] CHK014 - `--all` (FR-003 "todas as features nos dois locais") e FR-015 (ativa prevalece; arquivada homonima nao reconciliada silenciosamente) sao consistentes? [Consistencia, Spec §FR-003 vs §FR-015/Edge Cases; resolvido em Plan contracts/cli-invocation.md §2 `archived-shadowed`] {auto}
- [x] CHK015 - A escrita de `reconciliation.md` (FR-018) e compativel com a allowlist de escrita de FR-006/FR-005? [Consistencia, Spec §FR-006 "documentacao de feature", FR-018; Plan §Technical Context Storage lista `reconciliation.md` entre os arquivos gravaveis] {auto}
- [x] CHK016 - FR-018 (registro so quando ha alteracao) e FR-012/SC-003 (idempotencia) sao consistentes? [Consistencia, Spec §FR-018 "execucao sem divergencia MUST NOT gravar nada"; Clarifications Q1] {auto}
- [x] CHK017 - Marcadores datados (FR-009) nao quebram a idempotencia (FR-012)? [Consistencia, Plan §Riscos "marcadores existentes nao sao re-datados"; Spec §Edge Cases "Reexecucao"] {auto}
- [x] CHK018 - As politicas de escrita para features arquivadas e ativas sao a mesma, com excecao unica do corpus `current/`? [Consistencia, Spec §FR-017, Clarifications Q5] {auto}
- [x] CHK019 - Os principios da constitution citados no plan (I-VI) batem com os invocados no spec (I no CHANGELOG, VI na veracidade)? [Consistencia, Spec §Assumptions "Local de entrega", FR-008; Plan §Constitution Check] {auto}

## Mensurabilidade / Criterios de Aceite

- [x] CHK020 - SC-001, SC-003 e SC-007 sao objetivamente verificaveis por comparacao de conjuntos de arquivos modificados? [Mensurabilidade, Spec §SC-001, SC-003, SC-007; Independent Test US3] {auto}
- [x] CHK021 - SC-002 ("100% das divergencias plantadas") tem base de teste definida? [Mensurabilidade, Spec §SC-002 "projeto de teste"; Plan §Testing fixture `tests/fixtures/reconcile-docs/`] {auto}
- [ ] CHK022 - Como SC-005 (>= 90% sem edicao manual) sera medido, e por quem, esta definido? [Gap, Spec §SC-005 — sem metodo de medicao; nao ha teste automatizavel] {humano}
- [x] CHK023 - O limite de desempenho de `--all` esta especificado? [Requisitos Nao-Funcionais, Plan §Performance Goals "cada script < 2 s"; custo semantico do LLM declarado fora de controle] {auto}

## Cenarios e Edge Cases

- [x] CHK024 - Falha parcial em `--all` (FR-013, SC-006) e requisito com cenario de aceite? [Cobertura, Spec §US2-2, FR-013, SC-006] {auto}
- [x] CHK025 - Codigo removido e codigo novo nao documentado tem tratamento e marcador distintos? [Cobertura de Edge Cases, Spec §Edge Cases, FR-009] {auto}
- [x] CHK026 - Projeto sem git tem comportamento definido e testavel? [Cobertura de Edge Cases, Spec §FR-016; Plan §Riscos/`git-probe.sh` fallback `no-git` testado] {auto}
- [x] CHK027 - Divergencia com `tasks.md` (tarefa concluida cujo codigo foi removido) tem destino definido? [Cobertura, Spec §Assumptions "Escopo de documentos" — apenas relatorio] {auto}
- [x] CHK028 - Escopo de deteccao (o que NAO e detectado) esta explicito? [Clareza, Spec §FR-004, Clarifications Q2 "nao verificavel"] {auto}

## Dependencias e Premissas

- [x] CHK029 - A relacao com `converge` (complementar, sem chamada cruzada) esta documentada? [Premissas, Spec §Assumptions "Diferenca para converge"; Plan §Structure "Relacao com converge"] {auto}
- [x] CHK030 - O nome da skill e a alternativa estao registrados como premissa (nao como requisito ambiguo)? [Premissas, Spec §Assumptions "Nome da skill"; FR-001] {auto}
- [ ] CHK031 - A prioridade relativa entre "gravar direto por padrao" (sem confirmacao) e a reversibilidade apenas via VCS e aceitavel para projetos sem git? [Risco, Spec §Assumptions "Modo padrao grava direto" x §FR-016 projeto sem VCS] {humano}

## Notes

- Items `{auto}` foram resolvidos contra spec/plan/contratos com a citacao; `[ ]` + marcador = gap aberto.
- Gaps abertos: CHK007 (constitution ausente) e CHK013 (definicao de "acerto pontual") -> `create-tasks` (definir/especificar); CHK022 e CHK031 -> decisao do dono do produto.
