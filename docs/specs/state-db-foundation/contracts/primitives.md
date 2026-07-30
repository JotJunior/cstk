# Contract: Primitivas de acesso ao state.db (FR-004)

**Feature**: `state-db-foundation` | **Phase**: 1
**Status**: `[PROPOSTA — a validar na implementação]` para toda assinatura
marcada como NOVA. As assinaturas marcadas ATUAL foram extraídas por leitura
direta dos scripts em `global/skills/agente-00c-runtime/scripts/` e são fato
verificável, não proposta.

---

## Princípio do contrato: paridade de verbo, não reinvenção

FR-004 exige cobrir "os mesmos verbos que os orquestradores usam hoje em
todo caminho de escrita". A restrição de projeto que decorre disso:

> **A superfície de CLI não muda.** Os orquestradores (`agente-00c` e
> `feature-00c`) invocam os mesmos scripts, com os mesmos subcomandos e as
> mesmas flags. O que muda é o *backend* de persistência por trás deles.

Motivo: os arquivos de agente (`global/agents/agente-00c-orchestrator.md`,
`agente-00c-feature-orchestrator.md`) e os slash commands documentam essas
invocações literalmente, com flags exatas. Mudar a superfície obrigaria a
reescrever a prosa de todos eles — risco desproporcional para uma feature de
fundação, e fora do que a spec pede.

---

## Inventário da superfície ATUAL (a preservar)

Fonte: leitura direta dos scripts. Esta é a superfície que o backend
`state.db` deve honrar sem alteração observável.

### `state-rw.sh`

| Subcomando | Flags | Exit |
|---|---|---|
| `init` | `--state-dir` `--execucao-id` `--projeto-alvo-path` `--descricao` `--stack-json` `--whitelist-urls` `--short-name` `--briefing-path` `--briefing-sha256` `--constitution-path` `--constitution-sha256` `--constitution-version` `--key-aspects` `--canonical-project` `--session-name` `--atomic-commit` | 0/1/2 |
| `read` | `--state-dir` | 0/1/2 |
| `write` | `--state-dir` (JSON por stdin) | 0/1/2 |
| `get` | `--state-dir` `--field` | 0/1/2 |
| `set` | `--state-dir` `--field` `--value` | 0/1/2 |
| `sha256-update` | `--state-dir` | 0/1/2 |
| `sha256-verify` | `--state-dir` | 0/1/2 |
| `path-check` | `--projeto-alvo-path` `--create` | 0/1/2 |
| `infer-aspectos` | `--state-dir` `--projeto-alvo-path` | 0/1/2 |
| `migrate` | `--state-dir` | 0/1/2 |

Modo-feature ativado por `--short-name`, que torna obrigatórios
`--briefing-path`, `--briefing-sha256`, `--constitution-path`,
`--constitution-sha256`, `--constitution-version`. Modo-projeto exige
`--execucao-id`.

> **Colisão de nome a resolver**: `state-rw.sh` **já tem** um subcomando
> `migrate` (migração de schema interno do state.json). A migração
> `state.json → state.db` (FR-005) **não pode** reusar esse nome sem
> ambiguidade. Ver [migration.md](./migration.md) §Nomeação.

### `state-ondas.sh`

| Subcomando | Flags principais |
|---|---|
| `start` | `--state-dir` |
| `end` | `--state-dir` `--motivo-termino` `--proxima-agendada-para` `--next-instruction` `--add-etapa` (repetível) |
| `tool-call-tick` | `--state-dir` |
| `record-skill` | `--state-dir` `--skill` `--decisao-id` `--kind` (`skill`\|`gate`) |
| `record-task` | `--state-dir` `--task-id` `--titulo` `--wave-id` `--outcome` `--testes-rodados` `--testes-passados` `--lint-ok` `--arquivos` `--origem` `--if-absent` |
| `reconcile-tasks` | `--state-dir` `--tasks-md` `--wave-id` `--dry-run` |
| `wave-status` | `--state-dir` → stdout `none`\|`open`\|`closed` |
| `reconcile-wave` | `--state-dir` `--phase` `--tasks-md` `--terminal-phase` `--dry-run` |
| `current-id` | `--state-dir` → stdout `onda-NNN` |
| `git-commit` | `--state-dir` `--projeto-alvo-path` `--motivo` `--onda-id` |

`--motivo-termino` ∈ `etapa_concluida_avancando` \| `threshold_proxy_atingido`
\| `bloqueio_humano` \| `aborto` \| `concluido`.

### `state-decisions.sh`

| Subcomando | Flags |
|---|---|
| `register` | `--state-dir` `--agente` `--etapa` `--contexto` `--opcoes` `--escolha` `--justificativa` (7 obrigatórias) + `--score` `--evidencia` `--referencias` `--artefato-originador` |
| `count` | `--state-dir` `--agente` |
| `next-id` | `--state-dir` |
| `list` | `--state-dir` `--agente` `--etapa` |

`register` imprime o id novo (`dec-NNN`) em stdout.

### `bloqueios.sh`

| Subcomando | Flags |
|---|---|
| `register` | `--state-dir` `--decisao-id` `--pergunta` `--contexto-para-resposta` (4 obrigatórias) + `--opcoes-recomendadas` |
| `respond` | `--state-dir` `--block-id` `--resposta` |
| `list` | `--state-dir` `--status` |
| `count` | `--state-dir` `--pending-only` |
| `next-id` | `--state-dir` |
| `get` | `--state-dir` `--block-id` |

`register` imprime `block-NNN` em stdout e seta
`.execution.status = "aguardando_humano"`.

### `spawn-tracker.sh`

| Subcomando | Flags | Exit relevante |
|---|---|---|
| `check` | `--state-dir` | **3** = teto atingido |
| `enter` | `--state-dir` | **3** = teto atingido (não grava) |
| `leave` | `--state-dir` | idempotente em depth <= 1 |
| `current` | `--state-dir` | imprime depth |

Teto: `_ST_MAX=3`.

### `state-validate.sh` / `state-lock.sh`

`state-validate.sh` — sem subcomandos; `--state-dir`; exit 0 válido / 1
inválido / 2 uso. `state-lock.sh` — `acquire` \| `release` \| `check` \|
`check-execution-busy`, `--state-dir`; exit 3 = conflito.

---

## Contrato de comportamento sob backend `state.db`

### C1 — Compatibilidade de invocação (MUST)

Toda invocação listada acima produz, sob `state.db`, o **mesmo stdout, o
mesmo exit code e o mesmo efeito observável** que produz hoje sob
`state.json`. Isto inclui:

- `state-decisions.sh register` continua imprimindo `dec-NNN` em stdout —
  os orquestradores capturam esse valor em variável (`DEC_ID=$(…)`).
- `state-ondas.sh current-id` continua imprimindo `onda-NNN`.
- `state-ondas.sh wave-status` continua imprimindo exatamente
  `none`\|`open`\|`closed`.
- `bloqueios.sh count --pending-only` continua imprimindo um inteiro.
- `spawn-tracker.sh check` continua saindo **3** no teto.

### C2 — Seleção de backend (MUST)

Cada script resolve o backend na entrada, por presença de arquivo:

```
existe <state-dir>/state.db  ⇒ backend SQLite   (fonte de verdade)
senão                        ⇒ backend JSON      (comportamento atual, FR-012)
```

Por Decision 9 do research, um `state.db` **visível** é sempre completo e
verificado (a migração publica por rename atômico). Um `state.json`
coexistente é tratado como export/legado e **nunca** consultado como fonte.

### C3 — Semântica de erro nova, autorizada pelo FR-002 (MUST)

Constraints do banco criam falhas que hoje não existem. Elas MUST ser
reportadas com exit code convencional e mensagem em stderr, **nunca**
silenciadas:

| Situação | Constraint | Exit proposto |
|---|---|---|
| `start` com onda já aberta | `ux_wave_single_open` | **1** + stderr |
| `end` sobre onda já fechada | `trg_wave_close_once` | **1** + stderr |
| `register` de decisão com campo faltando | `CHECK` | 1 (paridade com hoje) |
| `bloqueios register` com `--decisao-id` inexistente | `FOREIGN KEY` | 1 (paridade com hoje) |
| `enter` acima do teto | `CHECK subagent_depth` | **3** (paridade com hoje) |

> **Mudança de comportamento a declarar explicitamente**: hoje
> `state-ondas.sh start` faz append cego e **duplica** a onda se chamado com
> onda aberta — é justamente por isso que o orquestrador carrega a guarda
> `wave-status` no passo 3.bis. Sob `state.db` a segunda chamada **falha**.
> Isso é uma melhoria (a duplicação era o bug), mas é observável: qualquer
> caminho que hoje dependa do append silencioso passa a receber erro. A
> guarda `wave-status` do orquestrador continua válida e vira defesa em
> profundidade, não requisito.

### C4 — Transacionalidade (MUST, FR-003)

Cada subcomando de escrita é **uma** transação `BEGIN IMMEDIATE; …; COMMIT;`.
Nenhum subcomando deixa escrita parcial. Subcomandos que hoje fazem múltiplas
mutações (ex.: `state-ondas.sh end`, que fecha a onda **e** atualiza
`.accumulated_metrics`; `bloqueios.sh register`, que grava o bloqueio **e**
muda `.execution.status`) passam a fazê-las na mesma transação — hoje são
sequências de escritas independentes, cada uma um RMW completo do arquivo.

### C5 — PRAGMAs obrigatórios por conexão (MUST)

Toda invocação de `sqlite3` sobre o `state.db` MUST emitir, antes do SQL:

```sql
PRAGMA foreign_keys = ON;    -- default é OFF; sem isto a FK é decorativa
PRAGMA busy_timeout = <ms>;  -- espera o escritor concorrente
```

`PRAGMA journal_mode = WAL` é aplicado **uma vez na criação** e persiste no
header do arquivo — não precisa ser reemitido por conexão.

### C6 — Concorrência (MUST, FR-011)

Leitores (`get`, `read`, `list`, `count`, `current-id`, `wave-status`) MUST
poder executar durante uma escrita em andamento, sem bloquear o escritor e
sem leitura parcial. Garantido por WAL. Escritores concorrentes são
serializados pelo banco; sob `database is locked` persistente após retries, a
operação MUST falhar com exit não-zero — **nunca** degradar silenciosamente
(diferença deliberada face ao `recall.sh`, cuja degradação silenciosa é
aceitável por ser índice derivado).

### C7 — Verificação de integridade (FR-010)

`sha256-update` / `sha256-verify` mantêm o nome e o contrato de exit code.
A implementação sob `state.db` passa a executar `PRAGMA integrity_check`.
**A cobertura de adulteração deliberada é decisão em aberto (D4-a do
research.md)** e MUST ser fechada antes da task que implementa FR-010 —
`integrity_check` sozinho não detecta edição externa bem-formada.

### C8 — Escape de texto livre em SQL (MUST) — A05/CWE-89

> Adicionado pelo gate de segurança da onda-004 (finding S1). Sem esta
> cláusula o contrato especificava constraints e transações mas **não** dizia
> como o texto entra no SQL — a omissão mais perigosa do desenho.

Todo valor de **texto livre** que entra numa string literal SQL MUST passar,
cumulativamente, por:

1. `strip_nul` — remoção de bytes NUL (o `sqlite3` trunca em NUL);
2. `sql_escape` — duplicação de aspa simples (`'` → `''`).

Ambos **já existem e estão testados** em `cli/lib/recall.sh`:

```sh
sql_escape() { printf '%s' "$1" | sed "s/'/''/g"; }
strip_nul()  { tr -d '\000'; }
```

MUST reusar esses helpers (extraindo-os para um ponto compartilhável), **não**
reimplementar. Campos afetados — todos de origem LLM ou de artefato lido:

| Campo | Origem |
|---|---|
| `decision.context` / `rationale` / `evidence` / `choice` | `--contexto` `--justificativa` `--evidencia` `--escolha` |
| `decision.options_considered` | `--opcoes` (JSON) |
| `human_block.question` / `context_for_answer` / `human_answer` | `--pergunta` `--contexto-para-resposta` `--resposta` |
| `task_outcome.title` / `touched_files` | `--titulo` `--arquivos` (paths do repo) |
| `event.description` | descrição do evento |
| `wave.termination_reason`, `executed_stages` | `--motivo-termino`, `--add-etapa` |
| `execution.target_project_description` | `--descricao` |

**Por que é MUST e não SHOULD**:

- O `sqlite3` CLI executa **múltiplos statements** separados por `;` a partir
  de stdin/heredoc. Uma aspa simples não escapada não causa só erro de
  sintaxe — permite terminar o literal e emendar comando arbitrário
  (`'; DROP TABLE decision; --`), incluindo `ATTACH`, que dá escrita em
  arquivo fora do banco.
- O escritor é um **agente LLM**, não um formulário: `--justificativa` e
  `--contexto` são prosa livre, e apóstrofo em português é rotineiro. A
  falha acidental é praticamente certa sem escape.
- Vetor deliberado real (LLM01/ASI06): texto de artefato lido pelo agente
  (spec, doc do projeto, saída de skill) pode chegar a `--contexto`. O
  próprio runtime já trata artefato lido como **conteúdo não-confiável**.

**Alternativa preferível quando disponível**: parâmetros nomeados do
`sqlite3` (`.param set`) em vez de interpolação. **DECISÃO EM ABERTO
(C8-a)**: verificar disponibilidade de `.param` na versão mínima suportada;
se indisponível, `strip_nul` + `sql_escape` é o piso obrigatório.

**Teste obrigatório**: registrar decisão cujo `--justificativa` contenha
`'; DROP TABLE decision; --` e apóstrofo simples; verificar que (a) o texto
é persistido **literalmente**, (b) a tabela `decision` continua existindo,
(c) `state-validate.sh` sai 0. Paridade com o teste que
`tests/test_model-routing.sh` já faz para o mesmo payload.

### C9 — Permissões de arquivo (MUST) — finding S3

O `state.db` e seus sidecars WAL (`state.db-wal`, `state.db-shm`) e o export
MUST ser criados com modo `0600`, por `chmod` **explícito** após a criação.

**Fato verificado**: hoje o `state.json` está em `0600`, mas **não há
nenhum `chmod` no runtime de estado** — a única chamada `chmod 600` em todo
`agente-00c-runtime/scripts/` está em `otel-usage.sh:262`. O `0600` atual é,
portanto, **ambiente** (herdado do umask do processo que criou), não
imposto: sob `umask 022` (o valor do shell do operador) um arquivo novo
nasceria `0644`.

Trocar 1 arquivo por 3 (banco + 2 sidecars) triplica a superfície desse
acidente — e o `-wal` contém as transações mais recentes em claro. Logo o
`chmod` explícito deixa de ser detalhe e vira requisito, seguindo o padrão
que `otel-usage.sh` já aplica.

### C10 — Arquivo temporário da migração (MUST) — finding S5

O temporário de [migration.md](./migration.md) §M2 MUST ser criado por
`mktemp` no diretório de destino, **não** por nome previsível derivado de
PID (`.state.db.tmp.$$`). Nome previsível em diretório onde outro processo
escreve é vetor clássico de symlink/TOCTOU. `mktemp` preserva a propriedade
essencial (mesmo filesystem ⇒ `mv` atômico).

### C11 — O que NÃO muda (MUST NOT)

- `state-lock.sh` **não é removido** e sua superfície não muda. Deixa de ser
  requisito de serialização (FR-011), vira camada opcional.
- `path-check` e `infer-aspectos` (`state-rw.sh`) não tocam estado
  transacional — permanecem idênticos.
- Nenhum script passa a escrever no `knowledge.db` (FR-009).
