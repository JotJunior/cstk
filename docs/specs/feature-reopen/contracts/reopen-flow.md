# Contract: modo de reabertura do `/feature-00c`

**Status**: fluxo `[PROPOSTA — a validar na implementacao]`, construido sobre
pre-flight **existente**. Cada elemento marcado *(existente)* foi lido em
`plugins/cstk/commands/feature-00c.md`; os marcados *(novo)* sao desenho.

**Path**: `plugins/cstk/commands/feature-00c.md`

## Invocacao *(novo)*

```
/feature-00c --reopen <short-name> "<descricao do incremento>"
```

`/agente-00c` e seus resumes **nao sao tocados** (FR-019).

---

## Ordem de execucao

A ordem e normativa: **toda recusa acontece antes de qualquer escrita em disco**
(FR-002, FR-004, Decision 7).

```
 1..5  pre-flight existente          (path-guard, sanitize, briefing,
                                      constitution, coexistencia agente-00c)
 6     ramo de reabertura            (novo — substitui/estende o item 6 atual)
 6.a   pre-condicoes de recusa       [NENHUMA ESCRITA ATE AQUI]
 6.b   sonda de trabalho pendente
 6.c   parecer + bloqueio humano     [aguarda operador]
 7     lock (acquire)                [primeira escrita possivel]
 7.a   re-verificacao pos-lock       (fecha TOCTOU)
 7.b   state-rounds.sh recover       (limbo pendente?)
 7.c   state-rounds.sh rotate        [ponto de commit da rotacao]
 7.d   restauracao de spec arquivada (se aplicavel)
 8     diagnostico de consumo        (existente)
 3'    state-rw.sh init              (execucao nova, limpa)
 3''   grava .previous_round + Decisao do parecer
```

### Passo 6.a — pre-condicoes de recusa *(novo)*

| # | Verificacao | Falha ⇒ |
|---|-------------|---------|
| 1 | `<state-dir>` existe **e** contem `state.json` ou `state.db` **na raiz** | **exit 4** — sem execucao anterior (FR-002) |
| 1b | Se a raiz esta vazia mas ha `rounds/<label>/` com estado: feature ja reaberta e com rotacao **consumada** sem `init` — nao e caso de recusa; ver tabela de conciliacao abaixo | — |
| 2 | `state-lock.sh check-execution-busy --state-dir <SD>` *(existente)* | exit `3` ⇒ **exit 5** — execucao viva (FR-003) |

Nenhuma das duas cria arquivo. A verificacao 1 e `[ -d ]`/`[ -f ]` puro; a 2 e
read-only e ja distingue exatamente o que FR-003 e FR-020 precisam: exit `0`
para `''`/`abortada`/`concluida`, exit `3` para
`em_andamento`/`aguardando_humano`.

**Mensagem da recusa 1 (FR-002)** deve apontar a abertura normal:
`/feature-00c <short-name> "<descricao>"`.
**Mensagem da recusa 2 (FR-003)** deve apontar `/feature-00c-resume` e
`/feature-00c-abort` — comandos do **escopo de feature** (FR-017).

### Passo 6.b — sonda de trabalho pendente *(novo)*

Delegada a `commit-mode.sh` para preservar o confinamento de `gh` exigido pelo
carve-out 1.1.0 (Decision 9). Resultado e **informativo**: nunca bloqueia
(FR-021). `probe_status` de skip vira "nao verificado", jamais "sem pendencia".

### Passo 6.c — parecer + bloqueio humano *(novo)*

Emitido **antes** de qualquer escrita (FR-004, literal). Conteudo obrigatorio:

| Elemento | Fonte | Requisito |
|----------|-------|-----------|
| recomendacao (`reabrir` \| `abrir-feature-nova`) | comparacao pedido × spec | FR-004 |
| justificativa citando os pontos comparados | idem | FR-004 |
| declaracao de que o round anterior **nao chegou ao fim** | `status == abortada` | FR-020 |
| aviso de trabalho pendente + fonte checada | passo 6.b | FR-021 |
| aviso de que a spec sera restaurada do arquivo | passo 7.d | FR-013 |

O operador confirma explicitamente. Escolha contraria a recomendacao
**prossegue** (FR-005). O sistema **nao** cria a feature nova por conta propria
quando recomenda `abrir-feature-nova` — apenas instrui como faze-lo (FR-005).

### Passo 7.c — rotacao

`state-rounds.sh rotate --state-dir <SD>` (ver `contracts/state-rounds.md`).
O lock permanece detido do passo 7 ate o Cleanup, cobrindo a rotacao inteira
(FR-012, decisao do clarify).

### Passo 7.d — restauracao de spec arquivada *(novo)*

Dispara quando `docs/specs/<short>/spec.md` **nao** existe e ha diretorio
arquivado (Decision 8):

| Ordem | Origem tentada |
|-------|----------------|
| 1 | `docs/specs/_archived/<short>/` |
| 2 | `docs/specs/_archived/<YYYY-MM-DD>-<short>/` — maior data vence |

Copia recursiva para `docs/specs/<short>/`; **origem permanece intacta**
(FR-013). `docs/specs/<short>/` ja existente e nao-vazio ⇒ nao sobrescreve (o
disco vence). O operador e informado do que foi restaurado e de onde (FR-013).

### Passo 3' — init da execucao nova *(existente, com 1 flag derivada)*

Invocacao **identica** a atual do `feature-00c.md`, com uma unica diferenca:
`--atomic-commit` recebe o valor **herdado** do round anterior, sem
re-perguntar (FR-022):

```sh
state-rw.sh init --state-dir "$AGENTE_00C_STATE_DIR" \
  --short-name "$SHORT" \
  --projeto-alvo-path "$_proj" \
  --descricao "$_desc" \
  --briefing-path "$_br" --briefing-sha256 "$_br_sha" \
  --constitution-path "$_ct" --constitution-sha256 "$_ct_sha" \
  --constitution-version "$_ct_ver" \
  --key-aspects "$_aspectos" \
  ${_canonical:+--canonical-project "$_canonical"} \
  ${_session:+--session-name "$_session"} \
  --atomic-commit "$_atomic_herdado"
```

`_atomic_herdado` e lido do estado terminal **antes** da rotacao; ausencia ou
leitura falha ⇒ `false` (FR-022). O literal deve ser exatamente `true`/`false`:
qualquer outro valor faz `init` sair `2`
(`init: --atomic-commit aceita apenas 'true' ou 'false'`).

Nenhum `--force` e necessario nem existe: apos a rotacao a raiz do state-dir nao
tem mais `state.json`/`state.db`, e as guardas das L411-418 nao disparam.

### Passo 3'' — ponteiro e Decisao *(novo)*

```sh
state-rw.sh set --state-dir "$SD" --field '.previous_round' --value '<json>'
```

Objeto **inteiro** (path aninhado e rejeitado sob SQLite — Decision 4).
Em seguida, a Decisao do parecer (FR-006) via `state-decisions.sh register`,
com `escolha` = decisao do operador e a divergencia explicitada quando houver.

---

## Correcao do item 6 do pre-flight (FR-016, FR-017)

Estado atual *(existente, `feature-00c.md` L134-141)* — a opcao (a) e
inalcancavel porque o `init` morre logo depois, e a mensagem cita comandos do
escopo de projeto:

```
6. feature pre-existente (FR-006):
   _spec="$_proj/docs/specs/$SHORT/spec.md"
   if [ -f "$_spec" ] && [ -s "$_spec" ]; then
     - apresentar bloqueio humano in-band com 2 opcoes:
       (a) retomar a partir da spec existente (entra direto em clarify)
       (b) abortar a invocacao
```

Duas correcoes obrigatorias:

1. **FR-016** — a opcao (a) MUST levar a uma execucao de fato. Quando existe
   estado terminal, (a) passa a acionar o fluxo de reabertura acima. Nenhuma
   opcao oferecida pode terminar em aborto do proprio fluxo que a ofereceu
   (SC-007).
2. **FR-017** — o item 6 hoje so testa `spec.md`; MUST tambem detectar
   **state-dir com estado terminal** (o caso mais comum no repo: spec arquivada,
   estado no lugar — que hoje nao dispara aviso nenhum). A mensagem MUST citar
   `/feature-00c --reopen`, `/feature-00c-resume` e `/feature-00c-abort` —
   comandos do escopo de **feature**, nunca `/agente-00c-*`.

A mensagem de `state-rw.sh init` *(existente)* que cita o escopo errado
(`init: state.json ja existe em $_sd. Use /agente-00c-abort ou
/agente-00c-resume.`) deixa de ser alcancavel pelo caminho de reabertura, mas
**permanece incorreta para o modo feature**. Corrigi-la exige distinguir os dois
modos dentro do `init` — registrado como item de escopo em `plan.md`.

---

## Exit codes do modo `--reopen` *(novo)*

Estende a numeracao ja usada pelo pre-flight *(existente: `1` validacao,
`2` coexistencia, `3` lock ocupado)*:

| Exit | Condicao | FR |
|------|----------|-----|
| `0` | reabertura consumada, ou operador escolheu abortar apos o parecer | — |
| `1` | falha de validacao do pre-flight (itens 1..5) | *(existente)* |
| `2` | coexistencia com `agente-00c` ativa | *(existente)* |
| `3` | lock por short-name ocupado | *(existente)* |
| `4` | short-name sem execucao anterior — usar abertura normal | FR-002 |
| `5` | execucao anterior nao-terminal — usar resume/abort | FR-003 |
| `6` | rotacao pendente irrecuperavel automaticamente — produzido quando o passo 7.b (`state-rounds.sh recover`) sai `1` (journal invalido pelas regras J1..J7, ou `mv` de recuperacao falhou). Exercitado por T-36 | FR-011 |

Exit `0` para "operador abortou apos o parecer" e deliberado: o fluxo fez
exatamente o que devia (consultou e obedeceu), e nada foi escrito.

---

## Invariantes de teste

| ID | Invariante | Origem |
|----|------------|--------|
| T-20 | `--reopen` de short-name inexistente ⇒ exit `4` e **zero** arquivos criados (state-dir nao passa a existir) | FR-002 |
| T-21 | `--reopen` com execucao `em_andamento` ⇒ exit `5`, estado vivo byte-identico | FR-003 |
| T-22 | `--reopen` com execucao `aguardando_humano` ⇒ exit `5` | FR-003 |
| T-23 | parecer emitido antes de qualquer escrita (nenhum inode novo ate a confirmacao) | FR-004 |
| T-24 | operador contraria a recomendacao ⇒ prossegue e `diverged=true` na Decisao | FR-005, FR-006 |
| T-25 | recomendacao `abrir-feature-nova` **nao** cria feature nova | FR-005 |
| T-26 | round anterior `abortada` ⇒ parecer declara que nao chegou ao fim | FR-020 |
| T-27 | `.previous_round` legivel via `get` nos dois backends | FR-008, FR-010 |
| T-28 | `atomic_commit_enabled` herdado sem prompt; ausencia ⇒ `false` | FR-022 |
| T-29 | spec arquivada restaurada; `_archived/` intacto (`cmp -r`) | FR-013 |
| T-30 | spec ativa pre-existente nao e sobrescrita pela restauracao | Edge Case |
| T-31 | lock detido continuamente do passo 7 ate o Cleanup | FR-012 |
| T-32 | segunda sessao concorrente ⇒ exit `3`, sem tocar a rotacao em curso | FR-012 |
| T-33 | item 6 detecta state-dir terminal com spec arquivada e cita comandos de feature | FR-016, FR-017 |
| T-34 | nenhuma opcao oferecida termina em aborto do proprio fluxo | SC-007 |
| T-35 | backend da execucao nova segue a config global corrente (mecanismo ja existente de `init`), independente do backend do round anterior — sem heranca, sem flag `--backend` | FR-010, Decision 14 |
| T-36 | `recover` exit `1` (journal invalido) ⇒ fluxo sai `6` sem rotacionar | FR-011 |
| T-37 | raiz sem estado mas com `rounds/<label>/` presente ⇒ conciliado, **nao** recusado com exit 4 | coerencia 6.a × `rotate` |

### Conciliacao raiz-vazia × `rounds/` presente

`state-rounds.sh rotate` exige estado **na raiz** (pre-condicao 1, exit `3`).
Um state-dir com estado apenas sob `rounds/` significa que uma rotacao anterior
foi consumada mas o `init` nao chegou a rodar — limbo legitimo, coberto por
FR-011. Tratamento: **pular** o passo 7.c (nao ha o que rotacionar) e seguir
direto para o `init` (passo 3'), com `.previous_round` apontando para o maior
label existente. Nunca exit `4`: a feature **tem** execucao anterior — ela so
esta preservada.
