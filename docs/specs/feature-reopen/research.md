# Research: feature-reopen

Documento do Phase 0 do `/plan`. Resolve os unknowns tecnicos do Technical
Context antes do design.

> **Aterramento (Constitution Principio VI)**: cada Decision abaixo cita a
> fonte lida no repo em 2026-08-11. Contratos ainda inexistentes que esta
> feature projeta estao marcados `[PROPOSTA — a validar na implementacao]`.
> Nenhuma flag, exit code ou mensagem foi suposta.

---

## Decision 1: Atomicidade observavel da rotacao (FR-011)

**Decision**: rotacao em 3 tempos com *journal* + diretorio de estagio, cujo
ponto de commit e um unico `mv` de diretorio:

1. `rounds/.rotate-journal` (arquivo texto) grava a intencao ANTES de qualquer
   movimento: label do round, backend, lista de arquivos a mover, timestamp.
2. Arquivos transacionais sao movidos para `rounds/.rNN.staging/`.
3. **Ponto de commit**: `mv rounds/.rNN.staging rounds/rNN` — rename unico de
   diretorio, dentro do mesmo filesystem, portanto atomico no nivel do VFS.
   O journal so e removido depois.

Uma interrupcao em qualquer ponto e resolvida por `state-rounds.sh recover`
(roll-forward se o estagio esta completo; roll-back devolvendo os arquivos a
raiz do state-dir se nao esta). Nenhum caminho exige edicao manual (SC-006).

**Rationale**: nao existe transacao multi-arquivo em POSIX. O unico primitivo
atomico disponivel e `rename(2)` dentro do mesmo filesystem — por isso o commit
e deslocado para o rename do diretorio de estagio, e nao para os `mv` dos
arquivos individuais. O journal e o que torna a recuperacao *deterministica*:
sem ele, `recover` teria de adivinhar a intencao a partir do que sobrou no
disco. Os rounds ficam no mesmo state-dir, logo mesmo filesystem — a premissa
do rename atomico se sustenta.

**Alternatives considered**:
- *Copiar e depois apagar*: dobra o uso de disco e cria janela em que o estado
  existe em dois lugares (viola "estado terminal imutavel" se a copia diverge).
- *`mv` direto de cada arquivo sem estagio*: interrupcao no meio deixa o
  state-dir com estado parcial e sem registro da intencao — exatamente o limbo
  que FR-011 proibe.
- *Symlink/hardlink*: quebra SC-002 (preservacao byte a byte independente) e
  nao e uniforme entre plataformas.

---

## Decision 2: Sidecars `-wal` / `-shm` do SQLite (FR-010, GOTCHA v6.4.0)

**Decision**: antes de mover, executar `PRAGMA wal_checkpoint(TRUNCATE);` sobre
`state.db`; em seguida mover **somente `state.db`** para o round e remover
`state.db-wal` / `state.db-shm` residuais do state-dir. Round preservado contem
exatamente um arquivo de estado, em qualquer plataforma.

**Rationale**: os sidecars sao *derivados e volateis*, nao parte do dado. Apos
checkpoint TRUNCATE, todo o conteudo do WAL esta dentro de `state.db` e o WAL
fica vazio — mover so o `.db` nao perde nada. O precedente do checkpoint existe
no runtime: `state-db-migrate.sh:324` usa `PRAGMA wal_checkpoint(TRUNCATE);`
sobre a DB temporaria de migracao. O WAL e ligado uma vez em
`state-db-schema.sh:73` (`PRAGMA journal_mode=WAL;`), e `_state-db.sh:150-151`
faz `chmod 600` best-effort nos dois sidecars.

Isto **elimina na raiz** a divergencia de plataforma que quebrou a release
v6.4.0 (sidecars persistem no macOS e nao no Ubuntu): se o round nunca contem
sidecar, nao ha nada sobre o que as duas plataformas possam divergir. A
existencia de cada sidecar e testada antes de remover — ausencia nao e erro.

Como a rotacao so ocorre com a execucao em estado **terminal** e com o lock
detido (FR-003 + FR-012), nao ha escritor concorrente e o checkpoint e seguro.

### Verificacao do checkpoint NAO pode depender do exit code (achado do gate de seguranca)

`PRAGMA wal_checkpoint(TRUNCATE);` **sai `0` mesmo quando nao consegue
checkpointar**. Verificado empiricamente nesta onda: a saida e sempre a tripla
`busy|log|checkpointed` e o exit code observado foi `0` em todos os casos
testados:

```
$ sqlite3 t.db "PRAGMA wal_checkpoint(TRUNCATE);"
0|0|0
$ echo $?
0
```

O sinal de falha esta na **coluna 1 (`busy`)**, nao no exit code. Um checkpoint
com `busy != 0` deixa conteudo no WAL — e o passo (g), que apaga
`state.db-wal`, transformaria isso em **perda silenciosa de transacoes ja
commitadas**. O precedente citado (`state-db-migrate.sh:324`) inclusive termina
em `|| :`, o que descartaria qualquer erro.

Portanto o contrato de `rotate` MUST:

1. capturar a saida do PRAGMA e exigir **`busy == 0`** (coluna 1); senao exit `1`
   sem mover nada;
2. **nunca** aplicar `|| :` ao checkpoint;
3. antes de apagar os sidecars, exigir que `state.db-wal` esteja **ausente ou
   com 0 bytes** — checagem independente do PRAGMA;
4. rodar `PRAGMA integrity_check;` na copia **ja dentro do round**, apos o
   commit, confirmando que o arquivo preservado abre integro.

> Honestidade sobre o alcance da verificacao: foi observado que o exit code e
> sempre `0` e que o status vem na tripla. **Nao** foi reproduzido em laboratorio
> um caso com `busy != 0` — a mitigacao acima decorre da semantica documentada
> das colunas, nao de uma perda de dados observada. Nenhuma afirmacao de perda
> real esta sendo feita aqui.

**Alternatives considered**:
- *Preservar os 3 arquivos no round*: reintroduz exatamente a assimetria macOS
  vs Ubuntu, e `-shm` e memoria compartilhada reconstruivel — preserva-lo nao
  agrega informacao.
- *Ignorar os sidecars e mover so o `.db` sem checkpoint*: perda de dados real
  se o WAL tiver commits nao integrados.

---

## Decision 3: Numeracao dos rounds (FR-009)

**Decision**: label `r%02d` (`r01`, `r02`, ... `r99`), derivado por varredura de
`rounds/r??` e escolha do maior sucessor. Largura fixa de 2 digitos; ao passar
de `r99`, a largura cresce naturalmente (`r100`) e a ordenacao lexicografica
deixa de coincidir com a numerica — condicao documentada como limite conhecido,
nao tratada em codigo.

**Rationale**: zero-padding de largura fixa foi fixado no clarify justamente
para permitir `ls`/glob ordenados sem parsing numerico em POSIX sh. Duas casas
cobrem com folga o uso real (o repo tem 41 features arquivadas e nenhuma foi
reaberta ate hoje); assumir 100+ reaberturas da MESMA feature seria projetar
para um cenario nao observado.

**Alternatives considered**:
- *Timestamp como label* (`r2026-08-11T…`): ordena bem, mas perde a nocao de
  "rodada N" que a spec usa como identidade do Round (Key Entities), e polui o
  ponteiro `.previous_round`.
- *Sem padding* (`r1`, `r2`, … `r10`): `r10` ordena antes de `r2` — o problema
  exato que o clarify decidiu evitar.

---

## Decision 4: Persistencia de `.previous_round` (FR-008)

**Decision**: campo de topo `.previous_round` no estado transacional da execucao
nova, gravado via `state-rw.sh set --field '.previous_round' --value '<json>'`.
**Nao exige migracao de schema em nenhum dos dois backends.**

**Rationale — verificado empiricamente nesta onda**, nao inferido:

```
$ state-rw.sh set --state-dir <tmp> --field '.previous_round' \
    --value '{"round":"r01","path":"rounds/r01"}'
state-rw: set: .previous_round atualizado (backend sqlite)
$ state-rw.sh get --state-dir <tmp> --field '.previous_round'
{ "round": "r01", "path": "rounds/r01" }
$ sqlite3 <tmp>/state.db "SELECT extra_fields FROM execution;"
{"suggestions":[...],"previous_round":{...}}
```

O mecanismo e a coluna catch-all `execution.extra_fields TEXT -- JSON object`
(`references/state-db-schema.sql:65`). Em `_sr_db_set` (`_state-rw-db.sh`
L737-755) um campo de topo simples que nao casa coluna dedicada cai no ramo
`*)`, que faz read-modify-write de `extra_fields`; no `read` (L349-356) o
conteudo e remontado no topo do documento via
`((.extra_fields // {}) | del(.cache_metrics)) as $ext | (del(.extra_fields)) as $core | ($ext + $core)`.
No backend JSON o campo e apenas mais uma chave do objeto.

**Restricao herdada**: paths ANINHADOS sao rejeitados sob SQLite com exit `1`
(`set: campo nao suportado sob backend SQLite (path aninhado nao modelado)`).
Logo o objeto e sempre escrito **inteiro** em `.previous_round`; nunca via
`.previous_round.round`.

**Alternatives considered**:
- *Arquivo auxiliar `previous-round.txt`*: rejeitado pelo clarify (quebra a
  paridade entre backends e sai do estado transacional).
- *Coluna dedicada em `execution`*: exigiria migracao de schema e bump de
  `schema_version` (hoje literal `"1.0.0"`, imutavel apos init) para um dado que
  o catch-all ja cobre.

---

## Decision 5: Rounds vs. reconstrucao do indice de conhecimento (FR-018, SC-003)

**Decision**: **nao** podar `rounds/` do `--reindex`. Rounds DEVEM ser
ingeridos (SC-003 exige contar cada round exatamente uma vez), porem com
**namespace de proveniencia por round** para eliminar colisao de chave.
`[PROPOSTA — a validar na implementacao]`

O problema real, medido na fonte (`cli/lib/recall.sh:3189-3193`):

```sh
find "$_rx_states_root" -type f -name 'state.json' \
    \( -path '*/.claude/feature-00c-state/*/state.json' \
       -o -path '*/.claude/agente-00c-state/state.json' \) 2>/dev/null
```

Em `find -path`, `*` **casa `/`** e nao ha `-maxdepth`. Logo
`<state-dir>/rounds/r01/state.json` JA seria varrido hoje. Isso, por si, nao e
o defeito — o defeito e a **chave de idempotencia**: `ON CONFLICT(project,
feature, wave, source_id)` (`:1247`). A linha de `executions` usa `wave='-'` e
`source_id=execution_id`, e `execution_id` no modo feature e `feat-<short>-<ts>`
— distinto por round, logo **nao colide**. Mas decisoes, bloqueios e skills usam
`wave=onda-NNN` + `source_id=dec-NNN`, e **ambos os rounds comecam em
`onda-001`/`dec-001`**: o round preservado sobrescreveria as linhas da execucao
viva (e vice-versa), corrompendo o historico das duas.

Portanto a ingestao de um estado sob `rounds/<label>/` MUST carregar o label na
proveniencia: linha de `executions` com `wave=<label>` (em vez de `-`) e demais
linhas com `wave=<label>/onda-NNN`. O campo `feature` permanece o `short_name`
— as duas rodadas sao a MESMA feature, e e isso que faz "execucoes contadas =
numero de rounds" ser verdade sem duplicata.

Quanto a "nunca tratado como execucao ativa": ja e satisfeito pela normalizacao
existente (`:1194-1195`), que mapeia `status == "concluida"` para
`current_stage = "concluido"`. Round terminal nunca aparece ativo. Round
`abortada` preserva o proprio status (FR-020).

**Outros leitores de estado nao precisam de mudanca** — verificado: os hooks e
helpers (`pretooluse-bash-guard.sh` `_pbg_scope_has_state`,
`posttooluse-tool-call-tick.sh`, `posttooluse-agent-usage.sh`,
`posttooluse-loose-usage.sh`, `mcp-session.sh`, `guard-hooks-status.sh`) usam
**glob de shell** (`for d in "$froot"/*/`), e glob de shell **nao casa `/`** —
alcanca exatamente um nivel. `rounds/r01/` esta dois niveis abaixo e e
invisivel para eles. O `find -path` do `recall.sh` e o unico leitor afetado.

**Alternatives considered**:
- *`-prune` em `*/rounds`*: mataria SC-003 — rounds deixariam de ser contados.
- *Mover `rounds/` para fora do state-dir*: contraria a restricao travada
  (`rounds/r<N>/` sob o state-dir) e quebra a co-localizacao que torna o rename
  atomico da Decision 1 possivel (mesmo filesystem).
- *Namespacar por `feature` (`<short>#r01`)*: quebraria toda consulta por
  `--project P` + feature e faria a mesma feature aparecer como N features.

---

## Decision 6: Paridade de backend no `--reindex` (FR-010, SC-003, SC-004)

**Decision**: acrescentar ao `--reindex` uma segunda varredura para `state.db`,
roteando para `recall_ingest_state_db` — a mesma funcao que o `--ingest` ja usa.
`[PROPOSTA — a validar na implementacao]`

**Rationale**: hoje `recall_mode_reindex` (`cli/lib/recall.sh:3131-3227`) tem
exatamente um `find` de estado, e ele e `-name 'state.json'`. **Nao existe
nenhum `find` para `state.db` no modo reindex.** Consequencia ja vigente
(anterior a esta feature): toda execucao com backend SQLite e invisivel ao
`--reindex`. O caminho de ingestao existe e e usado pelo `--ingest`, que
despacha por presenca de arquivo (`:2773-2777`):

```sh
if [ -r "$_ing_state_dir/state.db" ]; then
  recall_ingest_state_db "$_ing_state_dir/state.db" "$_ing_state_dir" "$_ing_db"
else
  recall_ingest_state_json "$_ing_state_dir/state.json" "$_ing_db"
fi
```

Sem essa correcao, SC-003 falha para rounds SQLite e SC-004 nao se sustenta
("funciona para as 26 execucoes, independentemente de como cada uma foi
persistida" — 5 das 26 concluidas usam `state.db`; a contagem foi conferida no
disco nesta onda: 27 state-dirs, 21 com `state.json`, 6 com `state.db`, sendo o
6o a propria `feature-reopen` em andamento).

**Precedencia quando os dois arquivos coexistem**: `state.db` vence, espelhando
a regra ja implementada no `--ingest`. Evita ingerir duas vezes o mesmo round.

**Alternatives considered**:
- *Deixar a lacuna e cobrir so JSON*: viola FR-010 explicitamente (paridade de
  comportamento observavel entre backends) e SC-004.
- *Migrar todos os rounds para JSON na rotacao*: converteria estado terminal —
  proibido por FR-007 (preservacao integra, sem alteracao de campo).

---

## Decision 7: "Recusar sem escrever nada no disco" vs. lock (FR-002, FR-012)

**Decision**: ordem estrita de validacao — **toda recusa acontece antes de
qualquer escrita**, inclusive antes do `acquire` do lock:

```
1. state-dir existe E contem estado transacional?  -> nao: RECUSA (FR-002)
2. state-lock.sh acquire                            (primeira escrita possivel)
3. state-lock.sh check-execution-busy                -> exit 3: RECUSA (FR-003)
4. triagem + parecer + bloqueio humano               (nenhuma escrita ainda)
5. rotacao + init                                    (escrita de fato)
```

**Rationale**: dois helpers escrevem no disco antes do que se imaginaria:

- `state-lock.sh acquire` cria o proprio state-dir, `.lock/`, `.lock/owner` e
  semeia `.gitignore` com `*`. Adquirir o lock para so entao descobrir que a
  feature nunca existiu deixaria um state-dir fantasma — exatamente o que
  FR-002 proibe.
- `state-rw.sh init` chama `_sr_ensure_state_dir` na L388, **antes** das guardas
  de estado pre-existente das L411-418. Ou seja: um `init` recusado (exit `1`,
  `init: state.json ja existe em $_sd. Use /agente-00c-abort ou
  /agente-00c-resume.`) ainda assim cria state-dir + `state-history/` +
  `.gitignore`. O modo de reabertura nunca deve depender de que o `init` recuse
  — ele valida antes e so chama `init` sobre um state-dir ja rotacionado (logo
  sem `state.json`/`state.db` na raiz), onde `init` passa normalmente e **nao e
  necessario nenhum `--force`** (que, aliado, nao existe: `init` nao tem
  `--force` nem `--overwrite`).

Tambem por isso o `mkdir -p "$AGENTE_00C_STATE_DIR/backups"` que o
`feature-00c.md` faz na L206 **nao pode** ser executado no caminho de reabertura
antes da confirmacao da triagem.

**TOCTOU residual**: entre o passo 1 e o passo 2 outra sessao poderia agir.
Mitigacao: apos adquirir o lock, **re-verificar** a pre-condicao do passo 1
antes de rotacionar. Janela remanescente e aceitavel e documentada.

**Alternatives considered**:
- *Adquirir o lock primeiro e limpar o state-dir na recusa*: "limpar" e remover
  diretorio com base em heuristica — risco assimetrico (apagar estado alheio)
  muito maior que o beneficio.
- *Propor `--force` em `state-rw.sh init`*: desnecessario apos a rotacao, e
  ampliaria a superficie de um comando que hoje falha seguro.

---

## Decision 8: Restauracao de spec arquivada (FR-013)

**Decision**: `[PROPOSTA — a validar na implementacao]` copiar (nunca mover) a
arvore do diretorio arquivado para `docs/specs/<short>/`, deixando
`docs/specs/_archived/...` intacto, e informar o operador do que foi restaurado.

Resolucao do diretorio de origem, nesta ordem:
1. `docs/specs/_archived/<short>/` (forma sem data);
2. `docs/specs/_archived/<YYYY-MM-DD>-<short>/` (forma com data) — havendo mais
   de um, vence o de maior prefixo de data (ISO ordena lexicograficamente =
   cronologicamente);
3. nenhum: nao ha o que restaurar; segue sem restauracao.

Colisao: se `docs/specs/<short>/` ja existe e nao esta vazio, **nao sobrescreve**
— o disco vence (Edge Case "spec ativa editada a mao entre o fechamento e a
reabertura: o incremento se aplica sobre o que esta no disco").

**Rationale**: **nao existe hoje nenhum caminho de desarquivamento** — verificado
por varredura: nenhum script ou comando restaura de `_archived/`, e
`review-features/SKILL.md:64` determina que diretorios ja arquivados
"permanecem inalterados — NAO renomear nem mover conteudo ja arquivado". Copiar
respeita essa regra ao pe da letra e satisfaz FR-013 ("MUST preservar o
diretorio de arquivo do round anterior onde ele esta").

As duas formas de nome sao ambas reais no repo, contadas nesta onda: **40
diretorios** sob `_archived/` — 18 com prefixo de data e 22 sem. (A 41a entrada
do diretorio nao e uma spec arquivada e sim o arquivo
`docs/specs/_archived/review-features-report.md`; a resolucao MUST considerar
apenas diretorios, `-type d`.) Tratar so uma das formas quebraria metade dos
casos. Um diretorio arquivado tipico contem `spec.md`, `plan.md`,
`tasks.md`, `research.md`, `data-model.md`, `quickstart.md`, `contracts/`,
`checklists/` — a arvore inteira e copiada porque FR-015 (continuidade do
backlog) depende de `tasks.md` e o delta depende de `spec.md`.

**Nao confundir com o corpus de specs vivas**: `delta-merge.sh` escreve em
`docs/specs/current/` (8 arquivos hoje) e **nao** arquiva nada — o `mv` para
`_archived/` e passo manual descrito em prosa (`review-features/SKILL.md:43-68`).
A restauracao aqui e do diretorio da feature, nao do corpus.

**Alternatives considered**:
- *Mover de volta*: viola FR-013 e a regra de imutabilidade do arquivo.
- *Symlink*: quebra a edicao do delta na spec ativa e confunde o `delta-gate`.

---

## Decision 9: Deteccao de trabalho pendente e o confinamento do `gh` (FR-021)

**Decision**: implementar a sonda de trabalho pendente **dentro de
`commit-mode.sh`**, como subcomando novo, em vez de criar um script novo que
invoque `gh`. `[PROPOSTA — a validar na implementacao]`

**Rationale**: o carve-out de dependencia opcional da constitution (amendment
1.1.0) exige, na condicao (b), que "grep pelo nome do executavel localize todas
as mencoes em **um unico arquivo fonte**".

> **CORRECAO DE PREMISSA (achado do gate de veracidade — Principio VI).** A
> versao inicial desta Decision afirmava que "`gh` esta hoje confinado a
> `commit-mode.sh`". **Isso e falso**, e a afirmacao foi retirada. Medicao
> direta nesta onda mostra `gh` **invocado de fato** em mais de um arquivo:
>
> | Arquivo | Evidencia |
> |---------|-----------|
> | `scripts/commit-mode.sh` | `gh pr view --json url,state`, `gh auth status` |
> | `scripts/issue.sh` | `command -v gh` (L92-93), `gh label create` (L241), `gh issue list` (L250), `gh issue create` (L333+) |
> | `cli/lib/session.sh` | invocacao de `gh` para abertura de PR |
> | `scripts/bash-guard.sh`, `scripts/sanitize.sh` | mencoes em pattern-match/allowlist, **nao** invocacao |
>
> Consequencia honesta: a condicao (b) do carve-out 1.1.0 **ja nao esta
> satisfeita para `gh`** no codebase atual — situacao **anterior e alheia** a
> esta feature. Esta feature nao pode "preservar" um confinamento que nao
> existe, e tampouco deve fingir que existe para se declarar conforme.

**Justificativa que resta de pe** (independente da premissa corrigida): reusar
`commit-mode.sh` continua sendo a melhor escolha tecnica, porque e o arquivo que
ja concentra os helpers de `git`/`gh` de que a sonda precisa — resolucao de
branch default e consulta de PR — evitando uma terceira copia dessa logica.
O que **muda** e o status constitucional: colocar a sonda ali **nao torna** a
feature conforme a condicao (b); apenas **nao piora** um desvio pre-existente.
A regularizacao do `gh` (amendment declarando-o dep opcional multi-arquivo, ou
consolidacao num unico adapter) e **divida do toolkit**, fora do escopo desta
feature, e esta registrada como bloqueio humano para decisao do operador.

O mecanismo reusa o que ja existe e esta lido na fonte:
- branch default: `git -C "$PAP" symbolic-ref refs/remotes/origin/HEAD` filtrado
  por `sed 's@^refs/remotes/origin/@@'`; sem remote, `main` **e** `master` sao
  tratados como default;
- PR aberto: `gh pr view "$branch" --json url,state`, precedido de
  `command -v gh` e `gh auth status`, com skip nao-fatal (`skipped-gh-missing`,
  `skipped-gh-unauth`).

Isso satisfaz literalmente a exigencia de FR-021 de "citar a fonte checada":
cada afirmacao do aviso nomeia o comando que a produziu, e a ausencia de `gh`
vira "nao verificado" — **nunca** "nao ha PR aberto". Afirmar ausencia a partir
de uma verificacao que nao rodou seria fabricacao (Principio VI).

**Alternatives considered**:
- *Script novo `pending-work.sh` usando `gh`*: viola condicao (b) do carve-out.
- *Emendar a constitution para permitir `gh` em 2 arquivos*: custo de governanca
  desproporcional a um aviso informativo que nao bloqueia.
- *Assumir "sem PR" quando `gh` falta*: viola Principio VI.

---

## Decision 10: Onde vive a triagem (FR-004, FR-005, FR-006)

**Decision**: a comparacao pedido-vs-spec e feita pelo **command/orquestrador**
(camada de linguagem), nao por script POSIX. O runtime fornece apenas insumo
factual (existencia e caminho da spec, status e label do round anterior,
resultado da sonda de trabalho pendente); o parecer resultante e apresentado ao
operador como **bloqueio humano** via `bloqueios.sh register`, e a resposta vira
Decisao auditavel via `state-decisions.sh register`.

**Rationale**: julgar se um incremento "pertence" a uma spec e tarefa semantica.
Um script POSIX so poderia aproxima-la por sobreposicao de palavras — e um
numero desses viraria, na pratica, um score decidindo sozinho, que e exatamente
o que a restricao travada 3 proibe ("triagem advisory com bloqueio humano; nunca
decidir por score"). Mantendo a comparacao na camada de linguagem e o veredito
como bloqueio, o sistema **recomenda** e o operador decide (FR-005), inclusive
contra a recomendacao — e a divergencia fica registrada (FR-006).

**Ordem obrigatoria**: o parecer e emitido **antes de qualquer escrita em
disco** (FR-004, literal: "Antes de qualquer escrita em disco"). A Decisao que
registra parecer + escolha, porem, so pode ser gravada **depois** do `init` da
execucao nova — pois FR-006 exige que ela seja "decisao auditavel **da execucao
nova**", que ainda nao existe no momento do parecer. O parecer e portanto
carregado em memoria pelo fluxo e persistido logo apos o `init`.

**Alternatives considered**:
- *Score lexico automatico*: proibido pela restricao travada 3.
- *Registrar a Decisao no round anterior*: viola FR-007 (round imutavel).

---

## Decision 11: Continuidade do backlog (FR-015)

**Decision**: `tasks.md` restaurado/existente e preservado como esta; o trabalho
novo entra como **fase nova apendada** ao final, sem reescrever nem renumerar as
fases anteriores, e sem alterar marcacoes `[x]` ja concluidas.

**Rationale**: e o mesmo padrao ja praticado no toolkit pela skill `converge`,
que apenda uma fase de convergencia ao `tasks.md` existente em vez de
regenera-lo. Reusar o padrao evita inventar um segundo mecanismo de acrescimo e
mantem `create-tasks` idempotente sobre backlog pre-existente.

**Alternatives considered**:
- *Regenerar `tasks.md` do zero a partir da spec com delta*: perderia a marcacao
  de conclusao do round anterior — violacao direta de FR-015.

---

## Decision 12: Heranca da politica de commit automatico (FR-022)

**Decision**: ler `.atomic_commit_enabled` do estado terminal **antes** da
rotacao, e repassar o valor lido em `state-rw.sh init --atomic-commit
<true|false>`. Ausencia, leitura falha ou valor nao reconhecido ⇒ `false`.

**Rationale**: `init` ja aceita `--atomic-commit`, e a flag valida estritamente
o literal `true`/`false` (qualquer outra coisa: exit `2`,
`init: --atomic-commit aceita apenas 'true' ou 'false'`). O default seguro
`false` espelha o prompt interativo do `feature-00c.md` (L237-254), onde
qualquer entrada diferente de `s/S/y/Y/sim/yes` — inclusive Enter — desabilita.
FR-022 exige nao reapresentar a escolha ao operador; ler do round anterior e o
unico jeito de herdar sem perguntar.

**Alternatives considered**:
- *Reperguntar*: proibido literalmente por FR-022.
- *Herdar `true` por default na ausencia de registro*: contraria FR-022 ("a
  ausencia de registro MUST equivaler a politica desabilitada").

---

## Decision 14: Backend da execucao NOVA apos a rotacao (FR-010) — SEM heranca

**Decision**: a execucao nova **NAO herda** o backend do round anterior e **NAO
ganha flag nova**. Ela usa o **backend global corrente**, exatamente como
`state-rw.sh init` ja resolve hoje (via `state-backend.sh resolve`) para
qualquer `init` em state-dir limpo — a reabertura nao e um caso especial desse
mecanismo. Quando a config global diverge do backend do round preservado, a
linhagem da feature fica com rounds em backends diferentes. **Isso e
comportamento intencional**, nao um defeito a corrigir. Decisao do operador em
resposta a `block-001` (dec-022), score 3.

**Rationale**: a primeira redacao desta Decision tratou backend-misto-na-
linhagem como quebra de FR-010 e propos heranca via flag `--backend` nova ou
override implicito de config — ambas ampliariam o blast radius (flag nova em
`init` toca o **runtime**, exigindo `self-update` em vez de so `install`) por
um problema que, examinado de novo, nao existe:

- **FR-010** exige comportamento observavel **identico entre backends para a
  MESMA operacao de rotacao** (Scenario 1 vs Scenario 2) — nao exige que os
  ROUNDS de uma linhagem compartilhem formato de arquivo entre si. Nenhum FR
  desta feature amarra o backend da execucao nova ao do round anterior.
- **Desde v6.3 (`state-db-runtime-parity`)**, todos os leitores do runtime 00c
  (15+, incluindo `_state-read.sh`, `report.sh`, `state-rw.sh get`) sao
  **backend-agnosticos** — ler um round `state.json` seguido de outro
  `state.db` na mesma feature ja funciona sem tratamento especial, porque cada
  leitura resolve o backend do arquivo que tem na frente, nao de um estado
  global da feature.
- **Empiricamente, backend misto e o caso COMUM, nao o de canto**: das 26
  execucoes existentes no repo de referencia, 21 sao `state.json` e a config
  global corrente ja resolve `sqlite` — ou seja, a PRIMEIRA reabertura de
  qualquer uma dessas 21 features ja produziria round `json` + execucao nova
  `sqlite` mesmo com heranca ausente desde sempre. Herdar backend inverteria
  essa maioria, nao a preservaria.
- O paralelo com FR-022 (`atomic_commit_enabled` herdado) **nao se aplica
  aqui**: aquele campo e uma preferencia comportamental do operador sem
  equivalente em config global; backend de persistencia **ja tem** uma fonte
  de verdade global (`cstk state enable-sqlite` / `state_backend=`) que a
  reabertura deve respeitar como qualquer outro `init`, nao substituir.

**Mecanismo**: nenhum novo. `state-rw.sh init` continua resolvendo o backend
exatamente como faz hoje (linha ~400, `state-backend.sh resolve`), sem
distinguir reabertura de abertura normal. Confirmado empiricamente:
`grep -c -- "--backend" state-rw.sh` ⇒ `0` (flag nunca existiu). Esta feature
nao adiciona esse grep como zero-a-preservar; ela **fecha** a lacuna deixando
explicito que a ausencia e deliberada.

**Alternatives considered**:
- *Herdar o backend do round anterior* (redacao original desta Decision):
  rejeitada — exigiria flag nova em `init` (amplia o runtime, exige
  `self-update`) ou um override implicito de config por invocacao, por um
  ganho que os leitores backend-agnosticos da v6.3 ja tornam desnecessario.
- *Forcar sempre `sqlite`*: converteria silenciosamente projetos que
  deliberadamente usam JSON.
- *Bloquear a reabertura quando config global != backend do round*: transformaria
  um detalhe interno em erro para o operador, sem ganho.

## Decision 13: Superficie de invocacao do modo de reabertura (FR-001, FR-019)

**Decision**: `[PROPOSTA — a validar na implementacao]` flag `--reopen` no
proprio `/feature-00c`, e **nao** um command novo:

```
/feature-00c --reopen <short-name> "<descricao do incremento>"
```

O pre-flight existente (itens 1..8 do `feature-00c.md`) e reaproveitado
integralmente; o modo de reabertura se insere como ramo entre os itens 6 e 7.
`/agente-00c` nao e tocado (FR-019).

**Rationale**: a reabertura compartilha praticamente todo o pre-flight com a
abertura normal (path-guard, sanitizacao, briefing, constitution, coexistencia,
lock). Um command separado duplicaria os 8 itens e criaria duas copias para
manter em sincronia. Alem disso FR-016/FR-017 exigem consertar a mensagem e a
opcao (a) **dentro** do item 6 atual — que so existe nesse arquivo.

**Alternatives considered**:
- *`/feature-00c-reopen` dedicado*: duplicacao do pre-flight; o toolkit ja tem 6
  commands 00c e um setimo aumentaria a superficie sem ganho.
- *Detectar reabertura implicitamente* (mesmo short-name com estado terminal,
  sem flag): torna destrutivo por default um comando que hoje falha seguro;
  contraria o espirito de FR-005 (confirmacao explicita).
