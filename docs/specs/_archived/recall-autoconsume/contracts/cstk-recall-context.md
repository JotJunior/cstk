# Contract: `cstk recall --context` (modo leitura-para-contexto)

**Feature**: `recall-autoconsume` | **Arquivo**: `cli/lib/recall.sh`
(`recall_mode_context`) | **Spec**: [../spec.md](../spec.md)

Modo NOVO de `cstk recall`, distinto de busca (default), `--ingest` e
`--reindex`. Retorna achados do indice de conhecimento formatados como bloco
markdown enxuto, pronto para injecao em prompt. Read-only, best-effort.

---

## Invocacao

```sh
cstk recall --context "<termos>" \
  [--limit N] \
  [--exclude-feature <name>] \
  [--type T] \
  [--project P] \
  [--db PATH] \
  [--max-bytes N]
```

### Flags

| Flag | Obrig. | Default | Descricao |
|------|--------|---------|-----------|
| `<termos>` | sim | — | termos de consulta (string; tokenizada por whitespace). Compostos com **OR** (Decision 1). |
| `--context` | sim | — | seletor do modo (despachado por `recall_main`). |
| `--limit N` | nao | **4** | maximo de achados (inteiro positivo, faixa recomendada 3-5). Reusa `validate_limit`. |
| `--exclude-feature <name>` | nao | — | anti-eco (FR-005): omite registros com `feature = <name>`. |
| `--type T` | nao | — | filtro por tipo: `decision\|bloqueio\|retro\|skill`. Reusa `validate_type`. |
| `--project P` | nao | — | filtro por projeto de origem. |
| `--db PATH` | nao | resolvido | indice; `recall_resolve_db` (`--db` > `CSTK_KNOWLEDGE_DB` > `~/.claude/cstk/knowledge.db`). |
| `--max-bytes N` | nao | **2000** | teto de bytes do bloco (FR-006/SC-004). Inteiro positivo. |
| `-h\|--help` | nao | — | imprime usage, exit `RECALL_EXIT_OK`. |

### Despacho

`recall_main` detecta o modo varrendo argv: presenca de `--context` =>
`recall_mode_context`. Coexiste com a deteccao existente de `--ingest`/`--reindex`;
default permanece `search`. Precedencia documentada: `--ingest`/`--reindex` e
`--context` sao mutuamente exclusivos por uso; se mais de um aparecer, o
comportamento e definido pela ordem de deteccao em `recall_main` (manter
explicito no codigo).

---

## Composicao da query (OR — Decision 1)

Cada token de `<termos>` e escapado como frase FTS5 (`fts_phrase_escape`, reuso)
e os tokens sao juntados com ` OR `. Helper novo `fts_query_escape_or` (ou
parametro de juncao em `fts_query_escape`) — o modo busca/ingest mantem
AND-implicito (default inalterado).

WHERE resultante:

```sql
WHERE knowledge_fts MATCH '<termos escapados com OR>'
  [AND feature  != '<sql_escape(exclude-feature)>']   -- anti-eco (FR-005)
  [AND type     =  '<sql_escape(type)>']
  [AND project  =  '<sql_escape(project)>']
ORDER BY bm25(knowledge_fts)
LIMIT <N>;
```

Duas camadas de escape (FTS5 por-token + SQL via `sql_escape`), identicas ao
modo busca. SEM piso de bm25 (FR-007).

---

## Output (stdout) — ContextBlock

Quando **K >= 1** achados (apos anti-eco e tetos):

```markdown
> Aprendizado recuperado (read-back loop) — K achados de execucoes passadas.

- **[decision]** cstk/cstk-knowledge-db/onda-006 (2026-05-23T...): FASE 7 (hook fim-de-onda): onde disparar cstk recall --ingest...
- **[skill]** cstk/cstk-knowledge-db/onda-004 (2026-05-23T...): geracao de checklist de qualidade de REQUISITOS...
```

- Cabecalho blockquote com a contagem K.
- Uma linha por achado: `- **[<type>]** <project>/<feature>/<wave> (<source_ts>): <body truncado>`.
- `body` truncado por achado (ex: 280 chars) + sufixo `...` quando cortado.
- Bloco inteiro <= `--max-bytes` (para de adicionar achados ao atingir o teto;
  corta pelo ultimo achado inteiro que cabe).
- Proveniencia compacta inline (distinta do modo busca: 2 linhas/achado).

Quando **K = 0** (no-op): **stdout vazio** (sem cabecalho, sem erro).

---

## Exit codes

| Codigo | Constante | Situacao |
|--------|-----------|----------|
| 0 | `RECALL_EXIT_OK` | sucesso (K>=1 OU no-op: zero achados / dep ausente / db ausente-corrompido) |
| 2 | `RECALL_EXIT_USAGE` | uso incorreto: `--limit`/`--max-bytes` nao-inteiro, `--type` fora do enum, flag invalida, NUL em input, termos ausentes |

**Nunca** retorna codigo de falha por degradacao (FR-012): toda degradacao =
exit 0 + stdout vazio.

---

## Degradacao graciosa (no-op silencioso, exit 0)

| Condicao | Deteccao | Resultado |
|----------|----------|-----------|
| `sqlite3` ausente | `recall_have_sqlite3` | no-op, opcional `log_warn` em stderr |
| `jq` ausente | (usado no orquestrador p/ derivar termos) | passo PRE-DECISAO no-op |
| DB ausente | `! -f "$db"` | no-op |
| DB corrompido | `PRAGMA quick_check != ok` | no-op |
| Zero match / query degenerada | resultado vazio | stdout vazio |
| `database is locked` | WAL + `.timeout 5000`; se falhar, query vazia | no-op |

---

## Read-only (FR-014)

- Usa **somente** `recall_query_sql` (leitura). NUNCA `recall_run_sql` /
  `recall_apply_schema` (escrita).
- NAO cria/modifica o DB. NAO toca `state.json`.
- Verificavel por teste: mtime/size do DB inalterados apos invocacao (SC-006).

---

## Seguranca (FR-015)

- Conteudo do `body` ja foi scrubbed na **ingestao** (`secrets-filter.sh`,
  FR-017 da spec arquivada). O modo `--context` NAO re-scrub (seguro por
  construcao).
- NUL em qualquer input do usuario (`<termos>`, `--exclude-feature`, `--type`,
  `--project`, `--db`) e rejeitado com `RECALL_EXIT_USAGE` (consistente com
  modo busca).
- Estritamente local (Principio IV — zero coleta remota).

---

## Integracao com orquestradores (passo PRE-DECISAO — FR-008/FR-010/FR-011)

Pseudocodigo do passo, injetado no inicio das fases `specify` e `plan` de
`agente-00c-feature-orchestrator` e `agente-00c-orchestrator`:

```sh
# 1. derivar termos (teto <=8): aspectos primario, descricao fallback
TERMS=$(jq -r '.aspectos_chave_iniciais | .[0:8] | join(" ")' "$SD/state.json" | tr '-' ' ')
[ -n "$(printf '%s' "$TERMS" | tr -d ' ')" ] || \
  TERMS=$(jq -r '.execucao.projeto_alvo_descricao // .descricao_curta // ""' "$SD/state.json")

# 2. consumir (best-effort; --exclude-feature = anti-eco)
BLOCO=$(cstk recall --context "$TERMS" --limit 4 \
          --exclude-feature "$SHORT_NAME" --max-bytes 2000 2>/dev/null) || BLOCO=""

# 3. se K>0: injetar BLOCO no contexto + registrar Decisao (FR-016)
if [ -n "$BLOCO" ]; then
  K=$(printf '%s\n' "$BLOCO" | grep -c '^- ')
  state-decisions.sh register --state-dir "$SD" --etapa "<specify|plan>" \
    --contexto "read-back PRE-DECISAO: K=$K achados injetados (anti-eco feature=$SHORT_NAME)" \
    --opcoes '["injetar-achados","no-op"]' --escolha "injetar-achados" \
    --justificativa "termos: $TERMS" --score 2
fi
# K=0 => no-op, sem Decisao dedicada (FR-017)
```

Custo: <=2 invocacoes de leitura por feature (SC-006). NAO injetar em
clarify/execute-task/gate/review (FR-010).
