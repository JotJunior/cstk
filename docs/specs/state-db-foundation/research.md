# Research: Fundação state.db

**Feature**: `state-db-foundation` | **Date**: 2026-07-30 | **Phase**: 0
**Spec**: [spec.md](./spec.md)

> Todo identificador (subcomando, flag, campo, tabela, coluna, exit code)
> citado abaixo foi extraído por leitura direta das fontes reais do repo e
> tem o arquivo/linha indicado. Onde a decisão ainda não está fechada, o
> item aparece explicitamente como **DECISÃO EM ABERTO**, nunca como fato.
> (Constitution VI — Veracidade de Dados.)

---

## Decision 1 — Mecanismo de acesso ao SQLite: CLI `sqlite3` via POSIX sh

**Decision**: A camada de estado acessa o `state.db` invocando o binário
`sqlite3` a partir de scripts POSIX sh, alimentando-o com SQL por heredoc/
stdin — sem driver nativo, sem binding de linguagem, sem ORM.

**Rationale**:

- O toolkit não tem runtime de linguagem próprio: todo o runtime de estado
  é POSIX sh (`global/skills/agente-00c-runtime/scripts/*.sh`). Introduzir
  um driver exigiria introduzir uma linguagem hospedeira — mudança de
  ordem de grandeza maior que esta feature.
- **Precedente real e verificável no próprio repo**: `cli/lib/recall.sh`
  já opera um banco SQLite (`~/.claude/cstk/knowledge.db`, 12 tabelas +
  FTS5) inteiramente por CLI `sqlite3` a partir de POSIX sh, incluindo
  transações (`BEGIN; … COMMIT;` por arquivo ingerido) e retry sob lock
  (`recall_apply_sql_with_retry`, até 4 tentativas com backoff
  PID-jitterado sobre `database is locked`/`database is busy`).
- Ambiente de desenvolvimento confirmado: `sqlite3` presente em
  `/usr/bin/sqlite3`, versão `3.51.0` (macOS). WAL exige SQLite >= 3.7.0
  (2010), logo não há risco de versão nesse aspecto.

**Alternatives considered**:

- *Driver nativo (better-sqlite3 / node:sqlite / python sqlite3)*:
  rejeitado — introduz runtime de linguagem no caminho crítico do estado,
  contra a arquitetura POSIX sh do runtime. (O read-back loop recuperou uma
  decisão análoga de outro projeto — `gamedev-training/onda-012`, escolha
  `better-sqlite3` — mas aquele projeto **já era** Node; o critério que a
  motivou não transfere para cá.)
- *Manter JSON + lock mais rigoroso*: rejeitado — não resolve FR-002
  (invariantes na camada de armazenamento) nem FR-011 (leitores
  concorrentes não-bloqueados); apenas endurece o mecanismo que a spec
  identifica como frágil.

---

## Decision 2 — Concorrência: WAL como mecanismo primário

**Decision**: `PRAGMA journal_mode=WAL` no `state.db`, aplicado uma vez na
criação do banco. Leitores não bloqueiam o escritor e o escritor não
bloqueia leitores. Complementos obrigatórios: `PRAGMA busy_timeout` (espera
o escritor concorrente em vez de falhar imediatamente com `SQLITE_BUSY`) e
`PRAGMA foreign_keys=ON` (ver Decision 5).

**Rationale**: pré-decidido pelo operador no clarify — `dec-014`, resposta
ao `block-001`, registrada em [spec.md](./spec.md) §Clarifications Session
2026-07-30. O `journal_mode` é persistente no header do arquivo do banco:
setar uma vez na criação basta, não precisa ser reaplicado a cada conexão
(diferente de `busy_timeout` e `foreign_keys`, que são **por conexão** e
portanto precisam ser emitidos em toda invocação de `sqlite3`).

**Consequências assumidas**:

- O lock de diretório atual (`state-lock.sh`, `mkdir` de `<state-dir>/.lock`,
  exit 3 em contenção) **deixa de ser requisito** para serialização de
  escritores e para leitores. Permanece disponível como camada extra
  opcional (spec FR-011).
- WAL cria arquivos sidecar `state.db-wal` e `state.db-shm` junto ao banco.
  Consequência operacional: cópia de arquivo do `state.db` isolado **não é**
  um backup válido — daí o backup ser feito por export serializado
  (Decision 6 / FR-013-INFRA-BACKUP), não por `cp`.
- WAL pressupõe filesystem local com shared-memory funcional; não é
  confiável sobre NFS. **Aceito**: o estado 00c já vive em
  `<projeto-alvo>/.claude/`, isto é, dentro do repositório de trabalho local.

---

## Decision 3 — Atomicidade: uma transação `BEGIN IMMEDIATE` por mutação

**Decision**: cada mutação de estado (as do FR-004) é uma única invocação
de `sqlite3` contendo `BEGIN IMMEDIATE; …; COMMIT;`. A mutação inteira
aplica ou não deixa rastro (FR-003).

**Rationale**:

- `BEGIN IMMEDIATE` adquire o write-lock na abertura da transação, em vez
  de tentar promover um lock de leitura para escrita no meio dela. Isso
  elimina a classe de falha em que duas transações deferred leem, tentam
  escrever e uma recebe `SQLITE_BUSY` sem possibilidade de retry seguro —
  exatamente o modo de falha que o RMW do `state.json` sofre hoje.
- Uma invocação por mutação = um processo `sqlite3` por mutação. O custo é
  aceitável: a frequência de mutação de estado é de ordem dezenas por onda,
  não milhares por segundo.
- Combinado com `busy_timeout`, o segundo escritor espera em vez de falhar.

**Retry**: reaproveitar o padrão já implementado e testado em
`cli/lib/recall.sh` (`recall_apply_sql_with_retry`) em vez de inventar um
novo — mesma classe de erro (`database is locked` / `database is busy` /
`locking protocol`), mesmo backoff jitterado.

**Diferença de contrato face ao recall**: no `recall.sh` a degradação sob
lock persistente é **pular a ingestão e sair 0** (o índice é derivado e
reconstruível). No `state.db` isso é **inaceitável** — é a fonte de verdade;
lock persistente após retries MUST falhar com exit não-zero, nunca degradar
silenciosamente.

---

## Decision 4 — Verificação de integridade (FR-010): o que muda face ao sha256

**Decision**: a operação de verificação passa a ser
`PRAGMA integrity_check` (ou `quick_check` no caminho quente) sobre o
`state.db`, substituindo a comparação de hash do arquivo.

**Como funciona hoje** (fonte: `state-rw.sh`, subcomandos `sha256-update` /
`sha256-verify`): calcula-se o SHA-256 do arquivo `<state-dir>/state.json`
inteiro via `sha256sum` com fallback para `shasum -a 256`, e guarda-se o
hex puro num arquivo sidecar `<state-dir>/state.json.sha256` (**não** é um
campo dentro do JSON). `sha256-verify` compara e sai 1 em divergência.

**Limitação que precisa ser dita com honestidade**: `integrity_check` e
`sha256-verify` **não detectam a mesma coisa**.

| Ameaça | `sha256-verify` (hoje) | `PRAGMA integrity_check` |
|---|---|---|
| Corrupção estrutural (disco, escrita parcial) | detecta | detecta |
| Edição externa bem-formada (adulteração deliberada) | **detecta** | **NÃO detecta** |

Um `UPDATE` manual via `sqlite3` num `state.db` produz um banco
estruturalmente perfeito — `integrity_check` retorna `ok`. O sha256 do
arquivo JSON, ao contrário, muda com qualquer edição. Ou seja: trocar sha256
por `integrity_check` **fecha** o requisito de corrupção e **abre um
regresso** no requisito de adulteração, que o FR-010 menciona
explicitamente ("corrupção/adulteração silenciosa").

Nota: o sha256 de hoje já é uma defesa parcial — quem adultera o
`state.json` pode recomputar o sidecar `.sha256`, já que a chave não é
secreta. Ele detecta adulteração *descuidada*, não adulteração informada.

**DECISÃO FECHADA (D4-a)** — opção **1: `integrity_check` apenas**, aceitando
o regresso documentado acima. Resolvida pelo operador humano em resposta ao
bloqueio `block-002` (finding S2 do gate `owasp-security`, onda-004),
registrada como `dec-025`. Opções que estavam em avaliação:

1. **[ESCOLHIDA]** `integrity_check` apenas, aceitando o regresso e
   documentando-o (registra que o modelo de ameaça do toolkit é operador
   local confiável).
2. `integrity_check` + hash-chain append-only sobre a tabela de decisões
   (cada linha carrega o hash da anterior) — detecta remoção/reescrita de
   rastro de auditoria, que é o ativo que o Princípio I protege.
3. `integrity_check` + sha256 do **export** `state.json` (FR-007),
   preservando literalmente o mecanismo atual sobre o artefato derivado.

**Justificativa do operador**: o sha256 atual já é defesa parcial — quem
adultera o `state.json` pode recomputar o sidecar `.sha256`, já que a chave
não é secreta; ele detecta adulteração *descuidada*, não *informada*. O
modelo de ameaça assumido para esta feature é operador local confiável, o
que torna as opções 2/3 (custo adicional de hash-chain ou de manter dois
mecanismos de verificação) desproporcionais ao ativo protegido nesta fase.
`FR-010` passa a ser implementado apenas com `PRAGMA integrity_check` (ou
`quick_check`), sem cobertura adicional de adulteração bem-formada — o
regresso é aceito e documentado, não silenciado.

---

## Decision 5 — Invariantes do FR-002 dentro do banco, não na prosa

**Decision**: as cinco invariantes citadas no FR-002 são expressas como
constraints declarativas (`CHECK`, `UNIQUE` parcial, `FOREIGN KEY`,
`TRIGGER` onde constraint não alcança) — detalhadas em
[data-model.md](./data-model.md).

**Rationale**: hoje essas regras existem em dois lugares, ambos
não-declarativos e verificáveis só *a posteriori*:

- `state-validate.sh` — script de checagem única (sem subcomandos) que
  reprova depois do fato: valida `.schema_version == "1.0.0"`, tipos dos
  campos obrigatórios, consistência `status` × `finished_at`,
  `.budgets.current_subagent_depth <= 3`,
  `.budgets.cycles_consumed_current_stage <= 5`,
  `.budgets.retro_executions_consumed <= 2`, os 5 campos não-vazios de cada
  decisão (`context`, `options_considered`, `choice`, `rationale`, `agent`)
  e a referência de cada bloqueio humano a uma decisão existente.
- Validação imperativa espalhada nos scripts de escrita — ex.:
  `state-decisions.sh register` exige `--contexto` e `--justificativa` com
  >= 20 bytes e rejeita `--score 3` sem `--evidencia` de >= 20 chars;
  `bloqueios.sh register` checa a existência do `--decisao-id` via
  `_bl_decisao_exists` antes de gravar.

O ponto do FR-002 é que essas garantias passem a ser **impossíveis de
contornar** por um chamador que esqueça a checagem — inclusive um agente
autônomo escrevendo direto. `PRAGMA foreign_keys=ON` é obrigatório por
conexão (SQLite desliga FK por default) — se esquecido, a FK de bloqueio→
decisão vira decorativa.

**Alternative rejeitada**: manter as invariantes só em script e usar o banco
como armazenamento burro — anula a justificativa central da feature.

---

## Decision 6 — Backup por onda: export serializado, sem mecanismo novo

**Decision**: o snapshot por onda fechada continua sendo gerado em
`state-history/`, agora serializado a partir do `state.db` reaproveitando o
export do FR-007. Nenhum mecanismo de backup nativo do SQLite
(`VACUUM INTO`, `.backup`) é introduzido nesta fase.

**Rationale**: pré-decidido no clarify (spec §Clarifications, Session
2026-07-30) e reforçado por Decision 2 — como o WAL mantém dados em sidecars
`-wal`/`-shm`, um snapshot por cópia de arquivo seria sutilmente incorreto,
enquanto o export serializado é auto-contido por construção. Diretório
`state-history/` já existe no state dir real desta própria execução.

---

## Decision 7 — Ingestão do knowledge.db a partir do state.db (FR-008)

**Decision**: adicionar ao `cli/lib/recall.sh` um caminho de ingestão que lê
o `state.db` por SQL, mantendo o caminho JSON atual intacto e funcionando
(FR-012 e spec US4 AS-2: a rota SQL é **aditiva**, não substitui).

**Fatos verificados do mecanismo atual** (fonte: `cli/lib/recall.sh`):

- Modos existentes: busca (default), `--ingest`, `--reindex`, `--context`,
  `--list-memories`.
- `--ingest` **não descobre** arquivo: exige `--state-dir` e lê literalmente
  `"$state_dir/state.json"`. Ausente/ilegível ⇒ warning + exit 0.
- Schema em `schema_meta` (linha `key='schema_version'`), **não** em
  `PRAGMA user_version`; versão corrente `RECALL_SCHEMA_VERSION=12`.
- Entidades ingeridas e suas origens em JSON: `executions` (de
  `.execution` + `.accumulated_metrics`), `waves` (`.waves[]`), `decisions`
  (`.decisions[]`), `blocks` (`.human_blocks[]`), `tasks` (`.tasks[]`),
  `events` (`.events[]`), `skills` (`.waves[].skills_invoked[]`, filtrando
  `kind == "gate"`), `suggestions`, `retros`, `alert_signals`,
  `wave_model_usage`, `memories`.
- Idempotência por `UNIQUE(project, feature, wave, source_id)` +
  `ON CONFLICT … DO UPDATE`.
- Proveniência: `project` via `recall_derive_canonical` (campo congelado
  `.execution.canonical_project` > git worktree > basename do
  `target_project_path`); `feature` via `.short_name` com fallback por
  layout de diretório.
- Degradação: ausência de `sqlite3`, `jq` ou `secrets-filter.sh` ⇒
  `log_warn` + exit 0, nunca aborta a onda.

**Consequência de projeto**: como a ingestão SQL→SQL passa a ler de um banco
e escrever noutro, o caminho natural é `ATTACH DATABASE` do `state.db` (o
`knowledge.db` continua sendo o único destino de escrita — FR-009).
**DECISÃO EM ABERTO (D7-a)**: `ATTACH` do `state.db` como `read-only`
(`file:…?mode=ro` via URI) versus leitura em processo `sqlite3` separado
com pipe do resultado. A primeira é mais direta; a segunda evita qualquer
possibilidade de o processo de ingestão escrever no `state.db` por engano.
Decidir antes da task de FR-008.

**Invariante preservada (FR-009)**: nenhum projeto grava no `knowledge.db`
diretamente; ele continua único, global, derivado e reconstruível por
`--reindex`.

---

## Decision 8 — Migração idempotente (FR-005 / FR-006 / FR-014-INFRA-IDEMP)

**Decision**: migração em quatro tempos — **recusar → construir fora →
verificar → publicar atomicamente**:

1. **Recusar cedo**: aborta se `.execution.status` for `em_andamento`
   (FR-005) ou se a validação atual reprovar. Reaproveitar os verificadores
   que já existem em vez de reimplementar: `state-validate.sh` (invariantes)
   e `state-rw.sh sha256-verify` (integridade do arquivo de origem). Um
   bloqueio humano órfão, por exemplo, já é detectado por
   `state-validate.sh` — atende SC-006 sem código novo de checagem.
2. **Construir fora do lugar**: escrever num arquivo temporário no mesmo
   diretório (mesmo filesystem, requisito para o rename atômico).
3. **Verificar** (FR-006): contagem por entidade e comparação campo-a-campo
   entre origem e destino. Falhou ⇒ descarta o temporário; o projeto
   continua operando pelo `state.json` original, intacto (spec US2 AS-4).
4. **Publicar**: `mv` do temporário para `state.db` — atômico dentro do
   mesmo filesystem.

**Idempotência**: chave natural = identidade da execução (`.execution.id`,
o campo que `state-rw.sh init` grava e que a ingestão do recall já usa como
`execution_id`). Reexecutar sobre projeto já migrado não duplica nem
corrompe: a migração é sempre reconstrução completa a partir da origem,
seguida de publicação atômica — não é append incremental sobre um banco
existente. Registrar cada tentativa em `MigrationRun` (entidade da spec).

**Verificação campo-a-campo — como fechar SC-001 sem escrever um comparador
novo**: gerar o export FR-007 a partir do `state.db` recém-construído e
compará-lo com o `state.json` de origem. É exatamente o que SC-001 pede
("comparação campo-a-campo entre o export pós-migração e o `state.json`
original") e reduz a superfície de código de verificação a uma comparação de
JSON canonicalizado.

**Ordem de inserção**: a FK bloqueio→decisão obriga inserir decisões antes
de bloqueios. Como os IDs originais (`dec-NNN`, `block-NNN`, `onda-NNN`) são
preservados (FR-005), não há reescrita de identificador.

---

## Decision 9 — Coexistência e precedência de fonte de verdade

**Decision**: presença de `state.db` **com migração verificada** vence;
`state.json` remanescente vira export/legado. Pré-decidido no clarify.

**Consequência de implementação**: precisa existir um sinal legível de
"migração verificada" — não basta o arquivo existir, porque um `state.db`
parcial de uma migração interrompida não deve ganhar precedência. Como a
Decision 8 publica por rename atômico, um `state.db` **visível** é sempre
um banco completo e verificado; o temporário nunca ocupa o nome final. A
precedência pode então ser decidida por presença do arquivo — desde que a
migração jamais escreva no nome final antes de verificar.

---

## Decision 10 — Versão mínima de `sqlite3` suportada (task 1.2)

**Decision**: piso de `sqlite3` **3.45.1**, definido pelo ambiente mais
restritivo entre os dois já documentados como reais (não hipotéticos):
macOS local (`3.51.0`) e o runner `ubuntu-latest` do CI (`3.45.1`, imagem
`Ubuntu 24.04`).

**Evidência (fonte rastreável, não suposição)**:

- macOS local: `sqlite3 --version` → `3.51.0 2025-06-12 ... f0ca7bba1c5e...`
  (Decision 1, já documentado).
- CI (`ubuntu-latest`, `.github/workflows/*.yml` — `release.yml`,
  `shellcheck.yml`, `publish-site.yml` usam `runs-on: ubuntu-latest`):
  consultado via GitHub API
  (`api.github.com/repos/actions/runner-images/contents/images/ubuntu/Ubuntu2404-Readme.md`,
  README oficial da imagem Ubuntu 24.04 usada pelos runners hospedados),
  seção "Databases" lista `sqlite3 3.45.1` e a tabela de pacotes lista
  `sqlite3 | 3.45.1-1ubuntu2.6`.
- Menor das duas versões reais = **3.45.1** → piso adotado.

**C8-b (JSON1 / `json_valid` / `json_array_length`)**: suportado no piso.
Confirmado por duas fontes: (1) execução local —
`SELECT json_valid('{"a":1}'), json_array_length('[1,2,3]');` → `1|3`,
sem PRAGMA nem extensão carregada; (2) árvore de fontes do tag
`version-3.45.1` no repositório oficial (`github.com/sqlite/sqlite`,
consultado via `api.github.com/repos/sqlite/sqlite/contents/src?ref=version-3.45.1`)
já contém `src/json.c` **dentro do core** (não em `ext/misc/`), confirmando
que as funções JSON são compiladas por padrão desde antes do piso — não é
preciso o degrade documentado em `data-model.md` para `CHECK
(length(options_considered) > 2)`.

**C8-a (parâmetros nomeados / `.param set`)**: suportado no piso.
Confirmado via árvore de fontes do mesmo tag (`src/shell.c.in` em
`version-3.45.1`): a função `bind_table_init` cria a tabela
`temp.sqlite_parameters` e o dispatcher de comandos-ponto implementa
`.parameter set NAME VALUE` (`.param` casa por prefixo, forma abreviada
usual do shell `sqlite3`). Veredito: **adotar `.param set` como
otimização** sobre o piso já obrigatório (`strip_nul` + `sql_escape`,
`contracts/primitives.md` §C8) — ambos os mecanismos convivem; primitivas
usam parâmetros nomeados quando disponíveis e mantêm o escape manual como
caminho compatível caso uma instalação divergente não suporte `.param`.

**Consequência**: nenhum degrade de JSON1 é necessário; `research.md`/
`data-model.md` documentam piso `3.45.1` (não mais "assumir >= 3.38, a
verificar"). Decisão registrada como `dec-046` (score 3, evidência =
outputs literais acima).

---

## Riscos e não-decisões

| # | Item | Estado |
|---|---|---|
| R1 | Amendment 1.3.0 da constitution (sqlite3 obrigatório) | **Fechada** — ratificado (commit `c5b2d65`, rodapé `docs/constitution.md` = `1.3.0`); gate task 1.1 liberado (dec-045) |
| R2 | Cobertura de adulteração (D4-a) | **Fechada** (dec-025, resposta ao block-002) — opção 1, `integrity_check` apenas, regresso aceito e documentado |
| R3 | Forma do acesso na ingestão SQL→SQL (D7-a) | Decisão em aberto — fechar antes da task de FR-008 |
| R4 | ~24 scripts leem `state.json` hoje | Mitigado por FR-007 (export); nenhum precisa ser reescrito nesta fase |
| R5 | Versão mínima de `sqlite3` (task 1.2) | **Fechada** (Decision 10, dec-046) — piso `3.45.1`, JSON1 e `.param set` confirmados no piso |

**Nenhum `NEEDS CLARIFICATION` do Technical Context permanece aberto.** D4-a
e D7-a não são unknowns de contexto técnico: são escolhas de design
delimitadas, com opções enumeradas e ponto de decisão atribuído — registradas
aqui para não serem decididas silenciosamente na implementação. D4-a **já
está fechada** (dec-025); D7-a permanece em aberto para `/create-tasks`.
