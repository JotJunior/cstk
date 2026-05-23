# Contract — Helper de ingestao pos-onda

**Feature**: `cstk-knowledge-db` | **Date**: 2026-05-23

Define o contrato da operacao de **ingestao** que extrai conhecimento
estruturado de um `state.json` e o grava no indice
(`~/.claude/cstk/knowledge.db`). A ingestao e um **efeito colateral
aditivo e best-effort** do fim de onda — jamais um gate (FR-006, FR-018).

Implementacao confinada a `cli/lib/recall.sh` (unico arquivo que
referencia `sqlite3`, `jq` e `secrets-filter.sh` — carve-out condicao
(b)).

---

## Invocacao

Forma canonica (sub-comando do CLI):

```
cstk recall --ingest --state-dir <DIR> [--db <PATH>]
```

| Flag | Obrigatoria | Default | Descricao |
|------|-------------|---------|-----------|
| `--ingest` | sim (modo) | — | seleciona o modo ingestao |
| `--state-dir <DIR>` | sim | — | diretorio de state da feature (contem `state.json`) |
| `--db <PATH>` | nao | `$CSTK_KNOWLEDGE_DB` ou `~/.claude/cstk/knowledge.db` | caminho do indice |

Invocacao a partir do orquestrador/runtime (fim de onda): o runtime
chama o binario `cstk` (desacoplado do schema). Se `cstk` ausente no
PATH, o runtime degrada gracioso (aviso, segue a onda) — a ingestao e
opcional.

---

## Comportamento

1. **Resolver fonte**: ler `<DIR>/state.json`. Se ausente/ilegivel →
   aviso em stderr + exit 0 (degradacao graciosa; nao e erro fatal).
2. **Checar deps**: `command -v sqlite3` e `command -v jq`. Se qualquer
   ausente → aviso explicativo em stderr + exit 0, SEM criar/alterar o
   indice (FR-018, US3 cenario 1).
3. **Garantir DB**: criar diretorio do `--db` se possivel; abrir/criar o
   DB; aplicar schema (idempotente: `CREATE TABLE IF NOT EXISTS`,
   `CREATE VIRTUAL TABLE IF NOT EXISTS`); aplicar pragmas WAL +
   busy_timeout. Se diretorio nao-gravavel → aviso + exit 0.
4. **Extrair (read-only)** via `jq` do `state.json`:
   - `decisoes[]` → tabela `decisions`
   - `bloqueios_humanos[]` → tabela `bloqueios`
   - `retro` (ou array equivalente) → tabela `retros`
   - `ondas[].skills_invoked[]` → tabela `skills`
   - proveniencia comum: `execucao.id`, `short_name`,
     `execucao.projeto_alvo_path`, id da onda, timestamp do registro.
5. **Filtrar segredos** (somente texto livre, FR-017): cada campo de
   texto livre passa por `secrets-filter.sh scrub` (stdin→stdout) ANTES
   de persistir. Campos estruturados/proveniencia/nomes-de-skill NAO
   passam pelo filtro.
6. **Upsert idempotente** (FR-007/008): para cada registro,
   `INSERT ... ON CONFLICT(<chave>) DO UPDATE` nas tabelas; para o FTS5,
   `DELETE` por proveniencia+source_id seguido de `INSERT` na mesma
   transacao. Tudo dentro de `BEGIN; ... COMMIT;`.
   **Escaping obrigatorio (A05 Injection / CWE-89)**: TODO valor extraido
   do `state.json` (campos de texto livre E campos estruturados/
   proveniencia) que compoe um INSERT/UPDATE/DELETE tem suas aspas
   simples duplicadas (`'`→`''`) antes de entrar na string SQL. O
   `sqlite3` CLI nao oferece bind nativo via argv, portanto o escaping e
   a defesa primaria — nenhum valor e concatenado cru. Isto vale inclusive
   para campos de proveniencia: um `projeto_alvo_path` ou `source_id` com
   aspa simples nao pode injetar SQL. Coberto por teste com payload
   adversarial (`'; DROP TABLE ...; --`) em campo de texto e em
   proveniencia.
   **Rejeicao de NUL bytes (hardening dec-015, block-001)**: TODO valor
   extraido do `state.json` — campos de texto livre E campos
   estruturados/proveniencia — e verificado quanto a bytes NUL (`\000`)
   ANTES do escaping e da persistencia. Um byte NUL trunca strings em C
   (no `sqlite3` CLI e em `jq`), podendo corromper o INSERT, mascarar
   payloads de injecao ou produzir linhas truncadas. A presenca de NUL e
   tratada removendo o(s) byte(s) (strip) antes de persistir — a ingestao
   e best-effort/aditiva (FR-018), logo NAO aborta nem falha a onda por
   conta de NUL: ela sanitiza e segue (exit 0). NUL nunca chega intacto a
   camada SQL/FTS5. Coberto por teste com fixture de byte cru NUL (escape
   OCTAL `\000`, nunca hex) em campo de texto livre e em proveniencia.
7. **Concorrencia** (FR-016): WAL + `busy_timeout=5000`. Em "database is
   locked" persistente → retry/backoff limitado (ate 3 tentativas, sleep
   crescente); esgotado → aviso + skip da ingestao desta onda + exit 0.
   NUNCA usa `state-lock.sh`.
8. **Garantia de fonte intacta** (FR-009, SC-006): nenhuma escrita no
   `state.json` nem em artefatos transacionais. So `jq` de leitura.

---

## Exit codes

| Code | Significado | Tratamento pelo orquestrador |
|------|-------------|------------------------------|
| `0` | sucesso OU degradacao graciosa (dep ausente, fonte ausente, lock persistente, dir nao-gravavel) | seguir a onda normalmente |
| `2` | uso incorreto (flags invalidas) | erro de chamada — corrigir invocacao |

> NAO existe exit nao-zero por falha de ingestao "de verdade": toda falha
> operacional da camada de conhecimento degrada para exit 0 + aviso
> (FR-018, SC-003). Exit 2 e reservado a erro de USO (programacao), nao a
> falha de runtime da camada.

---

## Idempotencia (FR-007, FR-008, SC-002)

- Reingerir o mesmo `state.json` N vezes → contagem de linhas estavel.
- Reingerir apos novos registros → apenas os novos sao adicionados;
  antigos nao duplicam.
- Registro que mudou (ex: bloqueio respondido) com a mesma chave de
  proveniencia → linha atualizada (versao mais recente), nao nova linha.

---

## Saida (stdout/stderr)

- **stdout**: resumo opcional (`ingested: N decisions, M bloqueios, K
  retros, S skills`) — informativo, parseavel; vazio aceitavel.
- **stderr**: avisos de degradacao graciosa (dep ausente, lock, etc.).

---

## Cenarios de aceite mapeados

| Cenario (spec) | Comportamento |
|----------------|---------------|
| US2 AS1 (N+M+K+S registros) | apos ingest, indice contem exatamente esses registros com proveniencia |
| US2 AS2 (reingest mesma onda) | contagem inalterada |
| US2 AS3 (novos registros) | apenas novos adicionados |
| US2 AS4 (fonte intacta) | state.json byte-a-byte inalterado |
| US3 AS1 (sem dep) | aviso + exit 0, indice nao criado/alterado |
| Edge: state parcial | processa apenas registros presentes, sem assumir completude |
| Edge: dado sensivel | texto livre scrubbed; chave intacta |
| Edge: dir nao-gravavel | cria se possivel, senao degrada (exit 0) |
| Edge: NUL byte em valor (dec-015) | NUL stripado antes de persistir; ingestao segue (exit 0); nunca chega ao SQL/FTS5 |
