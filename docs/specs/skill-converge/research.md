# Research: Skill Converge — Reconciliação Spec-vs-Código

Documento produzido no Phase 0 do `/plan`. Resolve as decisões técnicas
abertas antes do design. As decisões de produto já foram fechadas na spec
(`## Clarifications`, sessão 2026-07-16, 5 perguntas); este documento cobre
as decisões de **arquitetura/algoritmo** que a spec deferiu explicitamente
para `/plan` (ver FR-020: "atribuição de severidade para `partial` … fica
deferida para `/plan`").

Referência de linhagem: `/speckit.converge` do
[github/spec-kit](https://github.com/github/spec-kit) (PR #3001). O modelo
de gap-types (`missing`/`partial`/`contradicts`/`unrequested`), o append-only
e a idempotência vêm daí; a numeração de fases do `tasks.md`, a integração
com `agente-00c`/`feature-00c` e a derivação de severidade a partir da
`constitution.md` local são adaptações específicas deste toolkit (ancoradas
em memória `reference_spec_kit_benchmark` da knowledge.db, read-back K=4 nesta
onda — referência histórica, não instrução).

---

## Decision 1: Divisão agente-semântico vs script-determinístico

**Decision**: `converge` é uma skill **agente-driven** (como `analyze`) para o
julgamento semântico (FR-003/FR-004), apoiada por **helpers POSIX sh
determinísticos** para toda a mecânica que precisa ser reproduzível byte-a-byte
(extração de paths/princípios, cálculo de severidade, numeração de fase,
dedup de idempotência, escrita append-only, contenção de path).

**Rationale**:
- FR-004 exige **leitura semântica estática pelo agente** (não rodar
  testes/build) — igual ao padrão read-only de `analyze`/`checklist`. Julgar
  se um arquivo "de fato implementa" a capacidade descrita é raciocínio, não
  regex; pertence ao agente.
- FR-011 (idempotência byte-a-byte) exige **determinismo** na escrita do
  `tasks.md`. O agente é não-determinístico por natureza; portanto extração de
  paths, numeração de fase, dedup e append **MUST** ser script POSIX
  (Constitution II — o próprio exemplo `CRITICAL` da spec, US2 Independent
  Test, é "um script nos paths declarados que não é POSIX sh puro").
- Espelha a anatomia real já existente: `analyze` (agente puro, sem
  `scripts/`) + `create-tasks` (agente + `scripts/next-task-id.sh` +
  `scripts/validate-tasks-template.sh`). `converge` é o híbrido dos dois.

**Alternatives considered**:
- *Tudo no agente (sem scripts)*: rejeitado — quebra FR-011 (a escrita do
  `tasks.md` viraria não-determinística; dois runs sobre o mesmo código
  poderiam gerar bytes diferentes).
- *Tudo em script (sem agente)*: rejeitado — FR-004 é explicitamente semântico
  ("de fato implementada, não apenas se o arquivo existe"); um script não
  distingue `partial` de `contradicts` de forma confiável.

---

## Decision 2: Onde vive a fronteira de idempotência (a chave do FR-011)

**Decision**: A idempotência é ancorada na **gap-key** = tripla normalizada
`(path do arquivo + tipo do Gap + requisito/task de origem)` — exatamente a
combinação fixada por FR-012. A key é embutida em cada tarefa de convergência
no `tasks.md` como marcador legível por máquina (comentário HTML:
`<!-- converge-key: <sha256-12> -->`), que o helper de dedup relê em execuções
futuras. A garantia de FR-011 é escopada a **"mesmo estado de código → mesmo
conjunto de gap-keys → nada novo a apendar → `tasks.md` inalterado (FR-010)"**.

**Rationale**:
- A key **NÃO** inclui a descrição em texto-livre do gap (que o agente pode
  redigir de forma ligeiramente diferente entre runs) — só os 3 atributos
  estruturais, estáveis por construção. Isso torna o dedup (FR-012) robusto a
  variação de redação.
- O tipo do Gap entra na key. Risco reconhecido: se o agente oscilar a
  classificação de um mesmo path entre `partial` e `contradicts` em runs
  distintos sobre o **mesmo** código, a key muda e o dedup falha. Mitigação:
  a SKILL.md fixa uma **rubrica de classificação determinística** (critérios
  objetivos por tipo) para que o mesmo estado de código produza o mesmo tipo.
  Esta é a tensão central da feature e está documentada como tal — não é
  varrida para baixo do tapete.
- Marcador como comentário HTML: invisível no render Markdown, não polui a UX
  do `tasks.md`, e é trivial de parsear com `grep` POSIX. Alinha com
  append-only (FR-009) — nunca toca tarefas pré-existentes.

**Alternatives considered**:
- *Key = hash do arquivo inteiro*: rejeitado — mudança irrelevante no arquivo
  (whitespace) invalidaria a key e reintroduziria o gap, quebrando FR-011.
- *Key só (path + tipo)*: rejeitado — FR-012 exige explicitamente incluir
  requisito/task de origem (dois requisitos podem tocar o mesmo path).
- *Persistir keys num arquivo lateral (`.converge-state`)*: rejeitado — cria
  artefato novo, contraria a clarification "sem novo arquivo de artefato
  dedicado"; o `tasks.md` já é a fonte de verdade da dedup.

---

## Decision 3: Algoritmo de severidade (incluindo `partial`, deferido pela FR-020)

**Decision**: Severidade é uma **função pura** `(tipo, prioridade-da-story,
viola-MUST?) → {CRITICAL|HIGH|MEDIUM|LOW}`, implementada em helper POSIX
determinístico, com esta tabela:

| Condição (avaliada em ordem, primeira que casa vence) | Severidade |
|-------------------------------------------------------|------------|
| Gap cuja causa viola princípio `MUST`/`NON-NEGOTIABLE` da constitution | `CRITICAL` |
| `missing` **ou** `contradicts` ligado a User Story `P1` | `HIGH` |
| `partial` ligado a User Story `P1` | `HIGH` |
| `missing` **ou** `contradicts` ligado a User Story `P2`/`P3` | `MEDIUM` |
| `partial` ligado a User Story `P2`/`P3` | `MEDIUM` |
| `unrequested` (qualquer prioridade) | `LOW` |

**Rationale**:
- CRITICAL por violação de `MUST` domina tudo (FR-006, SC-002: 100% dos
  achados que violam `MUST` recebem `CRITICAL`, nenhum rebaixado). Avaliado
  **primeiro**.
- HIGH/MEDIUM seguem a redação literal de FR-020 (P1→HIGH, P2/P3→MEDIUM para
  `missing`/`contradicts`).
- **`partial` (deferido pela FR-020)**: tratado com a **mesma severidade que
  `missing`/`contradicts` na mesma prioridade** (P1→HIGH, P2/P3→MEDIUM). Um
  path parcialmente implementado numa story P1 é tão bloqueante quanto um
  ausente — ambos deixam a story P1 incompleta. Consistente e sem introduzir
  um 5º nível.
- `unrequested` → `LOW` sempre (FR-020) — código a mais é revisão, não bloqueio.

**Alternatives considered**:
- *`partial` sempre um nível abaixo de `missing`*: rejeitado — subestima
  parciais de P1 (a own spec chama isso de "caso central", Edge Case
  `[x]`-mas-código-não-bate); um parcial silencioso é mais perigoso que um
  ausente óbvio.
- *Deixar `partial` sem severidade definida*: rejeitado — FR-020 deferiu ao
  `/plan` justamente para fechar aqui; deixar aberto violaria o gate.

---

## Decision 4: Extração determinística dos paths de intenção

**Decision**: Os paths auditáveis são extraídos **primariamente de `tasks.md`**
(que referencia arquivos concretos, em backticks e em linhas de subtarefa) e
**secundariamente de `plan.md`** (§Project Structure / árvore de código),
por helper POSIX (`grep`/`sed` sobre padrões de path). Cada path extraído
carrega seu **requisito/task de origem** (o heading `### N.M` ou o FR mais
próximo), satisfazendo FR-007 (todo achado cita path + origem).

**Rationale**:
- Edge Case da spec: `plan.md` ausente reduz contexto arquitetural mas **não**
  impede execução — `tasks.md` é a fonte primária de paths concretos.
- FR-018 (blast radius): cada path passa por contenção (Decision 6) **antes**
  de ser lido; paths fora do projeto-alvo viram achado `missing`/inconclusivo,
  nunca são abertos.
- Determinístico ⇒ compatível com FR-011.

**Alternatives considered**:
- *Extrair paths via agente*: rejeitado — não-determinístico, quebraria FR-011.
- *Só `plan.md`*: rejeitado — `plan.md` pode não existir (Edge Case), e a
  granularidade path↔task vive no `tasks.md`.

---

## Decision 5: Integração com orquestradores — gate in-phase, não novo stage

**Decision**: A execução automática entre `execute-task` e `review-task`
(US5/FR-015) é implementada como **quality-gate invocado pelo orquestrador na
fronteira execute-task→review-task**, no mesmo molde dos gates
`validate-documentation`/`owasp-security` já existentes — **NÃO** como uma nova
entrada em `pipeline.sh::_PL_STAGES_LIST`. O `ConvergenceReport` é registrado
como Decisão auditável via `state-decisions.sh register` + `state-ondas.sh
record-skill` (FR-019).

**Rationale**:
- `pipeline.sh::_PL_STAGES_LIST` é a lista canônica fixa de 10 etapas
  (`briefing … execute-task review-task review-features`), consumida por
  `stages`/`next`/`prev`/`detect-completion`. Inserir `converge` ali mudaria a
  ordem linear e exigiria um mapeamento `detect-completion` artificial (converge
  não gera artefato-arquivo próprio — seu output é uma Decisão + append no
  `tasks.md`).
- FR-019 **já** compara converge a `validate-documentation`/`owasp-security`,
  que são gates in-phase (rodam "após passo 7, antes do passo 8" no Loop
  principal — ver `agente-00c-feature-orchestrator.md` §Quality Gates), não
  stages. Seguir esse padrão é o caminho de menor disrupção e maior coerência.
- FR-015 exige **incondicional** (sem flag opt-out): o gate roda sempre na
  transição, sem consultar configuração.
- CRITICAL não trava sozinho (FR-019): o orquestrador decide escalar para
  bloqueio humano, idêntico ao tratamento dos demais gates `critical`/`high`.

**Alternatives considered**:
- *Novo stage `converge` em `_PL_STAGES_LIST`*: rejeitado — disrupção em
  `next`/`prev`/`detect-completion`, mapeamento de artefato forçado, e
  contradiz a própria FR-019 (que o equipara a gates, não a stages).
- *Opt-in por flag*: rejeitado — FR-015 é literal "MUST NOT expor flag de
  opt-out/opt-in".

---

## Decision 6: Contenção de path standalone (FR-018) sem acoplar ao runtime 00c

**Decision**: `converge` traz um helper de contenção **próprio e mínimo**
(`realpath`/resolução POSIX + verificação de prefixo contra o diretório do
projeto-alvo), em vez de depender de `agente-00c-runtime/scripts/path-guard.sh`.

**Rationale**:
- FR-014 exige modo **standalone** (SC-006: completa sem orquestrador ativo).
  Acoplar ao `path-guard.sh` (que é FR-024 do agente-00c, orientado a
  state-dir/zonas proibidas do orquestrador) arrastaria semântica do
  orquestrador para dentro de um uso solo.
- O escopo de contenção do converge é estreito: "o path resolvido está **dentro**
  do diretório do projeto-alvo?" (FR-018). Um helper enxuto e POSIX cobre isso
  sem herdar o modelo de ameaça completo do orquestrador.
- Constitution II: sem dep externa; `realpath` tem fallback POSIX
  (`cd`+`pwd -P`) quando ausente (macOS/zsh — ver CLAUDE.md global "não dependa
  de GNU-only").

**Alternatives considered**:
- *Reusar `path-guard.sh`*: rejeitado para o core standalone (acoplamento);
  pode ser considerado como reforço **adicional** quando converge roda DENTRO
  de um orquestrador, mas não é dependência do caminho standalone.

---

## Decision 7: Escopo de infraestrutura

**Decision**: Majoritariamente **N/A** (execução local, síncrona, read-only no
alvo). A única decisão de infra aplicável é **idempotência** — já resolvida na
Decision 2 (chave = paths declarados + conteúdo presente; sem TTL; resultado
determinístico que deriva do estado atual do código, não expira). Confirma o
bloco "Decisões de infraestrutura" da spec (linhas 48-57).

**Rationale**: converge não introduz scheduling, sessão persistente, refresh de
token, rotação de chaves nem mutex multi-processo. Nenhuma superfície de rede,
auth ou dados sensíveis próprios (roda sobre artefatos locais do projeto-alvo).

**Alternatives considered**: N/A.
