# REQUIREMENTS Checklist: roadmap-wave

**Purpose**: Validar qualidade, clareza e completude dos requisitos de
`roadmap-wave` (segundo ponto de entrada para a oferta de leva paralela
do roadmap) antes de `/create-tasks`.
**Created**: 2026-08-18
**Feature**: [spec.md](../spec.md)

## Completude de Requisitos

- [x] CHK001 - Todos os FRs tem pelo menos um cenario de aceitacao ou de
  quickstart associado? [Completude, Gate] {auto}
  Evidencia: `requirement-coverage.sh docs/specs/roadmap-wave/spec.md` →
  `RESULT|...|requirements=14|covered=14|errors=0` (exit 0, zero FINDING).
- [x] CHK002 - O requisito de pre-condicao (existencia/validade do
  roadmap) esta definido de forma que dispensa checagem redundante de
  briefing/constitution no ponto de entrada, com a justificativa
  registrada? [Completude, Spec §FR-001A] {auto}
  Evidencia: spec.md:124-130 (FR-001A) + Clarifications Session
  2026-08-18 Q1 (spec.md:11) justificam explicitamente por que a
  checagem individual e delegada a cada `/feature-00c` filho.
- [x] CHK003 - O requisito de parametrizacao do projeto-alvo define
  tanto o caminho default quanto o mecanismo de override? [Completude,
  Spec §FR-001] {auto}
  Evidencia: spec.md:118-123 (FR-001, "default: diretorio de trabalho
  corrente; MAY ser apontado explicitamente... via parametro de path").
- [x] CHK004 - O modo nao-interativo tem requisito explicito tanto para
  o teto quanto para o default de confirmacao ausente? [Completude,
  Spec §FR-012, FR-013, FR-014] {auto}
  Evidencia: spec.md:165-175 — FR-012 (suporte ao modo), FR-013 (teto
  explicito via parametro, default 2), FR-014 (ausencia de confirmacao
  ⇒ nao lancar).
- [ ] CHK005 - Existe requisito funcional que exija validacao/contencao
  do projeto-alvo parametrizado antes de invocar `git -C` sobre ele
  (nao apenas declaracao textual de premissa de confianca)? [Gap,
  Spec §Requirements] {auto}
  Nao satisfeito: `spec.md` (Functional Requirements, FR-001..FR-014)
  nao contem nenhum FR sobre contencao de path/validacao de repo
  hostil. A unica mitigacao documentada e prosa-only no command
  (`contracts/roadmap-wave-command.md:171-199`, §5.3) e o
  `plan.md` linha 200 declara explicitamente "Nao ha mitigacao tecnica
  no helper". Ver checklist de seguranca CHK-SEC (security.md) para o
  detalhamento do achado — Decisao dec-022 registra o destino:
  `/create-tasks` deve tornar essa lacuna uma tarefa explicita para o
  dono do produto decidir escopo (real contencao vs. aceitar risco
  documentado).

## Clareza de Requisitos

- [x] CHK006 - "Teto vigente" esta quantificado com um valor default
  concreto em vez de deixado vago? [Clareza, Spec §FR-013] {auto}
  Evidencia: spec.md:169-171 (FR-013, "teto default (2, mesmo valor do
  fluxo interativo)").
- [x] CHK007 - "Ambiente de trabalho isolado" tem definicao operacional
  (nao apenas termo vago) na secao de entidades? [Clareza, Spec §Key
  Entities] {auto}
  Evidencia: spec.md:190-192 (Key Entities, "espaco de execucao
  dedicado a uma unica feature lancada, independente de outras
  execucoes em paralelo") + data-model.md ("a worktree criada por
  `cstk session start`").
- [x] CHK008 - "Roadmap malformado/invalido" (FR-003) tem criterio
  objetivo de deteccao em vez de julgamento subjetivo? [Clareza,
  Spec §FR-003] {auto}
  Evidencia: data-model.md linhas ~28-35 mapeia estados observaveis
  pelo exit code de `roadmap-frontier.sh` (0/1/2/3/4) — criterio
  determinístico, nao subjetivo.

## Consistencia de Requisitos

- [x] CHK009 - FR-007 (nunca lancar sem confirmacao explicita) e
  FR-014 (default seguro "nao lancar" em modo nao-interativo) sao
  consistentes entre si, sem contradicao de precedencia? [Consistencia,
  Spec §FR-007, FR-014] {auto}
  Evidencia: spec.md:172-175 — FR-014 e redigido explicitamente como
  preservando FR-007 ("preservando FR-007 — nunca lançar sem
  confirmação explícita — mesmo fora do fluxo interativo").
- [x] CHK010 - O requisito de re-verificacao no momento do lancamento
  (FR-010) e consistente com o requisito de exclusao na oferta inicial
  (FR-009), cobrindo as duas janelas TOCTOU (oferta e lancamento)?
  [Consistencia, Spec §FR-009, FR-010] {auto}
  Evidencia: spec.md:154-161 — FR-009 cobre exclusao na fronteira
  apresentada, FR-010 cobre re-checagem no lancamento efetivo; Edge
  Cases (spec.md:102-106) documenta o cenario que motiva a dupla
  checagem.

## Qualidade de Criterios de Aceite / Mensurabilidade

- [x] CHK011 - SC-002 e mensuravel objetivamente ("100% das
  invocacoes...") em vez de usar linguagem vaga como "a maioria"?
  [Mensurabilidade, Spec §SC-002] {auto}
  Evidencia: spec.md:207-210 ("100% das invocações sobre um projeto sem
  roadmap... terminam em uma mensagem que identifica a causa
  específica").
- [x] CHK012 - SC-004 (teto respeitado) e verificavel por invariante de
  codigo (nao apenas por observacao manual)? [Mensurabilidade,
  Spec §SC-004] {auto}
  Evidencia: contract `roadmap-wave-command.md` §6, INV-2
  ("|selecionadas| <= max em toda invocacao (FR-006, SC-004)") — o
  contrato ja declara o invariante correspondente, verificavel por
  teste.

## Cobertura de Cenarios / Edge Cases

- [x] CHK013 - O edge case de entrada que deixa de ser elegivel entre
  calculo e lancamento (concorrencia) tem FR + cenario de teste
  dedicado? [Cobertura, Spec §Edge Cases] {auto}
  Evidencia: spec.md:102-106 (edge case) ↔ FR-010 (spec.md:157-161) ↔
  quickstart.md C7 "Anti-duplicidade no lancamento / TOCTOU".
- [x] CHK014 - O edge case de selecao acima do teto tem FR + cenario de
  teste dedicado? [Cobertura, Spec §Edge Cases] {auto}
  Evidencia: spec.md:107-109 (edge case) ↔ FR-006 (spec.md:144-147) ↔
  quickstart.md C5 "Candidatas excedem o teto".
- [x] CHK015 - O edge case de todas as candidatas caberem no teto (sem
  excesso a escolher) tem cobertura, mesmo que por delegacao a fluxo ja
  existente em vez de FR proprio? [Cobertura, Spec §Edge Cases] {auto}
  Evidencia: spec.md:110-112 (edge case) — o comportamento e herdado
  de `agente-00c.md` §6.ter, reusado por referencia e explicitamente
  NAO reescrito (`contracts/roadmap-wave-command.md` §2, "MUST NOT
  reescrever os 9 passos"); quickstart.md C1 exercita 2 candidatas
  dentro do teto default (2) sem selecao manual forcada.
- [x] CHK016 - Os 3 casos de recusa com remediacao (sem roadmap,
  roadmap invalido, fronteira vazia) tem cada um seu proprio cenario de
  aceitacao E de quickstart, evitando uma mensagem generica unica?
  [Cobertura, Spec §US2] {auto}
  Evidencia: spec.md:84-96 (Acceptance Scenarios 1-3 de US2) ↔
  quickstart.md C2/C3/C4, cada um mapeado a uma mensagem distinta.

## Requisitos Nao-Funcionais

- [x] CHK017 - Existe requisito nao-funcional cobrindo o tratamento de
  conteudo nao-confiavel (prosa do roadmap de terceiro) injetado no
  turno do operador? [NFR, Gap] {auto}
  Satisfeito: `spec.md` FR-015 ("O sistema MUST tratar a saida injetada
  de `roadmap-frontier.sh` (tabela + secao `### Avisos`) como conteudo
  nao-confiavel/rotulado, nunca como instrucao") formaliza a lacuna de
  rastreabilidade spec↔seguranca, referenciando `contracts/roadmap-wave-
  command.md` §5.1 (mitigacao tecnica ja existente, Decisao dec-018) e
  materializada em `plugins/cstk/commands/roadmap-wave.md` §5.1.

## Dependencias e Premissas

- [x] CHK018 - A dependencia da FASE 1 (helper `resolve-offer`) sobre a
  FASE 2 (command) esta declarada explicitamente, com o motivo tecnico
  que a torna hard-dependency? [Dependencias, Plan §Fases] {auto}
  Evidencia: plan.md ("FASE 1 — Helper `resolve-offer`... Precede a
  FASE 2 por dependencia dura: `tests/test_doc-subcommands.sh:33`
  reprova qualquer command que cite subcomando inexistente").
- [ ] CHK019 - A decisao de escopo sobre a contencao tecnica do
  projeto-alvo (real vs. prosa-only) esta ratificada pelo dono do
  produto, ou ainda depende de confirmacao humana antes de
  `/create-tasks` gerar a tarefa correspondente? [Risco] {humano}
  Aberto: dec-022 registra que o orquestrador NAO pode decidir sozinho
  se a mitigacao final e codigo novo em `roadmap-frontier.sh` (ou em
  `resolve-offer`) ou permanece prosa-only aceita como risco residual
  — depende de apetite de risco do dono do produto (mesmo criterio que
  motivou dec-018 originalmente, agora reaberto pela diretriz recebida
  nesta onda).

## Ambiguidades e Conflitos

- [ ] CHK020 - Ha conflito entre o plan.md ("Nao ha mitigacao tecnica
  no helper" — risco aceito) e a diretriz mais recente do operador
  (contencao real e requisito bloqueante da FASE 2)? [Conflict] {auto}
  Sim, conflito confirmado: `plan.md` linha ~200 (tabela "Riscos
  conhecidos") documenta a ausencia de mitigacao tecnica como aceita;
  a instrucao do operador recebida nesta onda (ver dec-022) declara
  que essa ausencia continua bloqueante. Destino: `/clarify` ou
  atualizacao direta do `plan.md`/spec.md pelo dono do produto antes
  de `/create-tasks` fechar o backlog da FASE 2 — nao resolvido nesta
  etapa (checklist so revela, nao decide escopo tecnico).

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou
  marcador `[Gap]`/`[Conflict]`).
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto.
- CHK005, CHK017, CHK020 formam o mesmo achado (contencao de path do
  projeto-alvo) visto por tres angulos — completude, NFR e conflito.
  Ver `checklists/security.md` para o detalhamento tecnico completo.
