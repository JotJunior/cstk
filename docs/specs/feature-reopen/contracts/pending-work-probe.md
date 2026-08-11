# Contract: `commit-mode.sh probe-pending-work`

**Status**: `[IMPLEMENTADO — FASE 4, tasks 4.1..4.3]`. Subcomando implementado
em `commit-mode.sh` (`_cm_cmd_probe_pending_work`) exatamente conforme este
contrato; T-50..T-53 cobertos em `tests/test_commit-mode.sh`
(`./tests/run.sh commit-mode` => `PASS: 53 FAIL: 0 ERROR: 0`). Fecha o
`[Gap]` CHK002 (`checklists/requirements.md`) e e o insumo direto de CHK009
(`checklists/security.md`, task 1.2).

**Path do script**: `plugins/cstk/skills/agente-00c-runtime/scripts/commit-mode.sh`
(subcomando novo — ver §Subcomandos no cabecalho do arquivo)
**Teste obrigatorio**: extensao de `tests/test_commit-mode.sh` (T-50..T-53, ja
listados em `plan.md`)

Sonda de trabalho nao integrado do round anterior (FR-021). Nao decide nada:
so observa e reporta, citando a fonte de cada afirmacao. A politica ("avisar e
deixar o operador confirmar") vive na camada acima (Decision 10,
`data-model.md::ReopenAdvisory`) — este contrato cobre so a coleta do fato.

## Conformidade obrigatoria (Constitution Principio II, NON-NEGOTIABLE)

- `#!/bin/sh` + `set -eu` (herdado do arquivo — nenhuma regra nova).
- Sem GNU-only. Alvo real: macOS/zsh (dev) **e** Ubuntu (CI).
- Erros em stderr, dados em stdout — mesmo padrao dos demais subcomandos de
  `commit-mode.sh`.
- `git` e dependencia obrigatoria (ja o e para o arquivo inteiro). `gh` e
  dependencia **opcional** (carve-out ja usado por `finalize`): ausencia ou
  falta de autenticacao produz skip nao-fatal, nunca aborta.
- **Divida constitucional herdada, nao criada aqui** (Decision 9,
  `research.md`): `gh` ja e invocado em mais de um arquivo do toolkit
  (`commit-mode.sh`, `issue.sh`, `cli/lib/session.sh`), o que hoje viola a
  condicao (b) do carve-out de dependencia opcional (amendment 1.1.0). Este
  contrato **nao regulariza** esse desvio pre-existente; apenas nao o agrava
  (reusa `commit-mode.sh`, nao cria um 4o arquivo com `gh`).

## Nome do subcomando e decisao de flags (task 1.1.2)

**Decisao**: `probe-pending-work`. Segue o padrao verbo-substantivo ja usado no
arquivo (`guard-branch`, `stage-message`) em vez de inventar um estilo novo.

```
commit-mode.sh probe-pending-work --state-dir DIR --projeto-alvo-path PATH -- BRANCH
```

| Flag/arg | Tipo | Obrigatorio | Notas |
|----------|------|-------------|-------|
| `--state-dir` | path | sim | Convencao uniforme do arquivo: **todo** subcomando de `commit-mode.sh` aceita `--state-dir` mesmo quando nao o consome no corpo (`guard-branch` e precedente literal — aceita e nunca le `_sdir`). Aqui reservado para consistencia de invocacao pelo orquestrador e para uso futuro de `_cm_diag`/log auditavel no state-dir; **nao** e usado para resolver a branch nem o repositorio. |
| `--projeto-alvo-path` | path | sim | repositorio onde `git`/`gh` rodam (`git -C "$PAP"`, `gh -R` implicito pelo `cd`) — mesmo padrao de `guard-branch`/`finalize` |
| `BRANCH` (posicional, apos `--`) | string | sim | branch do round anterior a avaliar. **Decisao** (task 1.1.2): posicional com `--` como separador obrigatorio, e nao `--branch NAME` — nomes de branch podem comecar por `-` (T-52) e um separador explicito e a defesa POSIX padrao (mesmo idioma de `git checkout -- <path>`), sem depender de heuristica de parsing de flag |

Por que **nao** `--branch NAME`: um valor de flag iniciado por `-` (ex.:
branch `--force-push-test` criada por engano) exigiria o MESMO tratamento de
separador para ser seguro, entao o separador `--` já é necessário de qualquer
forma; tornando-o o mecanismo primario (posicional) evita ter duas defesas
sobrepostas (flag nomeada + separador) para o mesmo risco.

## Exit codes

| Code | Significado |
|------|-------------|
| `0` | sucesso — `PROBE\|...` impresso; git respondeu (branch existe e o estado de merge foi determinado). `gh` pode ter rodado ou nao: se nao rodou (`probe_status` = `skipped-gh-missing`/`skipped-gh-unauth`), isso e visivel nos campos `pr_state=unknown`/`pr_url=null`, mas nao rebaixa o exit — o fato de merge (`merged`), que e o dado primario de FR-021, foi checado de fato. |
| `3` | skip nao-fatal **total** — `probe_status=skipped-no-git`: `git` ausente no PATH, `--projeto-alvo-path` nao e repositorio git, ou a branch informada nao existe localmente/remotamente. `PROBE\|...` ainda e impresso, com `merged=unknown`/`pr_state=unknown`. Alinhado ao uso de `3` no resto do arquivo (`guard-branch`/`stage-derived`: recusa/skip nao-fatal, nunca erro do chamador). |
| `1` | erro generico — falha inesperada de IO/permissao nao coberta pelos skips previstos acima (ex.: `--projeto-alvo-path` existe mas nao e legivel) |
| `2` | uso incorreto — flag obrigatoria ausente, `--` ausente, `BRANCH` vazio apos `--`, flag desconhecida |

Esta tabela cobre a definicao pedida por 1.1.3. Note que o enum
`probe_status` (`data-model.md::PendingWorkProbe`) tem 4 valores mas o exit
code so distingue 2 categorias (`checked` vs. `skipped-no-git` == exit 3); as
duas variantes de skip do `gh` (`skipped-gh-missing`/`skipped-gh-unauth`) sao
reportadas em `probe_status` **sem** rebaixar o exit para 3, porque o dado
primario de FR-021 (branch mesclada ou nao) permanece verificado — ver
§Aberto para 1.2 para o caso em que esse recorte for julgado insuficiente.

## Sequencia

```
a. Parse de flags; falta de obrigatoria ou BRANCH vazio -> exit 2
b. command -v git ausente -> probe_status=skipped-no-git, PROBE| com
   merged=unknown/pr_state=unknown/source="command -v git" -> exit 3
c. git -C "$PAP" rev-parse --verify --quiet "refs/heads/$BRANCH" (ou
   equivalente remoto) falha -> probe_status=skipped-no-git,
   source cita o comando exato executado -> exit 3
d. default_branch: git -C "$PAP" symbolic-ref refs/remotes/origin/HEAD,
   filtrado por sed (mesmo padrao de guard-branch/finalize); sem remote,
   "main"/"master" tratados como default (mesma convencao ja usada)
e. merged: git -C "$PAP" merge-base --is-ancestor "$BRANCH" "$default_branch"
   (ou equivalente) -> merged=yes|no, source cita o comando; nunca "no"
   por falha de execucao (I-P1) — falha aqui recai no passo (c)/(b), nao
   vira "no" silencioso
f. command -v gh ausente -> probe_status=skipped-gh-missing,
   pr_state=unknown, pr_url=null, source="command -v gh"
g. gh auth status falha -> probe_status=skipped-gh-unauth,
   pr_state=unknown, pr_url=null, source="gh auth status"
h. gh pr view "$BRANCH" --json url,state -> pr_state, pr_url,
   source="gh pr view <branch> --json url,state"; falha/vazio do comando
   (rede, timeout, rate-limit) -> pr_state=unknown/pr_url=null,
   probe_status permanece o skip aplicavel — NUNCA "closed"/"merged"
   inferido de saida vazia (I-P1; ver nota de precedente abaixo)
i. probe_status=checked quando (e) e (h) ambos produziram valor
   determinado; senao o skip mais especifico dentre f/g/b/c
j. imprime PROBE|...; exit conforme tabela acima
```

> **Nota de precedente (achado desta onda, informa 1.2)**: o subcomando
> `finalize`, ja existente no mesmo arquivo, chama `gh pr view "$_curr_branch"
> --json url,state 2>/dev/null` e trata saida vazia (`_ex_json=""`) — que
> tanto pode significar "PR nao existe" quanto "gh falhou/rede indisponivel"
> — como "nao ha PR", prosseguindo para criar um novo (`commit-mode.sh:726`,
> `~:771`). Isso e exatamente o padrao que I-P1 proibe para a sonda nova.
> Este contrato **nao herda** esse padrao: o passo (h) acima exige distinguir
> explicitamente "gh respondeu com JSON vazio/PR inexistente" (verificavel via
> exit code do `gh pr view`, tipicamente `1` com mensagem "no pull requests
> found") de "gh falhou por outro motivo" (rede/timeout) — ambos os casos MUST
> virar `pr_state=unknown` a menos que o exit/mensagem do `gh` confirme
> positivamente "nao ha PR". A granularidade exata dessa distincao (matriz de
> exit codes do `gh`) e o que a pergunta de CHK009 (task 1.2) esta avaliando.

## Response (stdout)

```
PROBE|<branch>|<default_branch>|<merged>|<pr_state>|<pr_url>|<source>|<probe_status>
```

Pipe-delimitado, mesmo padrao de `ROUND|...` (`state-rounds.md`) e
`RESULT|...` (`delta-gate.sh`) — parseavel com `IFS='|'` sem `jq`. Mapeamento
1:1 com `data-model.md::PendingWorkProbe`:

| Posicao | Campo | Valores |
|---------|-------|---------|
| 1 | `branch` | string (nunca vazio quando exit 0/3 — e o `BRANCH` de entrada) |
| 2 | `default_branch` | string ou `unknown` |
| 3 | `merged` | `yes` \| `no` \| `unknown` |
| 4 | `pr_state` | `open` \| `closed` \| `merged` \| `unknown` |
| 5 | `pr_url` | string ou `-` (placeholder de campo vazio no formato pipe; `null` semantico) |
| 6 | `source` | comando(s) literal(is) que produziram as afirmacoes, `; `-separado quando mais de um contribuiu (ex.: `git merge-base --is-ancestor; gh pr view`) |
| 7 | `probe_status` | `checked` \| `skipped-gh-missing` \| `skipped-gh-unauth` \| `skipped-no-git` |

`source` **nunca** pode ficar vazio quando `merged` ou `pr_state` != `unknown`
(I-P1 exige citar a fonte de toda afirmacao) — campo NOT NULL no data-model.

### `--dry-run`

Nao aplicavel. A sonda e inerentemente read-only (nenhum passo do §Sequencia
escreve em disco); nao ha estado transacional para simular.

## I-P1 (Principio VI, FR-021) — nota explicita (task 1.1.5)

`merged=unknown` ou `pr_state=unknown` MUST ser reportado, por todo consumidor
deste contrato (o parecer de reabertura, `data-model.md::ReopenAdvisory`),
como **"nao verificado"** — jamais como "nao ha trabalho pendente". Nenhum
caminho de erro listado no §Sequencia (timeout de `gh`, `git` corrompido,
ausencia de rede, ausencia de binario) pode emitir `merged=no` ou
`pr_state=closed` sem uma checagem que de fato respondeu isso — a unica saida
legitima de uma falha de execucao e `unknown` + o `probe_status=skipped-*`
correspondente. O achado de precedente acima (`finalize`) documenta o
anti-padrao que este contrato existe para NAO repetir.

## Resolucao de 1.2 (dec-038 — decisao do operador)

Task 1.2 decidiu por uma **regra estrutural fail-closed**, nao pela matriz de
exit codes cogitada originalmente (ver historico abaixo). Registrada como
`dec-038` (onda-005, score 3, evidencia: `commit-mode.sh:726`/`:771`).

**Regra** (aplica-se a TODO campo do `PendingWorkProbe`, nao so a `pr_state`):

1. Um campo so recebe **valor concreto** quando a leitura que o produz foi
   **bem-sucedida E parseada** (exit `0` do comando-fonte + saida no formato
   esperado).
2. Qualquer outro desfecho — `exit != 0`, stdout vazio, JSON nao-parseavel,
   binario ausente — MUST manter o campo em `unknown` e marcar o
   `probe_status` correspondente (`skipped-*`). Nunca um valor negativo
   (`merged=no`, `pr_state=closed`) inferido de ausencia/erro.
3. **PROIBIDO** o idioma `cmd 2>/dev/null || var=""` seguido de tratar
   `var` vazio como resposta negativa — o anti-padrao identificado em
   `commit-mode.sh:726` e `:771` (`finalize`), que descarta stderr e
   colapsa o exit code, tornando timeout, `gh` nao-autenticado e ausencia
   real de PR indistinguiveis.
4. O teste (`tests/test_commit-mode.sh`, T-51) MUST incluir cenario que
   simula **falha** do `gh` (nao so ausencia do binario) e AFIRMA que a
   saida traz `unknown`/`skipped-*` — nunca `merged=no` nem
   `pr_state=closed`.

**Candidatos avaliados e DESCARTADOS** (registrados para fechar a pergunta,
nao deixa-la aberta):

- **Matriz de exit codes do `gh pr view`** (candidato 1): amarraria o
  contrato a comportamento de ferramenta externa nao documentado
  formalmente, exigindo supor comportamento nao verificado (Principio VI).
  A regra estrutural acima e mais forte e mais barata: uma unica pergunta
  por leitura de codigo ("existe caminho que atribui valor concreto sem
  leitura verificada?") em vez de depender da tabela do `gh`.
- **Timeout proprio para `git merge-base --is-ancestor`** (candidato 2):
  operacao local sem rede; `timeout(1)` nao e POSIX-portavel nem existe
  por padrao no macOS — introduziria dependencia nova sem ganho.
- **Granularidade por-campo do `probe_status`** (candidato 3): o enum
  unico ja basta sob a regra estrutural (nomeia o desfecho mais
  degradado); mudar o schema seria alteracao fora do escopo de 1.1.

Com isso, a implementacao de 4.1 esta LIBERADA (dec-038).

## Heranca de `--atomic-commit` (task 4.2.2)

`probe-pending-work` **NAO participa** da heranca de `.atomic_commit_enabled`.
E uma sonda read-only invocada pelo fluxo `--reopen` de `feature-00c.md`
(FASE 3.2, task 3.2.1) **antes** de qualquer `init` de execucao nova — nesse
instante nao ha sessao de commit atomico corrente para herdar. A leitura de
`.atomic_commit_enabled` continua com fonte unica (`_cm_cmd_is_enabled`,
tarefa 3.5.1); `_cm_cmd_probe_pending_work` nao le nem escreve esse campo
(confirmado por `grep atomic_commit_enabled commit-mode.sh` — nenhuma
ocorrencia dentro da funcao). Ligar/desligar atomic-commit e responsabilidade
exclusiva do fluxo `--reopen`, nao desta sonda.

## Errors

| Exit | Condicao |
|------|----------|
| `2` | flag obrigatoria ausente; `--` ausente; `BRANCH` vazio; flag desconhecida |
| `3` | `git` ausente; `--projeto-alvo-path` nao e repo git; `BRANCH` inexistente |
| `1` | erro de IO/permissao nao coberto pelos casos acima |

## Invariantes de teste (extensao de `tests/test_commit-mode.sh`)

| ID | Invariante | Origem |
|----|------------|--------|
| T-50 | sonda com branch nao mesclada ⇒ reporta pendencia (`merged=no`) citando o comando em `source` | FR-021 |
| T-51 | `gh` ausente/nao autenticado ⇒ `probe_status=skipped-gh-*` e `pr_state=unknown` — **nunca** `pr_state=closed`/`merged=no` inferido da ausencia | FR-021, I-P1 |
| T-52 | branch com nome iniciado por `-` (ex.: `--force`) nao e consumida como flag — exige `--` antes do posicional | gate security (LOW) |
| T-53 | sonda nunca bloqueia: com `merged=no`/pendencia detectada, exit permanece `0` (o bloqueio e decisao da camada acima, nao desta sonda) | FR-021 |
