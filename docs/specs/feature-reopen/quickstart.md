# Quickstart: feature-reopen

Cenarios que validam a implementacao end-to-end. Um por fluxo critico, cobrindo
as 3 user stories, os dois backends (incluindo linhagem com backend misto —
Scenario 19) e os caminhos de erro.

Convencoes: `<PAP>` = raiz do projeto-alvo; `<SD>` =
`<PAP>/.claude/feature-00c-state/<short>`; `RS` =
`~/.claude/skills/agente-00c-runtime/scripts`.

> Todos os cenarios devem rodar em macOS **e** Ubuntu (CI) sem ajuste — a
> divergencia de sidecars WAL/SHM entre as duas plataformas ja quebrou a
> release v6.4.0 e e alvo explicito do Scenario 3.

---

## Scenario 1: Reabrir feature concluida, backend `state.json` (P1, happy path)

1. Escolher uma feature com execucao `concluida` persistida em `state.json`
   (21 disponiveis no repo de referencia).
2. `cp -R` do state-dir para um sandbox e registrar o `sha256` de `state.json`.
3. `/feature-00c --reopen <short> "acrescentar tratamento de timeout"`.
4. Ao parecer, confirmar `reabrir`.
5. **Expected**:
   - `<SD>/rounds/r01/state.json` existe e o `sha256` **bate** com o do passo 2;
   - `<SD>/state.json` novo existe, `status = em_andamento`, sem `waves`;
   - `state-rw.sh get --field '.previous_round'` devolve objeto com
     `round=r01`, `status=concluida`;
   - `<SD>/state-history/`, `<SD>/backups/` e `enforcement-log.jsonl`
     **permaneceram na raiz** (nao entraram no round);
   - `<SD>/rounds/.rotate-journal` **nao** existe;
   - a pipeline chega a primeira onda de trabalho sem nenhuma edicao manual
     (SC-001).

---

## Scenario 2: Reabrir feature concluida, backend `state.db` (P1, FR-010)

1. Escolher uma das 5 execucoes concluidas em `state.db`.
2. Sandbox + `sha256` de `state.db`, `state.db-wal`, `state.db-shm` (anotar
   quais existem — no Ubuntu os sidecars podem nao existir).
3. `/feature-00c --reopen <short> "<incremento>"`, confirmar `reabrir`.
4. **Expected**:
   - `<SD>/rounds/r01/` contem **exatamente um** arquivo: `state.db`;
   - **nenhum** `state.db-wal` nem `state.db-shm` dentro do round;
   - `sqlite3 <SD>/rounds/r01/state.db 'PRAGMA integrity_check;'` ⇒ `ok`;
   - a contagem de decisoes do round bate com a de antes da rotacao (o
     checkpoint dobrou o WAL no `.db`, nao perdeu commit);
   - comportamento observavel **identico** ao Scenario 1 (FR-010).

---

## Scenario 3: Paridade macOS × Ubuntu dos sidecars (regressao v6.4.0)

1. Rodar Scenario 2 nas duas plataformas.
2. Comparar a **listagem** de `rounds/r01/`.
3. **Expected**: listagens identicas nas duas plataformas — exatamente
   `state.db`. Nenhuma asserção de teste depende da existencia de `-wal`/`-shm`,
   que sao removidos apos o checkpoint. Este e o cenario que impede a repeticao
   da quebra de release v6.4.0.

---

## Scenario 4: Segunda reabertura (P1, FR-009, AS-1.5)

1. Partir do estado final do Scenario 1.
2. Levar a execucao a `concluida` (ou `abortada`).
3. `/feature-00c --reopen <short> "<segundo incremento>"`, confirmar.
4. **Expected**:
   - `rounds/r01/` e `rounds/r02/` coexistem;
   - `r01` **byte a byte identico** ao que era (SC-002) — `cmp` contra a copia
     do Scenario 1;
   - `.previous_round.round == "r02"`;
   - `ls rounds/` ordena `r01` antes de `r02` sem parsing numerico (FR-009).

---

## Scenario 5: Recusa — short-name sem execucao anterior (FR-002, error case)

1. Escolher um `<short>` que **nunca** teve execucao.
2. Anotar se `<PAP>/.claude/feature-00c-state/<short>` existe (nao deve).
3. `/feature-00c --reopen <short> "<descricao>"`.
4. **Expected**:
   - exit `4`;
   - mensagem instrui a abertura normal `/feature-00c <short> "<descricao>"`;
   - **nenhum arquivo ou diretorio criado** — em especial o state-dir continua
     inexistente e nenhum `.lock/` ou `.gitignore` foi semeado.

> Este cenario e o que prova que a recusa precede o `acquire` do lock e o
> `init` — ambos criam diretorio antes de validar (Decision 7).

---

## Scenario 6: Recusa — execucao ainda viva (FR-003, error case)

1. Preparar state-dir com `status = em_andamento`; registrar `sha256`.
2. `/feature-00c --reopen <short> "<descricao>"`.
3. Repetir com `status = aguardando_humano`.
4. **Expected** (nos dois):
   - exit `5`;
   - mensagem aponta `/feature-00c-resume` e `/feature-00c-abort` — escopo de
     **feature**, nunca `/agente-00c-*` (FR-017);
   - `sha256` do estado vivo **inalterado**; nenhum round criado.

---

## Scenario 7: Round anterior abortado (FR-020)

1. State-dir com `status = abortada` e `finished_at` preenchido.
2. `/feature-00c --reopen <short> "<incremento>"`.
3. **Expected**:
   - a reabertura **e permitida** (terminal legitimo);
   - o parecer declara explicitamente que o round anterior **nao chegou ao fim**;
   - `.previous_round.status == "abortada"`.

---

## Scenario 8: Triagem recomenda feature nova (P2, FR-004/005/006)

1. `/feature-00c --reopen <short> "<descricao claramente estranha a spec>"`.
2. **Expected (parte A)**: parecer recomenda `abrir-feature-nova`, justifica
   citando os pontos comparados, instrui como abrir — e **nao** cria a feature
   nova por conta propria (FR-005). Nada escrito no disco ate aqui (FR-004).
3. Confirmar mesmo assim `reabrir`.
4. **Expected (parte B)**: a reabertura prossegue (FR-005) e a Decisao
   registrada na execucao nova contem recomendacao, escolha e a **divergencia**
   entre as duas (FR-006).
5. Repetir com descricao claramente aderente ⇒ recomendacao `reabrir`, e em
   ambos os casos a execucao **aguardou** confirmacao (SC-005).

---

## Scenario 9: Spec arquivada volta ao caminho ativo (FR-013, P1/AS-1.3)

1. Escolher feature cujo `docs/specs/<short>/` **nao** existe e cujo
   `docs/specs/_archived/.../<short>/` existe (caso mais comum no repo).
2. Registrar `sha256` recursivo do diretorio arquivado.
3. `/feature-00c --reopen <short> "<incremento>"`, confirmar.
4. **Expected**:
   - `docs/specs/<short>/spec.md` existe de novo;
   - o diretorio sob `_archived/` esta **intacto** (`sha256` recursivo bate) —
     nao foi movido, renomeado nem removido;
   - o operador foi informado de que a restauracao ocorreu e de qual origem;
   - repetir com a forma de nome sem data e com a forma `<YYYY-MM-DD>-<short>`
     (ambas existem: dos 40 diretorios em `_archived/`, 18 sao datados e 22 nao);
   - a resolucao ignora entradas que nao sao diretorio (ha um
     `review-features-report.md` solto em `_archived/`).
5. Variante: com `docs/specs/<short>/spec.md` **ja presente e editado a mao** ⇒
   restauracao **nao sobrescreve**; o incremento se aplica sobre o disco.

---

## Scenario 10: Incremento entra como delta, nunca como spec paralela (FR-014)

1. Apos o Scenario 1, deixar a pipeline gerar o incremento na spec.
2. **Expected**:
   - `docs/specs/<short>/spec.md` ganhou secao `## Delta Requirements` com
     `### Capability: <slug>` e ao menos um bloco `#### ADDED`;
   - **nenhuma** spec paralela foi criada para a feature;
   - `delta-gate.sh docs/specs/<short>/spec.md` sai `0` e imprime
     `RESULT|...|delta=present|errors=0|warnings=0`.

---

## Scenario 11: Backlog preserva o round anterior (FR-015, P3/AS-3.3)

1. Feature reaberta cujo `tasks.md` tem fases concluidas marcadas `[x]`.
2. Rodar a pipeline ate gerar trabalho novo.
3. **Expected**:
   - fases anteriores intactas, **incluindo** as marcacoes `[x]`;
   - trabalho novo aparece como **fase apendada** ao final;
   - nenhuma fase anterior foi renumerada ou reescrita.

---

## Scenario 12: Rotacao interrompida sai por comando (FR-011, SC-006, error case)

Tres injecoes de falha, cada uma partindo de um state-dir limpo:

| # | Interromper apos | Recuperacao esperada |
|---|------------------|----------------------|
| a | escrita do journal, antes de mover | roll-back — state-dir volta ao original |
| b | mover parte dos arquivos (staging incompleto) | roll-back — arquivos devolvidos a raiz |
| c | staging completo, antes do rename final | roll-forward — `rounds/<label>/` consumado |

1. Injetar a falha.
2. Rodar `"$RS"/state-rounds.sh recover --state-dir <SD>` **uma unica vez**.
3. **Expected**:
   - exit `0` e linha `RECOVER|<none\|forward\|rollback>|<label>`;
   - estado coerente: **ou** round consumado **ou** state-dir original — nunca
     hibrido;
   - `rounds/.rotate-journal` e o staging nao existem mais;
   - **nenhuma** edicao manual de arquivo foi necessaria (SC-006);
   - `recover` rodado de novo ⇒ no-op, exit `0` (idempotente).

---

## Scenario 13: Concorrencia entre sessoes (FR-012, Edge Case)

1. Sessao A inicia `--reopen` e para logo apos adquirir o lock.
2. Sessao B tenta `--reopen` do **mesmo** short-name.
3. **Expected**:
   - B sai `3` (lock ocupado) sem tocar em nada;
   - a rotacao de A permanece integra;
   - o lock de A cobre a rotacao **inteira**, sendo liberado so no Cleanup
     (FR-012).

---

## Scenario 14: Indice de conhecimento conta cada round uma vez (P3, SC-003)

1. Feature com `r01` preservado + execucao viva, nos **dois** backends.
2. `cstk recall --reindex --states-root <raiz de teste>`.
3. **Expected**:
   - exatamente **2** linhas de `executions` para `(project, feature)` — uma por
     round, zero duplicatas;
   - `dec-001` de `r01` e `dec-001` da execucao viva **coexistem** (a
     proveniencia por round evitou a colisao de chave);
   - **nenhum** round aparece como execucao ativa;
   - round em `state.db` foi ingerido (hoje seria invisivel — Decision 6);
   - `--reindex` rodado 2x ⇒ contagens identicas (idempotencia);
   - state-dir sem `rounds/` ⇒ resultado identico ao de antes da mudanca
     (nao-regressao).

---

## Scenario 15: Nenhuma opcao termina em aborto do proprio fluxo (SC-007, FR-016)

1. Feature com estado terminal e spec **arquivada** — o caso que hoje nao
   dispara o item 6 do pre-flight e morre no `init`.
2. `/feature-00c <short> "<descricao>"` (abertura **normal**, sem `--reopen`).
3. **Expected**:
   - o pre-flight **detecta o state-dir terminal** (nao apenas `spec.md`) e
     apresenta as opcoes (FR-017);
   - a mensagem cita `/feature-00c --reopen`, `/feature-00c-resume`,
     `/feature-00c-abort` — nunca `/agente-00c-*`;
   - escolher a opcao "retomar a partir da spec existente" leva a uma **execucao
     de fato** (FR-016), nao a um aborto;
   - percorrer todas as opcoes oferecidas em todo o fluxo: nenhuma termina em
     aborto do fluxo que a ofereceu (SC-007).

---

## Scenario 16: Politica de commit herdada sem prompt (FR-022)

1. Round anterior com `.atomic_commit_enabled = true`.
2. `/feature-00c --reopen <short> "<incremento>"`.
3. **Expected**: nenhuma pergunta sobre atomic-commit; execucao nova com
   `.atomic_commit_enabled = true`.
4. Repetir com round anterior **sem** o campo registrado.
5. **Expected**: execucao nova com `false` (default seguro).

---

## Scenario 17: Aviso de trabalho pendente cita a fonte (FR-021, Principio VI)

1. Round anterior com branch associada **nao** mesclada na default.
2. `/feature-00c --reopen <short> "<incremento>"`.
3. **Expected**:
   - o parecer avisa do trabalho pendente identificando branch (e PR, se `gh`
     respondeu) e **cita o comando** que produziu cada afirmacao;
   - o aviso **nao bloqueia** — confirmando, a reabertura prossegue (FR-021).
4. Repetir com `gh` ausente do `PATH` ou nao autenticado.
5. **Expected**: o parecer reporta **"nao verificado"** para o status de PR —
   jamais "nao ha PR aberto". Ausencia de verificacao nunca vira afirmacao de
   ausencia (Principio VI, I-P1).

---

## Scenario 18: Conformidade POSIX e cobertura de teste (Principio II + regra do repo)

1. `shellcheck -s sh plugins/cstk/skills/agente-00c-runtime/scripts/state-rounds.sh`
2. `./tests/run.sh --check-coverage`
3. `./tests/run.sh state-rounds` e `./tests/run.sh recall`
4. **Expected**:
   - shellcheck sem erro; nenhum bashismo (`[[ ]]`, arrays, `local`, `<<<`,
     `function`, `$'...'`);
   - `--check-coverage` sai `0` — `tests/test_state-rounds.sh` existe e cobre o
     script novo (orfao faria sair `1`);
   - suite verde nas duas plataformas.

---

## Scenario 19: Linhagem com backend misto e comportamento intencional (FR-010, Decision 14)

Cobre a resolucao do "Decision 14 (FR-010)" registrada no `research.md`:
a execucao nova **nao herda** o backend do round anterior nem existe flag
`--backend` — ela usa a config global corrente, exatamente como qualquer
`init` em state-dir limpo. Dois sub-cenarios, nas duas direcoes.

### 19a — round `state.json` + execucao nova `state.db` (caso comum)

1. Preparar state-dir com config global `state_backend=sqlite`
   (`cstk state enable-sqlite`) e uma execucao anterior `concluida`
   persistida em `state.json` (perfil das 21 execucoes legadas do repo de
   referencia).
2. `/feature-00c --reopen <short> "<incremento>"`, confirmar `reabrir`.
3. **Expected**:
   - `<SD>/rounds/r01/state.json` preservado (round permanece no formato em
     que foi gravado — nunca convertido);
   - `<SD>/state.db` novo existe (backend resolvido pela config global, nao
     pelo round); `<SD>/state.json` novo **nao** existe;
   - `state-rw.sh get --field '.previous_round'` (lido via backend `sqlite`
     da execucao nova) devolve `round=r01`, `status=concluida` — a leitura
     do ponteiro **atravessa** o backend do round sem tratamento especial
     (paridade v6.3);
   - nenhum erro, nenhum aviso de "backend divergente" — a divergencia e
     silenciosamente correta, nao uma condicao de excecao.

### 19b — round `state.db` + execucao nova `state.json` (inverso)

1. Preparar state-dir com config global `state_backend=json` e uma execucao
   anterior `concluida` persistida em `state.db` (uma das 5 execucoes SQLite
   do repo de referencia).
2. `/feature-00c --reopen <short> "<incremento>"`, confirmar `reabrir`.
3. **Expected**: espelho do 19a — `<SD>/rounds/r01/state.db` preservado
   intacto, `<SD>/state.json` novo criado pela config global, `.previous_round`
   legivel normalmente apontando para `r01`.

**Nao-objetivo explicito**: nenhum destes sub-cenarios espera migracao,
conversao ou aviso de incompatibilidade — a mistura de backends dentro da
mesma linhagem de feature e o comportamento default esperado desde que a
config global e independente do historico de rounds (dec-022).

---

## Convencoes de Borda

**N/A — single-layer.** Nao ha cenario "Roundtrip End-to-End": esta feature nao
atravessa fronteira backend↔frontend. Justificativa completa em
`plan.md` §Convencoes de Borda.
