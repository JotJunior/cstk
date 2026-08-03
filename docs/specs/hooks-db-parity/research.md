# Research: Paridade Backend-Agnostica dos Hooks 00C

**Feature**: `hooks-db-parity`
**Fase**: 0 (Research)
**Data**: 2026-08-03

> Toda medicao citada aqui foi executada nesta maquina durante a onda-003 da
> execucao `feature-00c` desta feature. Ambiente: macOS (Darwin 25.5.0),
> `sqlite3 3.51.0`, `jq` presente, state-dir SQLite real
> (`.claude/feature-00c-state/hooks-db-parity/state.db`, 122880 bytes) e
> sandboxes sinteticos em `$TMPDIR`. Nenhum numero deste documento e
> estimado — Constitution VI (Veracidade de Dados).

## Resumo dos unknowns resolvidos

| # | Unknown | Resolucao |
|---|---------|-----------|
| 1 | Heuristica leve vs materializacao completa | Heuristica leve (`[ -f state.db ]` + query pontual) |
| 2 | Como preservar a precedencia determinista | Refatorar a resolucao de status; preservar o laco e a ordenacao existentes |
| 3 | Desenho do gate automatizado de latencia | Teste dedicado, mediana de N=20 invocacoes reais, teto por hook, skip-guard em ambiente sem `sqlite3` |
| 4 | Fail-closed do guard vs fail-open das metricas sob SQLite | Tri-estado na deteccao (`ativa` / `inativa` / `indeterminada`); cada hook decide o que fazer com `indeterminada` |
| 5 | Onde confinar a dependencia `sqlite3` (Constitution II) | Helper sourceable unico em `scripts/_hook-active-exec.sh`, resolvido pela cadeia de candidatos ja existente |

---

## Decision 1 — Deteccao por query pontual, nao por materializacao

**Decision**: sob backend SQLite, os hooks resolvem o status da execucao com
uma **query pontual** (`SELECT status FROM execution LIMIT 1;`) diretamente no
`state.db`, apos um teste barato de existencia (`[ -f "$dir/state.db" ]`).
NAO usam `_state-read.sh` / `state-rw.sh read` (materializacao do documento
inteiro) nem `state-rw.sh get --field`.

**Rationale** — medicao empirica (N=50 para as queries, N=20 para os
comandos do runtime; media aritmetica por operacao):

| Caminho | Custo medido | Relativo |
|---------|--------------|----------|
| `sqlite3 <db> "SELECT status FROM execution LIMIT 1"` (path direto) | **3.79 ms** | 1.0x |
| `sqlite3 "file:<db>?mode=ro" "SELECT status ..."` | **4.49 ms** | 1.2x |
| `jq -r '.execution.status' state.json` (o que o hook JA faz por dir JSON) | **5.17 ms** | 1.4x |
| `state-rw.sh get --state-dir X --field '.execution.status'` | **24.29 ms** | 6.4x |
| `state-rw.sh read` (materializa o documento inteiro) | **21.79 ms** | 5.8x |

Piso de referencia do ambiente: `fork/exec` de `/usr/bin/true` = 1.55 ms;
`jq --version` = 2.40 ms; `sqlite3 --version` = 2.54 ms. Ou seja, a query
pontual custa ~1.25 ms **acima do piso de processo** — praticamente so o
custo de subir o binario.

Tres consequencias decidem a questao:

1. A query pontual e **mais barata que a leitura JSON que o hook ja faz
   hoje** (3.79 ms vs 5.17 ms). Portar para SQLite nao piora o hook; no
   limite, melhora.
2. A materializacao e **5.8x mais cara** e traria efeitos colaterais
   (mktemp por invocacao, trap de cleanup, propagacao de exit code) para
   ler UM campo de UMA linha.
3. `_state-read.sh` foi desenhado para **leitores do runtime** que precisam
   do documento inteiro para rodar `jq` arbitrario (`budget.sh`, `drift.sh`,
   `cycles.sh`). Os hooks precisam de um unico escalar. Usar o
   materializador aqui seria acoplar um hook fail-open a um caminho que
   propaga falha por contrato (FR-012 da `state-db-runtime-parity`).

Medicao do prototipo completo da deteccao portada (script real, nao
micro-benchmark): **11.52 ms** com 1 state-dir SQLite ativo; **91.64 ms**
com 22 state-dirs (21 JSON terminais + 1 SQLite ativo). O custo do cenario
de 22 dirs e dominado pelos 21 spawns de `jq` dos dirs JSON **ja existentes
hoje** — nao pela adicao do SQLite. Comparacao direta com os hooks atuais no
mesmo sandbox: tick = 12.36 ms (1 dir) / 93.48 ms (22 dirs); bash-guard =
17.36 ms (1 dir) / 96.38 ms (22 dirs). A deteccao portada nao adiciona custo
mensuravel acima do ruido nesses cenarios.

**Alternatives considered**:

- **`_state-read.sh` + `jq` no documento materializado** — rejeitado por
  custo (21.79 ms, 5.8x) e por acoplar fail-open a um contrato de
  propagacao de falha. Vantagem descartada: reuso do "caminho canonico" —
  que existe para leitores de documento, nao para probes de escalar.
- **`state-rw.sh get --field`** — rejeitado: 24.29 ms, o mais caro dos
  tres, porque paga materializacao + `jq` + overhead do dispatcher do
  script.
- **Ler o `state.db` sem `sqlite3`** (parse do formato binario em sh) —
  descartado sem medicao: reimplementaria um parser de formato de arquivo
  em POSIX sh, violando o Principio V (profundidade acima de metrica) e
  criando uma segunda implementacao divergente da fonte de verdade.

### 1.a Modo de abertura do `sqlite3`: `mode=ro` com fallback

Medicao dedicada (3 copias identicas do `state.db` real, cada uma aberta de
um jeito):

| Modo de abertura | Resultado | Efeito colateral no state-dir |
|------------------|-----------|-------------------------------|
| path direto (`sqlite3 <db> "..."`) | le corretamente (inclusive WAL) | **cria `state.db-shm` (32768 B) e `state.db-wal`** |
| `file:<db>?mode=ro` | le corretamente **se** `-shm`/`-wal` existirem; sem os sidecars falha com `Error: in prepare, unable to open database file (14)` | nenhum |
| `file:<db>?immutable=1` | le sempre, sem erro | nenhum |

`immutable=1` foi **rejeitado**: a flag afirma ao SQLite que o arquivo nao
pode mudar, o que o autoriza a ignorar o `-wal`. Em um state-dir com escritor
concorrente (o proprio orquestrador/servidor MCP a cada onda) isso admite
leitura stale — inaceitavel para uma decisao de guarda. A tentativa de
demonstrar staleness empiricamente nao produziu divergencia porque a CLI
`sqlite3` faz checkpoint no fechamento da ultima conexao, logo o cenario
exige escritor de longa duracao; na ausencia de prova empirica de que e
seguro, prevalece a leitura conservadora (nao usar `immutable=1`).

**Decision**: tentar `file:<db>?mode=ro` primeiro (zero efeito colateral,
enxerga o WAL) e, em falha, cair para o path direto (sempre funciona; pode
criar `-shm`/`-wal`, artefatos legitimos do proprio SQLite, nao um espelho
de estado). Ambos os caminhos foram medidos e ambos retornam o valor
correto (`em_andamento`) contra o `state.db` real.

Nota de escopo: `-shm`/`-wal` criados pelo fallback **nao** violam a regra
anti-mirror (`FR-003` da `state-db-runtime-parity`), que proibe materializar
uma copia legivel do estado dentro do state-dir. Sao arquivos internos do
motor, ja presentes no state-dir de qualquer execucao ativa (verificado no
state-dir real desta execucao).

---

## Decision 2 — Precedencia preservada por refatoracao minima do laco

**Decision**: manter **verbatim** a estrutura de decisao ja existente nos
tres hooks — (1) `agente-00c` vence sobre `feature-00c`; (2) entre
`feature-00c`, menor short-name em ordem byte-wise (`LC_ALL=C sort | sed -n
'1p'`); (3) status ativo = `em_andamento` ou `aguardando_humano` — e trocar
**apenas** a operacao "obter o status deste state-dir", que hoje e uma
chamada `jq` hard-coded contra `state.json`.

**Rationale**: a precedencia e um requisito de determinismo (FR-002) ja
coberto por testes existentes sob JSON. A refatoracao mais segura e a que
nao toca o laco, a ordenacao nem o predicado de status. Codigo lido nos
tres arquivos confirma que a logica e identica byte a byte:

- `pretooluse-bash-guard.sh` L210-241 (`_pbg_is_active_status`, laco em
  `"$_pbg_feat_root"/*/`, `LC_ALL=C sort`)
- `posttooluse-tool-call-tick.sh` L60-97 (`_ptt_*`, idem)
- `posttooluse-agent-usage.sh` L76-114 (`_pau_*`, idem)

O laco atual comeca com `[ -f "${d}state.json" ] || continue` — essa linha e
a causa-raiz: um state-dir SQLite e **pulado antes de qualquer avaliacao**.
A troca e substituir esse gate por "resolver status deste dir (JSON ou DB)"
e continuar apenas quando o status nao for ativo.

Ordem de tentativa dentro de um mesmo state-dir (importa para o caso de
backend misto acidental, FR-002 + Edge Case 2 da spec): **`state.db` vence
sobre `state.json`**, em paridade com `_sr_backend()`
(`_state-rw-db.sh:53`) e com `state_read_materialize()`
(`_state-read.sh:58`), que ja selecionam SQLite pela mera presenca do
`state.db`. Divergir dessa regra criaria duas nocoes de "backend efetivo"
no mesmo repositorio.

**Alternatives considered**:

- **Reescrever a deteccao como um unico `find`/`sort` unificado** —
  rejeitado: mudaria a forma do laco e exigiria re-derivar o determinismo
  ja testado, sem ganho funcional.
- **Ordenar por mtime ou por "quem abriu primeiro"** — rejeitado: viola
  FR-002 explicitamente (a spec fixa a ordem lexicografica).

---

## Decision 3 — Gate automatizado de latencia: mediana de N=20, teto por hook

**Decision**: criar um cenario de teste dedicado (no test de cada hook) que
mede a latencia **end-to-end do hook real** contra um state-dir SQLite
sintetico e falha se o teto for ultrapassado. Parametros fixados:

| Parametro | Valor | Justificativa |
|-----------|-------|---------------|
| Estatistica | **mediana** de N=20 invocacoes | media e sensivel a um unico outlier de scheduler; p95 com N=20 e o 19o valor, praticamente "o pior caso", instavel em CI compartilhado |
| Warm-up | 3 invocacoes descartadas | primeira abertura do `state.db` paga cache frio de FS |
| Teto — hooks de metrica | **150 ms** | orcamento da spec = ~30 ms (FR-005); medido hoje = 12.36 ms; teto de gate = 5x o orcamento para absorver CI lento |
| Teto — hook de guarda | **400 ms** | orcamento da spec = ~177 ms; medido hoje = 17.36 ms; mesma folga proporcional |
| Skip condicional | `sqlite3` ausente => cenario **skip** (nao fail) | o gate mede latencia, nao disponibilidade; ausencia de dep e coberta por cenario proprio (Decision 4) |
| Fixture | 1 state-dir SQLite ativo, criado no proprio teste | isola o custo da deteccao SQLite do custo O(N) de varrer dirs JSON preexistentes |

**Rationale**: o clarify desta feature fixou "gate automatizado que mede e
falha" (Session 2026-08-03), e SC-003 repete. O risco conhecido de um gate
de tempo em CI e o flake — ja existe precedente no repositorio
(`tests/README.md` e a allowlist `_is_slow_test` de `tests/run.sh`
reconhecem variabilidade de maquina). Dai as tres mitigacoes acima:
mediana (nao media/p95), warm-up, e teto folgado em relacao ao orcamento
de projeto.

O teto folgado nao esvazia o gate: o valor que ele precisa capturar e uma
**regressao de ordem de grandeza** — trocar a query pontual por
materializacao (21.79 ms => ~6x) ou introduzir uma varredura por dir. Um
teto de 150 ms contra 12.36 ms medidos ainda detecta qualquer regressao de
10x, que e exatamente a classe de erro que FR-005 quer barrar. Um teto
apertado (ex.: 30 ms exatos) falharia em CI compartilhado por ruido, seria
silenciado, e o gate morreria — pior que um gate folgado vivo.

Medicao do relogio: `perl -MTime::HiRes=time` (usado nas medicoes desta
onda). `perl` esta presente em macOS e nas imagens de CI usadas pelo
repositorio; se ausente, o cenario faz **skip** pelo mesmo criterio do
`sqlite3` — um gate de performance nunca pode virar um gate de
disponibilidade de ferramenta de medicao.

**Alternatives considered**:

- **`time` builtin + parse de saida** — rejeitado: resolucao e formato
  variam entre shells (`sh`/`dash`/`zsh`) e locale (virgula vs ponto
  decimal — ha precedente de FAIL falso por locale `pt_BR` no repositorio).
- **p95 com N=100** — rejeitado: N=100 x 3 hooks x ~15 ms = ~5 s so nesse
  gate, empurrando os tests para a allowlist de lentos; ganho estatistico
  irrelevante para detectar regressao de ordem de grandeza.
- **Gate por contagem de spawns (`sqlite3`/`jq` invocados)** em vez de
  tempo — considerado como *complemento* util e barato, porem insuficiente
  sozinho: nao captura regressao dentro de uma unica invocacao (ex.: query
  sem `LIMIT` num DB grande). Fica como cenario adicional, nao substituto.

---

## Decision 4 — Tri-estado na deteccao; cada hook decide sua politica de falha

**Decision**: o helper de deteccao retorna **tres** estados distintos, e nao
o binario "achou/nao achou" de hoje:

| Estado | Significado | Exit code do helper |
|--------|-------------|---------------------|
| `ativa` | execucao ativa localizada; imprime `<tipo>\t<state-dir>` | 0 |
| `inativa` | varredura completa, nenhuma execucao ativa (inclui "nenhum state presente") | 1 |
| `indeterminada` | um `state.db` esta presente porem o status nao pode ser determinado (`sqlite3` ausente, DB corrompido, erro de leitura) | 2 |

Politica por hook (FR-003 vs FR-004):

| Hook | `ativa` | `inativa` | `indeterminada` |
|------|---------|-----------|-----------------|
| `pretooluse-bash-guard.sh` | delega a `bash-guard.sh` (comportamento atual) | `exit 0`, fora de escopo | **`MECANISMO_FALHOU` + `permissionDecision: deny`** (fail-closed) |
| `posttooluse-tool-call-tick.sh` | grava tick no sidecar | `exit 0` silencioso | **`exit 0` silencioso** (fail-open) |
| `posttooluse-agent-usage.sh` | grava linha no sidecar | `exit 0` silencioso | **`exit 0` silencioso** (fail-open) |

**Rationale**: FR-007 exige distinguir "nenhum state presente" (fora de
escopo) de "`state.db` presente porem ilegivel" (falha de mecanismo). Um
retorno binario nao consegue expressar essa diferenca — e e exatamente essa
confusao que produz o bug atual, onde "nao consegui ler" e tratado como
"nao ha execucao". O tri-estado torna a distincao explicita no **unico**
ponto que tem a informacao (quem tentou abrir o DB), em vez de espalhar
heuristica por tres hooks.

Assimetria fail-closed/fail-open preservada: e a mesma ja documentada nos
cabecalhos dos hooks (`pretooluse-bash-guard.sh` L16-19: sem `jq` =>
`MECANISMO_FALHOU`; `posttooluse-tool-call-tick.sh` L14-19: fail-open
absoluto). Esta feature apenas estende a assimetria existente ao novo modo
de falha (SQLite ilegivel).

Caso `sqlite3` ausente + `state.db` presente: para o guard e **bloqueio**
(`MECANISMO_FALHOU`), nunca liberacao. Verificado que este e um estado
alcancavel de fato — o `state.db` pode existir num host onde `sqlite3` foi
removido do PATH; nesse caso o proprio runtime (`state-rw.sh read`) tambem
falha com exit 1, ou seja, a execucao esta quebrada de qualquer forma e
liberar comandos sem guarda seria a pior das saidas.

Caso "backend misto acidental": um dir SQLite `indeterminado` **nao**
interrompe a varredura dos demais dirs. A varredura completa e feita; se
algum dir resolver `ativa`, vence a precedencia normal (FR-002). O estado
`indeterminada` so e retornado quando **nenhuma** execucao ativa foi
confirmada E ao menos um dir ficou indeterminado — evita que um state-dir
antigo corrompido bloqueie o host inteiro enquanto ha uma execucao
saudavel em curso.

**Alternatives considered**:

- **Binario + variavel de "houve erro" exportada** — rejeitado: o helper e
  consumido via `$(...)` (subshell); variavel setada la nao chega ao
  chamador. Mesma armadilha ja documentada em `_state-read.sh:32-37`.
- **Fail-closed tambem nos hooks de metrica** — rejeitado: viola FR-004
  literalmente e transformaria um bug de subcontagem numa interrupcao de
  sessao.
- **Fail-open no guard quando `sqlite3` falta** — rejeitado: e exatamente a
  regressao de seguranca que esta feature existe para eliminar (US1).

---

## Decision 5 — Confinamento da dep `sqlite3` num helper sourceable unico

**Decision**: criar **um** arquivo novo,
`global/skills/agente-00c-runtime/scripts/_hook-active-exec.sh`, sourceable
(prefixo `_`, seguindo a convencao ja usada por `_state-read.sh`,
`_state-dir.sh`, `_log.sh`), contendo a funcao de deteccao tri-estado e a
**unica** mencao a `sqlite3` fora da camada de estado transacional. Os tres
hooks passam a resolver e sourcer esse helper; nenhum deles referencia
`sqlite3` diretamente.

**Rationale (Constitution II — bloqueante)**: o carve-out 1.3.0
(dependencia obrigatoria) e explicitamente **inaplicavel** aqui — sua
condicao (a) diz que a obrigatoriedade vale so para o runtime de estado
transacional e que "nenhuma outra parte do toolkit (skills de documentacao,
CLI de catalogo, **hooks**) pode exigir a ferramenta como pre-requisito de
funcionamento". Logo a dep `sqlite3` nos hooks precisa passar pelo carve-out
**1.1.0** (dep opcional), cujas tres condicoes sao cumulativas:

- **(a) opcional com fallback graceful verificavel**: sem `sqlite3`, os
  hooks seguem funcionando integralmente para backend JSON (o caminho
  `jq`/`state.json` e intocado) e degradam de forma definida no caminho
  SQLite — guard bloqueia (`MECANISMO_FALHOU`), metricas viram no-op. Cada
  degradacao tem cenario de teste dedicado (Decision 3 / plan §Testes).
- **(b) confinamento em UM arquivo identificavel**: satisfeito pelo helper
  unico. `grep -rn sqlite3 global/skills/agente-00c-runtime/hooks/` deve
  retornar zero linhas de codigo apos a implementacao; a unica ocorrencia
  nova no toolkit fora da camada de estado fica em `_hook-active-exec.sh`.
- **(c) declaracao explicita**: feita neste research e no `plan.md`
  §Constitution Check / §Complexity Tracking.

Ganho colateral (e o mais importante para a causa-raiz): hoje o algoritmo de
deteccao esta **triplicado verbatim** nos tres hooks — e por isso o mesmo bug
existe em triplicata. Um helper unico elimina a classe inteira.

**Resolucao do helper**: reusar a cadeia de candidatos ja existente em
`_pbg_resolve_dep` (`pretooluse-bash-guard.sh` L54-69), verificada no
codigo: (1) sibling `<hook-dir>/../scripts/<rel>` — cobre a arvore-fonte do
repo em dev/testes; (2) `<cwd>/.claude/skills/agente-00c-runtime/<rel>` —
escopo project; (3) `$HOME/.claude/skills/agente-00c-runtime/<rel>` —
escopo global. Precedente confirmado: o guard **ja** depende hoje de
`scripts/bash-guard.sh` e `scripts/secrets-filter.sh` resolvidos assim,
apesar de ser provisionado standalone em `<projeto>/.claude/hooks/`
(`cli/lib/hooks.sh::apply_guard_hooks`). Nenhum mecanismo de distribuicao
novo e necessario — os hooks continuam sendo os 3 arquivos ja provisionados.

**Compatibilidade com instalacao stale** (helper ainda nao presente no
host): cada hook trata "helper irresolvivel" pela sua propria politica de
falha, mas **so quando ha `state.db` em jogo**:

- se nenhum `state.db` existe no cwd, os hooks usam o caminho JSON inline
  (comportamento identico ao de hoje, zero regressao para quem nao migrou);
- se ha `state.db` e o helper nao resolve, o guard bloqueia
  (`MECANISMO_FALHOU`) e as metricas viram no-op — mesma semantica de
  `indeterminada`.

Isso e o que impede o pior cenario de rollout: um host com hooks novos e
catalogo velho (ou vice-versa) **nao** passa a bloquear todo comando Bash
de todo projeto — apenas projetos que de fato migraram para SQLite, que
hoje ja estao sem guarda alguma.

**Alternatives considered**:

- **Replicar a deteccao SQLite nos 3 hooks** (espelho do que ja se faz com
  `jq`) — rejeitado: `sqlite3` apareceria em 3 arquivos, ferindo a condicao
  (b) do carve-out 1.1.0, e perpetuaria a triplicacao que causou este bug.
  O precedente do `jq` triplicado nao autoriza um segundo caso; e divida
  tecnica existente, nao licenca.
- **Novo subcomando em script executavel ja existente** (ex.:
  `guard-hooks-status.sh active-exec`) — rejeitado por custo: seria um
  `fork/exec` adicional por invocacao de hook (piso medido 1.55 ms + shell
  startup + dispatcher), contra ~0 do `.` (source). Tambem misturaria um
  script de diagnostico do operador com o caminho quente do hook.
- **Embutir o helper como heredoc gerado no momento do provisionamento** —
  rejeitado: cria duas copias divergentes (fonte + provisionada) sem
  `cstk doctor` para detectar drift entre elas.

---

## Decision 6 — Cobertura de testes e extensao da varredura de paridade

**Decision**: estender os tres testes de hook ja existentes e a varredura
estatica de paridade, sem criar arquivo de teste novo por hook:

| Arquivo | Extensao |
|---------|----------|
| `tests/test_pretooluse-bash-guard.sh` | deteccao sob SQLite; `deny` sob SQLite; `sqlite3` ausente + `state.db` presente => `MECANISMO_FALHOU`; state-dir sem nenhum state => fora de escopo; gate de latencia |
| `tests/test_posttooluse-tool-call-tick.sh` | tick gravado sob SQLite; `sqlite3` ausente => no-op silencioso (stdout **e** stderr vazios); gate de latencia |
| `tests/test_posttooluse-agent-usage.sh` | linha de spawn gravada sob SQLite; no-op silencioso na falha; gate de latencia |
| `tests/test_state-parity-sweep.sh` | **incluir `hooks/*.sh` na varredura estatica** de construcao de path `/state.json` |
| (novo) `tests/test_hook-active-exec.sh` | teste unitario do helper: tri-estado, precedencia `agente-00c` > `feature-00c`, ordem `LC_ALL=C`, backend misto |

**Rationale**: a varredura estatica de `tests/test_state-parity-sweep.sh`
(camada (b)) hoje itera sobre `"$R"/*.sh` (o diretorio `scripts/`) mais
`cli/lib/00c-bootstrap.sh` — **o diretorio `hooks/` esta fora do alcance**,
verificado por leitura do arquivo (L230-247). E precisamente por isso que a
regressao dos hooks passou despercebida quando a `state-db-runtime-parity`
portou os 15 leitores do runtime: o sweep que deveria ter pego nunca olhou
para la. Incluir `hooks/*.sh` no laco fecha a lacuna de forma permanente —
qualquer hook futuro que construa `/state.json` na mao passa a falhar a
suite.

Consequencia de manutencao: os tres hooks mantem o caminho JSON inline
(construcao `<dir>/state.json` legitima), logo entram na allowlist
`_static_allowlist()` com classificacao `codigo-real` e justificativa — o
mesmo tratamento ja dado a `state-lock.sh`, `bloqueios.sh`,
`state-decisions.sh` e demais mutadores dual-backend. A allowlist tem
cenario proprio contra entradas mortas (`scenario_estatica_allowlist_sem_
entradas_mortas`), entao a entrada precisa continuar tendo hit real.

O novo `tests/test_hook-active-exec.sh` e exigido pela convencao do
repositorio (`CLAUDE.md` §Como testar scripts shell): todo `.sh` novo em
`global/skills/*/scripts/` precisa do `tests/test_<nome>.sh`
correspondente, sob pena de `./tests/run.sh --check-coverage` falhar com
exit 1.

**Alternatives considered**:

- **Um unico teste de integracao cobrindo os 3 hooks** — rejeitado: perde
  granularidade de diagnostico e conflita com a convencao 1:1
  script<->teste ja gateada por `--check-coverage`.
- **Estender a camada dinamica do sweep (manifest de leitores) aos hooks**
  — considerado; a camada dinamica invoca cada leitor contra um state-dir
  SQLite populado e checa exit code contratual. Os hooks nao tem interface
  de linha de comando (consomem JSON em stdin), entao entrariam no manifest
  com um invocador especial. Fica **fora** desta feature: a camada estatica
  ja fecha a lacuna que produziu o bug, e o comportamento dinamico dos
  hooks passa a ser coberto pelos testes dedicados de cada um.

---

## Riscos residuais

| Risco | Severidade | Mitigacao |
|-------|------------|-----------|
| Gate de latencia flakeando em CI compartilhado | Media | mediana + warm-up + teto 5x o orcamento (Decision 3); skip se `perl`/`sqlite3` ausentes |
| Host com hooks novos e catalogo stale (helper irresolvivel) | Media | fallback JSON inline preserva o comportamento atual quando nao ha `state.db`; bloqueio so atinge projetos ja migrados, que hoje estao sem guarda (Decision 5) |
| Leitura stale sob escritor concorrente | Baixa | `immutable=1` descartado; `mode=ro` e path direto ambos consultam o WAL (Decision 1.a) |
| `-shm`/`-wal` criados pelo fallback em state-dir de execucao encerrada | Baixa | artefatos internos do SQLite, nao espelho de estado; ja presentes em qualquer execucao ativa |
| Contencao/lock do SQLite durante escrita transacional (Edge Case 3 da spec) | Baixa | query de leitura em WAL nao bloqueia escritor nem e bloqueada por ele; em erro, cai no tri-estado `indeterminada` e cada hook aplica sua politica |
