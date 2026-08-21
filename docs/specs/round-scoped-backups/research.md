# Research: Escopar `backups/` na rotacao de round

**Feature**: `round-scoped-backups` | **Date**: 2026-08-21
**Spec**: [spec.md](./spec.md)

Todo comportamento afirmado abaixo foi lido no arquivo citado ou verificado
empiricamente nesta maquina (Constitution Principio VI). Onde ha verificacao
empirica, o comando e a saida literal estao transcritos.

---

## Decision 1 — Mover `backups/` DENTRO do mesmo staging da rotacao

**Decision**: `backups/` passa a ser um item do conjunto movido pelo `rotate`,
deslocado para `rounds/.<label>.staging/backups` na mesma fase `moving` que ja
move o estado transacional. O commit continua sendo o unico `mv --
rounds/.<label>.staging rounds/<label>` que ja existe hoje
(`plugins/cstk/skills/agente-00c-runtime/scripts/state-rounds.sh`, secao
`# h1. COMMIT: rename atomico`).

**Rationale**: a atomicidade exigida por FR-001/FR-008 ja e uma propriedade do
desenho atual — o staging acumula tudo e um unico `rename(2)` publica o round.
Anexar `backups/` ao staging herda essa atomicidade sem introduzir um segundo
ponto de commit. Nenhuma janela nova aparece: ou o rename aconteceu (round tem
estado + snapshots) ou nao aconteceu (raiz tem estado + snapshots), e o journal
cobre o meio-termo (Decision 5).

**Alternatives considered**:

- *Mover `backups/` numa operacao separada, depois do commit do round*:
  rejeitada — cria uma segunda janela nao-atomica exatamente onde FR-008 proibe
  ("nao pode deixar snapshots divididos entre a raiz do state-dir e o round
  preservado"). O journal atual so descreve UMA transacao.
- *Copiar (`cp -R`) em vez de mover, deixando a raiz intacta*: rejeitada — a
  execucao nova reinicia a numeracao em `wave-001.json` e sobrescreveria a copia
  remanescente na raiz; o defeito da issue #150 permaneceria, so que com
  duplicacao de disco.
- *Renomear snapshots por prefixo de round na propria raiz (ex.:
  `r01-wave-001.json`)*: rejeitada — muda a localizacao/nomeacao de escrita dos
  snapshots durante a execucao, violando FR-007 (escritores devem continuar
  gravando em `backups/wave-NNN.json`), e exigiria tocar os tres escritores
  citados na spec.
- *Diretorio irmao `rounds/<label>-backups/`*: rejeitada — quebra a premissa de
  que um round e uma unidade autocontida (`state-rounds.sh list` deriva backend e
  metadados de `rounds/<label>/`), e deixaria dois artefatos para o operador
  correlacionar manualmente.

---

## Decision 2 — Representacao no journal: entrada nomeada no conjunto fechado

**Decision**: `backups` entra no CSV `files=` do journal como mais um nome do
**conjunto fechado**, que passa de `{state.json, state.json.sha256, state.db}`
para `{state.json, state.json.sha256, state.db, backups}`. O tipo (arquivo vs
diretorio) e derivado do NOME, nao de sufixo ou metadado novo: `backups` e o
unico membro tratado como diretorio.

**Rationale**: a validacao J4 do `recover` (bloco `# J4: files fechado a
{state.json, state.json.sha256, state.db}` em `state-rounds.sh`) e uma guarda de
seguranca — impede que um journal adulterado faca o `recover` mover caminhos
arbitrarios (`../..`, paths absolutos) para dentro do state-dir. Manter o
conjunto FECHADO e ampliar por um nome literal preserva integralmente essa
guarda. Derivar o tipo por nome mantem o parser linha-a-linha existente
(`_sr_journal_field`) inalterado e nao adiciona campo novo ao journal.

**Alternatives considered**:

- *Marcar diretorios com sufixo `/` no CSV (`backups/`)*: rejeitada — exigiria
  strip do sufixo em cada uso e abriria o `case` de J4 para um padrao (`*/`) em
  vez de literais, enfraquecendo a guarda contra entradas forjadas.
- *Campo novo no journal (ex.: `dirs=backups`)*: rejeitada — dois campos
  paralelos precisariam ser mantidos em sincronia em `rotate`, `recover`
  (roll-forward e roll-back) e `_sr_staging_complete`; um unico CSV ordenado
  descreve a transacao inteira com menos estado.
- *Journal versionado (`version=2`) com compatibilidade retroativa*: rejeitada —
  um journal so existe DURANTE uma rotacao interrompida (o `rotate` recusa com
  exit `3` se ja houver um pendente, e o `recover` o remove ao final). Nao ha
  populacao de journals antigos persistidos a migrar.

---

## Decision 3 — Elegibilidade: so entra se existir E for nao-vazio

**Decision**: `backups` so e incluido no CSV `files=` (e portanto so e movido) se
o diretorio existir, nao for symlink (Decision 6) e contiver ao menos uma entrada.
Ausente ou vazio ⇒ nao entra no journal, nada e movido, o round nao ganha um
`backups/` vazio e o `rotate` conclui com exit `0`.

**Rationale**: e a leitura literal de FR-006 e do Acceptance Scenario de User
Story 3 ("o round preservado nao contem um diretorio de snapshots vazio ou
ausente"). Manter a entrada fora do journal quando nao ha o que mover tambem
mantem o `recover` trivial: sem entrada, nao ha diretorio a conferir nem a
devolver.

**Detecao de vazio**: `ls -A1 -- "$dir"` — saida vazia ⇒ diretorio vazio.
Ancoragem da escolha (evidencia rastreavel, nao alegacao normativa sobre o texto
do padrao):

- **Precedente no proprio script alvo**: `_sr_next_label` em `state-rounds.sh` ja
  lista diretorio com `ls -1 -- "$_snl_dir"`. Usar a mesma construcao mantem
  consistencia local.
- **Precedente de `-A` no repo, ja exercitado no CI dos dois alvos**:
  `tests/test_feature-00c-preflight.sh` usa `[ -z "$(ls -A "$_spec_dir" 2>/dev/null)" ]`
  como teste de diretorio vazio (duas ocorrencias).
- **Verificacao empirica nesta maquina** (`Darwin`): `ls -A1 -- <dir com so
  .hidden>` imprime `.hidden` e sai `0` — a flag existe e inclui entradas
  ocultas.

> Nota de veracidade (achado do gate `data-veracity-verifier`): uma versao
> anterior deste documento afirmava normativamente que "`-A`/`-1` sao POSIX" e que
> "`-mindepth`/`-maxdepth` nao sao POSIX". Nenhuma fonte rastreavel disponivel na
> execucao (o texto do padrao POSIX nao esta entre as fontes do projeto)
> sustentava essas afirmacoes, e a segunda era ainda contradita pelo proprio
> repo — ver alternativa abaixo. As afirmacoes foram substituidas por evidencia
> de precedente + verificacao empirica.

**Alternatives considered**:

- *`find "$dir" -mindepth 1`*: rejeitada por **consistencia com o script alvo**,
  nao por portabilidade. A justificativa original ("nao e POSIX") foi retirada por
  ser insustentavel: o repo ja usa `-maxdepth`/`-mindepth` em codigo que roda nos
  dois ambientes — `plugins/cstk/skills/review-features/scripts/aggregate.sh`
  (`find "$ROOT" -mindepth 1 -maxdepth 1 -type d`),
  `plugins/cstk/skills/agente-00c-runtime/scripts/pipeline.sh` e `tests/run.sh`.
  O motivo real de preferir `ls` aqui e que `state-rounds.sh` ja lista diretorio
  com `ls`, e trocar de ferramenta no mesmo arquivo sem ganho seria ruido.
- *Mover sempre que o diretorio existir, mesmo vazio*: rejeitada — contradiz o
  Acceptance Scenario de US3, que pede explicitamente que o round nao ganhe
  diretorio de snapshots vazio.
- *`ls -1` (sem `-A`)*: rejeitada — um `backups/` contendo apenas entradas
  ocultas seria classificado como vazio e ficaria para tras. `-A` elimina esse
  falso-negativo.

---

## Decision 4 — `_sr_staging_complete`: predicado por tipo do item

**Decision**: `_sr_staging_complete` passa a aplicar `[ -d ]` a entrada `backups`
e `[ -f ]` as demais, em vez do `[ -f ]` uniforme de hoje.

**Rationale**: `_sr_staging_complete` e o unico discriminador entre roll-forward e
roll-back no `recover` (bloco `if [ -d "$_rc_target" ] ... elif
_sr_staging_complete ...`). Se `backups` estiver no CSV e a funcao usar `[ -f ]`,
um staging COMPLETO (com `backups/` ja movido) seria classificado como incompleto
e o `recover` faria roll-back de uma rotacao que so faltava commitar — perda de
trabalho valido e violacao de SC-002 ("uma unica tentativa de recuperacao").

**Alternatives considered**:

- *`[ -e ]` uniforme (existe, de qualquer tipo)*: rejeitada — aceitaria um
  `state.db` que fosse diretorio, ou um `backups` que fosse arquivo comum,
  degradando a checagem de consistencia do staging.

---

## Decision 5 — Roll-back de diretorio: destino preexistente e ERRO, nunca merge

**Decision**: no roll-back, antes de devolver `backups` do staging para a raiz, o
`recover` MUST assertar que `"$_SR_STATE_DIR/backups"` **nao existe**. Se existir,
falha com exit `1` e diagnostico acionavel, sem mover nada — nunca tenta merge nem
`mv` cego.

**Rationale (verificado empiricamente, nao inferido)**: `mv` de diretorio para um
destino que ja e diretorio NAO falha nem substitui — ele ANINHA. Verificacao nesta
maquina (`uname -s` ⇒ `Darwin`):

```
$ mkdir -p a/backups b/backups; printf 'x' > a/backups/w1.json
$ mv -- a/backups b/backups; echo "exit=$?"
exit=0
$ find b -print | sort
b
b/backups
b/backups/backups
b/backups/backups/w1.json
```

Ou seja: exit `0`, silencioso, e os snapshots terminam em
`backups/backups/w1.json` — um roll-back que "sucede" deixando o state-dir
estruturalmente corrompido. A guarda explicita converte um sucesso falso em falha
diagnosticavel, preservando a garantia de SC-002 ("totalmente movido ou totalmente
intacto").

**Alternatives considered**:

- *`mv` cego (mesmo tratamento dos arquivos)*: rejeitada pela evidencia acima —
  para arquivos `mv` sobrescreve o destino, para diretorios ele aninha; o
  tratamento uniforme e justamente o bug.
- *Merge entrada a entrada (mover cada `wave-NNN.json` de volta)*: rejeitada —
  introduz semantica de merge com resolucao de colisao (qual `wave-001.json`
  vence?) numa primitiva cujo contrato e "tudo ou nada". Alem disso, sob o lock
  detido pelo `rotate` (guarda G6 do contrato), um `backups/` recriado na raiz no
  meio da rotacao indica anomalia real que merece parar, nao mascarar.
- *`rm -rf` do destino antes do `mv`*: rejeitada — destruiria dados cuja origem e
  desconhecida numa rotina de RECUPERACAO. Inaceitavel numa feature cujo proposito
  e justamente parar de perder snapshots.

---

## Decision 6 — Guarda de symlink para `backups/` (G8)

**Decision**: adicionar guarda de paridade com G4 (contrato `state-rounds.md`
§Guardas de seguranca obrigatorias): se `"$_SR_STATE_DIR/backups"` for symlink
(`[ -L ]`), o `rotate` recusa com exit `1` antes de qualquer escrita e sem incluir
a entrada no journal. Registrada como **G8** na emenda do contrato.

**Rationale**: G4 existe porque "um `rounds` symlinkado tracked levaria a rotacao
para fora do state-dir e quebraria a premissa 'mesmo filesystem ⇒ rename atomico'"
(texto do contrato). O mesmo raciocinio se aplica a um `backups` symlinkado: o
`mv` moveria o proprio link (ou, no roll-back, o restauraria num caminho
diferente), e o conteudo real ficaria fora da unidade atomica do round. Sem G8, o
item novo do conjunto movido seria o unico sem a protecao que todos os outros
caminhos ja tem.

**Alternatives considered**:

- *Resolver o symlink e mover o alvo real*: rejeitada — moveria dados de fora do
  state-dir para dentro do round, quebrando o confinamento de blast radius e a
  premissa de mesmo filesystem que sustenta o rename atomico.
- *Ignorar `backups/` silenciosamente quando for symlink*: rejeitada — perda
  silenciosa de auditoria e exatamente a classe de defeito que esta feature
  corrige (issue #150).

---

## Decision 7 — Purge do abort: escopo ja correto, formalizado por teste

**Decision**: nenhuma mudanca de codigo no purge. O comando
`plugins/cstk/commands/feature-00c-abort.md` executa `rm -rf --
"$AGENTE_00C_STATE_DIR/backups"` sob a flag `--purge-backups` (secao 8 do
comando), caminho que ja e a raiz do state-dir e nao alcanca
`rounds/<label>/backups`. A conformidade com FR-005/SC-003 passa a ser garantida
por cenario de teste de regressao, nao por leitura.

**Rationale**: FR-005 e uma garantia de NAO-REGRESSAO ("MUST NEVER remover ou
alterar snapshots ja movidos"). Antes desta feature ela era vacuamente verdadeira
(nao existia `rounds/<label>/backups`); depois dela passa a ser uma propriedade
que pode ser quebrada por uma edicao futura do comando. Teste automatizado e o
unico mecanismo que a mantem viva.

**Alternatives considered**:

- *Adicionar guarda defensiva no comando de abort (ex.: recusar se o path contiver
  `rounds/`)*: rejeitada — o path e construido a partir de `AGENTE_00C_STATE_DIR`
  no proprio comando, sem interpolacao de rounds; a guarda protegeria contra um
  cenario que o codigo nao produz, adicionando complexidade sem risco coberto.

---

## Decision 8 — Emenda do contrato existente + correcao do teste T-15

**Decision**: `docs/specs/feature-reopen/contracts/state-rounds.md` e emendado no
lugar (nao duplicado): sai `backups/` da lista "Nunca movidos", entra na tabela
"Conjunto movido por backend", a sequencia do `rotate` e a matriz de decisao do
`recover` passam a citar a entrada de diretorio, e a invariante T-06 e reescrita
para "nenhum `-wal`/`-shm`" (o que ela de fato protege) em vez de "contem so
`state.db`". Em paralelo, o cenario T-15 de `tests/test_state-rounds.sh` e
emendado: `backups/` sai das assercoes de "permanece na raiz"; os demais itens
(`enforcement-log.jsonl`, `commit-baseline.txt`, `state-history/`, `.lock/`)
permanecem exatamente como estao.

**Rationale**: sao os dois pontos do repo que hoje afirmam o OPOSTO de FR-001 —
`state-rounds.md` em prosa normativa e `test_state-rounds.sh` como assercao
executavel (`[ -f "$_sd/backups/wave-001.json" ] || _fail "T-15" "backups/ foi
movido"`). Sem emendar ambos, a suite falha e o contrato passa a mentir. A spec ja
determina isso em FR-003; a Delta Requirements da spec registra por que o corpus
canonico (`docs/specs/current/`) nao e o alvo: a capacidade de rotacao ainda vive
inteiramente na spec ativa `feature-reopen`.

**Alternatives considered**:

- *Criar contrato novo em `docs/specs/round-scoped-backups/contracts/` e deixar o
  antigo intacto*: rejeitada — dois contratos divergentes para a mesma primitiva,
  com o mais antigo (e mais encontravel, por ser o da feature que criou o script)
  afirmando o comportamento errado. O contrato desta feature e um DELTA que aponta
  para a emenda, nao uma segunda fonte de verdade.
- *Remover T-15*: rejeitada — T-15 continua cobrindo FR-007 da `feature-reopen`
  para os outros quatro artefatos nao-transacionais; remove-lo abriria buraco de
  cobertura alheio a esta feature.

---

## Unknowns remanescentes

Nenhum. Nao ha `NEEDS CLARIFICATION` no Technical Context: linguagem, runtime,
persistencia, plataforma-alvo e tier de entrega sao herdados do projeto e do
script existente (nenhum eixo estrutural novo e aberto por esta feature).
