# Data Model: feature-reopen

Entidades do Phase 1. Esta feature **nao** introduz banco novo nem tabela nova:
tudo se apoia em estruturas ja existentes (estado transacional dos
orquestradores, layout de diretorio, `knowledge.db`). Onde um campo e novo, ele
esta marcado como tal e a Decision do `research.md` que o fundamenta e citada.

> Convencao de nomes: sintaxe em ingles (chaves de estado, labels de
> diretorio); textos e mensagens em portugues.

---

## Entity: Round

Uma rodada completa de trabalho sobre a feature. Materializa-se como diretorio
imutavel `<state-dir>/rounds/<label>/` contendo **apenas** o estado transacional
terminal daquela rodada.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `label` | string | `^r[0-9]{2,}$`, unico no state-dir | `r01`, `r02`, ... — Decision 3 |
| `path` | string | relativo ao state-dir | sempre `rounds/<label>` |
| `backend` | enum | `json` \| `sqlite` | derivado do arquivo presente |
| `state_file` | string | `state.json` \| `state.db` | um e somente um por round |
| `aux_files` | string[] | so backend `json` | `state.json.sha256`; sob `sqlite` e sempre vazio (Decision 2) |
| `execution_id` | string | herdado do estado preservado | `feat-<short>-<ts>`; discriminador na ingestao |
| `status` | enum | `concluida` \| `abortada` | estado terminal; `abortada` e legitimo (FR-020) |
| `finished_at` | timestamp ISO 8601 | NOT NULL | garantido pelo CHECK C2 do schema |

### Composicao do round por backend

Derivada da composicao real de state-dir observada no repo:

| Backend | Movido para o round | Deixado no state-dir |
|---------|---------------------|----------------------|
| `json` | `state.json`, `state.json.sha256` | `state-history/`, `backups/`, `feature-00c-report.md`, `.lock/`, `.gitignore` |
| `sqlite` | `state.db` (apos `PRAGMA wal_checkpoint(TRUNCATE)`) | idem + `commit-baseline.txt`, `mcp-server.json`, `tool-call-ticks.log`, `wave-agent-usage.jsonl`, `enforcement-log.jsonl` |

`state.db-wal` e `state.db-shm` **nao entram no round** e sao removidos do
state-dir apos o checkpoint (Decision 2) — e o que torna o round identico em
macOS e Ubuntu e fecha o GOTCHA da release v6.4.0.

### Invariantes

- **I-R1 (FR-007, SC-002)**: apos o commit da rotacao, nenhum arquivo sob
  `rounds/<label>/` e escrito de novo — por nenhum caminho do toolkit.
- **I-R2 (FR-009)**: `label` nunca e reutilizado; a numeracao so cresce.
- **I-R3**: exatamente um arquivo de estado por round (`state.json` XOR
  `state.db`) — nunca os dois.
- **I-R4 (FR-018)**: um round nunca e reportado como execucao ativa por
  nenhum leitor de estado.

### State Transitions

```
(inexistente) → staging → committed → (imutavel para sempre)
                   ↓
              rolled-back      (recover: arquivos devolvidos ao state-dir)
```

---

## Entity: RotationJournal

Registro de intencao que torna a rotacao recuperavel por comando (FR-011,
SC-006). Arquivo texto de vida curta em `<state-dir>/rounds/.rotate-journal`,
criado antes do primeiro movimento e removido depois do commit.

`[PROPOSTA — a validar na implementacao]` — formato `key=value`, uma chave por
linha, POSIX-parseavel sem `jq`:

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `label` | string | `^r[0-9]{2,}$` | round alvo da rotacao em curso |
| `backend` | enum | `json` \| `sqlite` | decide o conjunto de arquivos |
| `files` | string | lista separada por espaco | nomes relativos ao state-dir |
| `staging` | string | path relativo | `rounds/.<label>.staging` |
| `phase` | enum | `staged` \| `moving` | fase alcancada antes da interrupcao |
| `started_at` | timestamp ISO 8601 | NOT NULL | `date -u +%Y-%m-%dT%H:%M:%SZ` |

### Regras de parsing (obrigatorias — o roll-back e um `mv` destrutivo)

O `recover` move arquivos com base **no conteudo deste arquivo**. Um journal
corrompido ou plantado (`files=../../.ssh/id_rsa`, `staging=/etc`) transformaria
`recover` num `mv` arbitrario. Portanto:

| # | Regra |
|---|-------|
| J1 | Parser linha-a-linha proprio. **Nunca** `.`, `source` ou `eval` — mesmo padrao ja adotado por `state-backend.sh` para o config global |
| J2 | Allowlist de chaves: `label`, `backend`, `files`, `staging`, `phase`, `started_at`. Chave desconhecida ⇒ journal invalido, exit `1` |
| J3 | `label` MUST casar `^r[0-9]{2,}$` |
| J4 | Cada entrada de `files` MUST pertencer ao conjunto fechado `{state.json, state.json.sha256, state.db}`. Entrada com `/`, `..` ou iniciada por `-` ⇒ invalido |
| J5 | `staging` **nao e confiado**: e sempre **derivado** de `label` (`rounds/.<label>.staging`). O valor lido serve so para conferencia |
| J6 | O journal MUST ser arquivo regular e **nao-symlink** (`[ -f ]` e `! [ -L ]`) |
| J7 | `backend` ∈ `{json, sqlite}`; `phase` ∈ `{staged, moving}` |

Journal que viole qualquer regra ⇒ exit `1` com diagnostico, **sem mover nada**.
O operador resolve inspecionando o arquivo; nunca ha `mv` sobre valor nao
validado.

### Semantica de recuperacao

| Estado no disco | Diagnostico | Acao de `recover` |
|-----------------|-------------|-------------------|
| journal ausente | nenhuma rotacao pendente | no-op, exit 0 |
| journal presente, `rounds/<label>/` ja existe | commit ocorreu, journal orfao | roll-forward: remove o journal |
| journal presente, staging completo | interrompida antes do rename | roll-forward: renomeia staging → `<label>`, remove journal |
| journal presente, staging incompleto | interrompida no meio dos `mv` | roll-back: devolve arquivos ao state-dir, remove staging + journal |

O criterio de "staging completo" e a presenca de todos os nomes listados em
`files` dentro de `staging` — verificacao por `[ -f ]`, sem dependencia externa.

---

## Entity: ExecutionPointer (`.previous_round`)

Campo **novo** de topo no estado transacional da execucao nova (FR-008),
apontando para o round imediatamente anterior. Gravado sempre como objeto
inteiro (paths aninhados sao rejeitados pelo backend SQLite — Decision 4).

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `round` | string | `^r[0-9]{2,}$` | label do round anterior |
| `path` | string | relativo ao state-dir | `rounds/<label>` |
| `execution_id` | string | NOT NULL | `execution_id` preservado no round |
| `status` | enum | `concluida` \| `abortada` | como o round anterior terminou |
| `rotated_at` | timestamp ISO 8601 | NOT NULL | quando a rotacao foi consumada |

### Persistencia por backend

| Backend | Onde vive | Migracao necessaria? |
|---------|-----------|----------------------|
| `json` | chave de topo do documento | Nao |
| `sqlite` | `execution.extra_fields` (JSON catch-all), remontado no topo pelo `read` | **Nao** — verificado empiricamente (Decision 4) |

`schema_version` permanece `"1.0.0"` e imutavel: nenhuma coluna e adicionada.

### Relationships

- `Execucao corrente` 1:0..1 `Round` via `.previous_round.round`
- `Round[n]` encadeia com `Round[n-1]` pela ordem lexicografica dos labels —
  a cadeia completa e reconstruivel por `ls rounds/`, sem parsing numerico.

---

## Entity: ReopenTriage (Parecer de reabertura)

Veredito advisory apresentado ao operador antes de qualquer escrita (FR-004),
que se materializa em **duas** estruturas ja existentes: um `BloqueioHumano`
(a pergunta) e uma `Decisao` (o registro auditavel da resposta, FR-006).

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `recommendation` | enum | `reabrir` \| `abrir-feature-nova` | veredito do sistema |
| `rationale` | string | NOT NULL, cita pontos comparados | FR-004 exige a justificativa |
| `previous_status` | enum | `concluida` \| `abortada` | se `abortada`, o parecer MUST declarar que o round anterior nao chegou ao fim (FR-020) |
| `pending_work` | PendingWorkProbe | ver entidade abaixo | aviso informativo, nunca bloqueante (FR-021) |
| `operator_choice` | enum | `reabrir` \| `abortar-invocacao` | resposta humana |
| `diverged` | bool | derivado | `recommendation != operator_choice` |

### Ciclo de vida

```
gerado (em memoria, ANTES de escrita) → apresentado como BloqueioHumano
   → respondido pelo operador → [rotacao + init] → gravado como Decisao
```

A Decisao so pode ser gravada **depois** do `init`, porque FR-006 exige que ela
seja decisao "da execucao nova" — que ainda nao existe no instante do parecer
(Decision 10). O parecer trafega em memoria nesse intervalo.

### Mapeamento para a Decisao auditavel

| Campo da Decisao | Valor |
|------------------|-------|
| `contexto` | parecer + `rationale` + estado do round anterior |
| `opcoes` | `["reabrir","abrir-feature-nova"]` |
| `escolha` | `operator_choice` |
| `justificativa` | inclui `diverged` quando o operador contraria a recomendacao |
| `score` | fixo, sem heuristica — a decisao e humana, nao pontuada |

---

## Entity: PendingWorkProbe

Resultado da verificacao observavel de trabalho nao integrado do round anterior
(FR-021). **Cada campo carrega a fonte que o produziu** — ausencia de
verificacao nunca vira afirmacao de ausencia (Principio VI).

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `branch` | string \| null | — | branch associada avaliada |
| `default_branch` | string \| null | — | de `git symbolic-ref refs/remotes/origin/HEAD`; sem remote, `main`/`master` |
| `merged` | enum | `yes` \| `no` \| `unknown` | `unknown` quando git nao pode responder |
| `pr_state` | enum | `open` \| `closed` \| `merged` \| `unknown` | de `gh pr view --json url,state` |
| `pr_url` | string \| null | — | so quando `gh` respondeu |
| `source` | string | NOT NULL | comando literal que produziu cada afirmacao |
| `probe_status` | enum | `checked` \| `skipped-gh-missing` \| `skipped-gh-unauth` \| `skipped-no-git` | skip e nao-fatal |

### Invariante

- **I-P1 (Principio VI, FR-021)**: `merged=unknown` ou `pr_state=unknown`
  MUST ser reportado como **"nao verificado"**, jamais como "nao ha trabalho
  pendente". Ausencia de evidencia nao e evidencia de ausencia.

---

## Entity: KnowledgeIngestProvenance (extensao do `knowledge.db`)

Nao e entidade nova: e a extensao do campo de proveniencia ja existente para
distinguir rounds na reconstrucao do indice (FR-018, SC-003, Decision 5).
`[PROPOSTA — a validar na implementacao]`

| Origem do estado | `feature` | `wave` (linha de `executions`) | `wave` (decisoes/bloqueios/skills) |
|------------------|-----------|-------------------------------|------------------------------------|
| execucao viva (hoje) | `<short_name>` | `-` | `onda-NNN` |
| round preservado | `<short_name>` (inalterado) | `<label>` | `<label>/onda-NNN` |

### Por que o `feature` nao muda

As duas rodadas sao a **mesma** feature. Manter `feature` estavel e o que faz
"execucoes contadas para a feature == numero de rounds" (SC-003) ser verdade
sem que a feature apareca fatiada em N features distintas.

### Por que o `wave` precisa mudar

A chave de idempotencia da ingestao e `ON CONFLICT(project, feature, wave,
source_id)`. Sem namespace, `dec-001` do round `r01` e `dec-001` da execucao
viva colidem — um sobrescreve o outro e o historico das duas rodadas e
corrompido. A linha de `executions` nao colidiria (usa `source_id =
execution_id`, distinto por round), mas as demais colidiriam.

### Invariantes

- **I-K1 (SC-003)**: apos `--reindex`, `COUNT(*)` de execucoes de uma feature ==
  numero de rounds no disco (rounds preservados + execucao corrente).
- **I-K2 (FR-018)**: nenhum round preservado aparece com etapa ativa — a
  normalizacao existente ja mapeia `status == "concluida"` para
  `current_stage = "concluido"`; round `abortada` preserva o proprio status.
- **I-K3 (FR-010)**: rounds em `state.json` e em `state.db` produzem o mesmo
  numero de linhas — o que exige a varredura de `state.db` no `--reindex`
  (Decision 6), hoje inexistente.
