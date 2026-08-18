# Data Model: roadmap-parallel-launch

**Feature**: `roadmap-parallel-launch`
**Status**: `[PROPOSTA — a validar na implementacao]` (exceto onde marcado **REAL**)

> **Nenhum estado persistido novo.** A spec e explicita: "nao ha scheduler nem
> estado persistido alem do ja existente em `docs/roadmap.md` e nas pastas de
> spec por feature". As entidades abaixo sao **estruturas em memoria** de um
> unico ciclo de oferta, ou identidades derivadas de fontes existentes. Nao ha
> tabela, migracao, arquivo de estado ou schema novo.

---

## Entity: EntradaDeRoadmap (**REAL** — ja existe)

Unidade emitida por `roadmap-status.sh --json`. Fonte literal:
`plugins/cstk/skills/review-features/scripts/roadmap-status.sh:200-201`.

| Campo | Tipo | Notas |
|---|---|---|
| `ordem` | inteiro >= 1 | posicao no roadmap; `ordem(dep) < ordem(entrada)` (§3.3 do contrato de roadmap) |
| `short_name` | string | validado fail-closed contra `^[a-z][a-z0-9-]*$`, <= 64 chars |
| `status` | enum | `nao-iniciada` \| `em-andamento` \| `concluida` |
| `depende_de` | array de string | short-names; `-` literal no artefato vira array vazio |

**Derivacao de `status`** (§5 de `roadmap-mode/contracts/roadmap-artifact.md`,
contra `docs/specs/<short_name>/`):

| Condicao | status |
|---|---|
| diretorio nao existe | `nao-iniciada` |
| diretorio existe, `tasks.md` ausente | `em-andamento` |
| `tasks.md` com >= 1 linha `- [ ]` / `- [~]` | `em-andamento` |
| `tasks.md` sem linha pendente | `concluida` |

Nunca ha campo `status` dentro de `docs/roadmap.md` (proibido pela §2.2).

---

## Entity: Fronteira `[PROPOSTA]`

Subconjunto de `EntradaDeRoadmap`, recalculado a cada ciclo. Nao persistido.

| Campo | Tipo | Notas |
|---|---|---|
| `candidatas` | lista de `EntradaDeRoadmap` | apenas as elegiveis |
| `avisos` | lista de `AvisoDeSobreposicao` | pode ser vazia |

**Predicado de elegibilidade** (FR-001 + FR-010):

```
elegivel(E) := E.status == "nao-iniciada"
               AND para todo d em E.depende_de:
                     existe D com D.short_name == d AND D.status == "concluida"
```

Filtro adicional (FR-011): remove `E` cujo `short_name` ja tem worktree ativa.

**Transicoes observaveis** (nao ha maquina de estado propria — a transicao e
consequencia da mudanca de `status` da fonte):

```
nao-elegivel --(dependencia passa a "concluida")--> elegivel
elegivel     --(feature e lancada; dir de spec criado)--> nao-elegivel (em-andamento)
elegivel     --(worktree ativa detectada)--> excluida da leva (FR-011)
```

Termino nao-concluido (abortado / bloqueio humano) deixa `tasks.md` com linha
pendente => `em-andamento` => dependentes permanecem nao-elegiveis. **FR-010 e
consequencia da derivacao, nao de logica adicional.**

---

## Entity: Leva `[PROPOSTA]`

Lote de features lancadas numa rodada. Vive apenas durante a oferta.

| Campo | Tipo | Notas |
|---|---|---|
| `teto` | inteiro >= 1 | **default 2** quando o operador nao especifica (FR-003, clarify Q1) |
| `escolhidas` | lista de short-name | `length <= teto`; `length <= length(candidatas)` |

Teto maior que o numero de candidatas => lanca todas, sem exigir atingir o
teto (edge case declarado na spec).

---

## Entity: SessaoCoordenadora `[PROPOSTA]`

| Campo | Tipo | Origem |
|---|---|---|
| `nome` | string | `cstk-coord/<nome-do-repo>`, atribuido por `claude --name` (**REAL**: `claude --help`, `-n, --name <name>`) |
| `repo_path` | path | repo principal onde `/agente-00c` rodou |

Sem nome atribuido => nao ha endereco para a notificacao; a degradacao MUST
ser informada no lancamento (`contracts/parallel-launch.md` §5).

---

## Entity: SessaoFilha `[PROPOSTA]`

| Campo | Tipo | Origem |
|---|---|---|
| `short_name` | string | feature atribuida |
| `nome` | string | `cstk-feature/<short_name>` via `claude --name` |
| `worktree` | path | `<pai-do-repo>/<nome-do-repo>-<short_name>` (**REAL**: `cli/lib/session.sh:243`) |
| `branch` | string | `<short_name>` (criada por `cstk session start`) |
| `pane_id` | string | capturado por `tmux new-window -P -F '#{pane_id}'` (**REAL**: `tmux list-commands`); ausente no caminho degradado |

Ciclo de vida:

```
criada (cstk session start) --> executando (/feature-00c) --> terminal --> notifica (best-effort)
                                                          \-> morta abruptamente --> sem notificacao (via manual, FR-013)
```

---

## Entity: NotificacaoDeConclusao `[PROPOSTA]`

Texto plano — o mecanismo (`SendMessage`) transporta texto, nao objeto.

| Campo | Tipo | Valores |
|---|---|---|
| `feature` | string | short-name da filha |
| `outcome` | enum | `concluida` \| `abortada` \| `aguardando_humano` — valores VERBATIM de `.execution.status` (**REAL**: `state-validate.sh:250`, conjunto `em_andamento\|aguardando_humano\|abortada\|concluida`). Nao existe status `bloqueio_humano` (esse e motivo de termino de ONDA) nem `pausada`. |
| `repo` | string | nome do repo coordenador |

Forma: `[cstk-parallel] feature=<SHORT> outcome=<...> repo=<...>`

Canal nao autenticado: o receptor casa a mensagem inteira por regex ancorada
e a trata como gatilho opaco, nunca como instrucao
(`contracts/parallel-launch.md` §6).

Propriedades duras: imediata (sem intervalo/timeout — clarify Q5) e
best-effort (falha nao altera o ciclo de vida da filha — FR-015).

---

## Entity: AvisoDeSobreposicao `[PROPOSTA]`

| Campo | Tipo | Notas |
|---|---|---|
| `par` | tupla de 2 short-names | candidatas da MESMA leva |
| `tokens` | lista de string | tokens de artefato mencionados por ambas |

Derivado do bloco de prosa das entradas de `docs/roadmap.md` (§3.4 do contrato
de roadmap) — unica fonte disponivel para candidata `nao-iniciada`, cujo
diretorio de spec por definicao nao existe.

**Restricao de redacao (Principio VI)**: renderizado como indicio ("as
entradas X e Y mencionam ambas Z"), NUNCA como afirmacao de conflito.
Informativo, jamais bloqueante (AC3 da US4).
