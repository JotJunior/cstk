# Contract: helper de deteccao de execucao ativa

**Feature**: `hooks-db-parity`
**Arquivo**: `global/skills/agente-00c-runtime/scripts/_hook-active-exec.sh`
**Tipo**: shell sourceable (nao executavel diretamente)

---

## Command: `hook_active_exec <cwd>` [PROPOSTA — a validar na implementacao]

Funcao sourceable que resolve qual execucao autonoma (`agente-00c` /
`feature-00c`) esta ativa a partir de um `cwd`, de forma agnostica ao
backend de persistencia (`state.json` ou `state.db`).

Novo artefato introduzido por esta feature. A assinatura abaixo e um
**desenho proposto**, nao um contrato ja existente no codebase.

### Uso

```sh
# Resolucao do helper: cadeia de candidatos identica a _pbg_resolve_dep
# (pretooluse-bash-guard.sh L54-69), verificada no codigo-fonte.
if _helper=$(_resolve_dep "scripts/_hook-active-exec.sh"); then
  . "$_helper"
  _out=$(hook_active_exec "$CWD"); _rc=$?
else
  _rc=127   # helper irresolvivel — tratamento por politica de cada hook
fi
```

### Parametros

| Posicao | Nome | Obrigatorio | Descricao |
|---------|------|-------------|-----------|
| 1 | `cwd` | sim | raiz do projeto a partir da qual `.claude/agente-00c-state/` e `.claude/feature-00c-state/` sao resolvidos |

### Exit codes

| Exit | Significado | stdout |
|------|-------------|--------|
| `0` | `ativa` — execucao ativa localizada | `<execution_kind>\t<state_dir>\t<backend>` |
| `1` | `inativa` — varredura completa, nenhuma execucao ativa (inclui "nenhum state presente", FR-007) | vazio |
| `2` | `indeterminada` — ao menos um `state.db` presente cujo status nao pode ser determinado, e nenhuma execucao ativa confirmada | vazio |
| `3` | uso incorreto (`cwd` vazio) | vazio |

`127` **nao** e emitido pela funcao: e o valor convencionado no chamador
para "helper irresolvivel", tratado com a mesma politica de
`indeterminada`.

### stdout / stderr

- **stdout**: exclusivamente a linha de resultado quando exit `0`. Nunca
  emite diagnostico, aviso ou log em stdout.
- **stderr**: **sempre vazio**. Requisito duro — o consumidor
  `posttooluse-tool-call-tick.sh` opera sob fail-open silencioso (FR-004) e
  qualquer texto em stderr apareceria ao operador. Erros do `sqlite3` e do
  `jq` sao suprimidos com `2>/dev/null` dentro do helper e traduzidos para
  exit `2`.

### Garantias

| # | Garantia | Requisito |
|---|----------|-----------|
| G1 | Precedencia `agente-00c` > `feature-00c`; entre `feature-00c`, menor short-name em `LC_ALL=C sort` | FR-002 |
| G2 | Dentro de um mesmo state-dir, `state.db` vence sobre `state.json` | FR-002 (paridade com `_sr_backend`) |
| G3 | Status ativos = `em_andamento`, `aguardando_humano` | FR-001 |
| G4 | Ausencia total de state (nem `.json` nem `.db`) => exit `1`, jamais `2` | FR-007 |
| G5 | `state.db` presente + `sqlite3` ausente/DB ilegivel => exit `2`, jamais `1` | FR-003, FR-007 |
| G6 | Um candidato `indeterminado` nao interrompe a varredura dos demais; `ativa` vence `indeterminada` | FR-002 |
| G7 | Nao escreve em nenhum arquivo; nao cria diretorio; nao muta o state-dir | FR-006, SC-004 |
| G8 | Nao consome stdin (o stdin do hook ja foi lido pelo chamador) | — |
| G9 | POSIX sh puro, sem Bash-isms | Constitution II |
| G10 | Unica mencao a `sqlite3` fora da camada de estado transacional | Constitution II carve-out 1.1.0 (b) |

### Leitura do backend SQLite

```
SELECT status FROM execution LIMIT 1;
```

Ordem de abertura (research Decision 1.a):

1. `file:<state-dir>/state.db?mode=ro` — sem efeito colateral; falha com
   `unable to open database file (14)` quando `-shm`/`-wal` nao existem.
2. fallback: path direto `<state-dir>/state.db` — sempre funciona; pode
   criar `state.db-shm` / `state.db-wal`.

`immutable=1` e **proibido** neste contrato: autoriza o motor a ignorar o
WAL, admitindo leitura stale sob escritor concorrente.

### Orcamento de latencia

| Cenario | Custo medido (referencia) |
|---------|---------------------------|
| 1 state-dir SQLite ativo | ~3.8 ms de query + varredura |
| por state-dir JSON adicional | ~5.2 ms (custo `jq` preexistente, inalterado) |

Tetos impostos pelo gate automatizado no **hook completo**, nao no helper
isolado: 150 ms (hooks de metrica) e 400 ms (hook de guarda) — ver
`quickstart.md` §Cenario 7 e research Decision 3.

---

## Command: `_resolve_dep <rel-path>` [EXISTENTE]

Cadeia de resolucao de dependencia ja implementada em
`pretooluse-bash-guard.sh` como `_pbg_resolve_dep` (L54-69). Reproduzida
aqui porque os outros dois hooks passam a precisar dela (hoje sao
auto-contidos).

| Ordem | Candidato | Cobre |
|-------|-----------|-------|
| 1 | `<dir-do-hook>/../<rel-path>` | arvore-fonte do repo (dev/testes: `hooks/` e `scripts/` sao irmaos) |
| 2 | `<cwd>/.claude/skills/agente-00c-runtime/<rel-path>` | instalacao escopo `project` |
| 3 | `$HOME/.claude/skills/agente-00c-runtime/<rel-path>` | instalacao escopo `global` |

Vence o primeiro existente **e executavel**. Exit `1` se nenhum encontrado.

### Ordem MODIFICADA para o helper (SEC-H1) [PROPOSTA]

Para `_hook-active-exec.sh` — e **somente** para ele — a ordem dos
candidatos 2 e 3 e **invertida**:

| Ordem | Candidato | Motivo |
|-------|-----------|--------|
| 1 | `<dir-do-hook>/../<rel-path>` | arvore-fonte do repo |
| 2 | `$HOME/.claude/skills/agente-00c-runtime/<rel-path>` | **escopo global vence**: instalacao controlada pelo operador sombreia arquivo plantado no repositorio |
| 3 | `<cwd>/.claude/skills/agente-00c-runtime/<rel-path>` | escopo `project`, ultimo recurso |

Razao (plan.md §Security Review, SEC-H1): diferente de
`bash-guard.sh`/`secrets-filter.sh` — resolvidos **apos** a confirmacao de
execucao ativa — o helper e sourceado **antes** da deteccao, logo em toda
invocacao de hook, em todo projeto. `cwd` vem do payload do harness, entao
o candidato derivado dele passa a ser alcancavel por conteudo de
repositorio hostil sem necessidade de execucao 00c ativa.

A ordem original permanece **inalterada** para as demais deps (nenhuma
regressao de comportamento).

### Pre-condicao de sourcing (SEC-H1, obrigatoria)

O hook MUST executar um **pre-check inline**, usando apenas builtins do
shell (`[ -f ]`, `[ -d ]`), antes de resolver ou sourcear o helper:

> Existe ao menos um `state.json` **ou** `state.db` sob
> `<cwd>/.claude/agente-00c-state/` ou `<cwd>/.claude/feature-00c-state/*/`?

Se **nao**, o hook sai `0` imediatamente (fora de escopo, FR-006) sem
resolver nem sourcear nada. Esse e o caminho de 100% das sessoes manuais do
operador — que passam a nao tocar em nenhum arquivo externo.

### Requisitos adicionais de implementacao (SEC-M1, SEC-M2, SEC-M3)

| ID | Requisito |
|----|-----------|
| SEC-M1 | NAO interpolar o path cru numa URI `file:...`. Usar `sqlite3 -readonly <path>` ou escapar `?`, `#`, `%` antes de montar a URI |
| SEC-M2 | Emitir `PRAGMA busy_timeout=200;` antes do `SELECT`; descartar o eco do pragma no stdout (gotcha documentado em `_state-db.sh` L77-89) |
| SEC-M3 | Ordenar os short-names (`LC_ALL=C sort`) **antes** de sondar e parar no primeiro ativo; aplicar teto defensivo de state-dirs sondados por invocacao |
| SEC-H2 | Auto-teto interno de tempo bem abaixo do `timeout: 5` do harness, com `MECANISMO_FALHOU` explicito no guard — a menos que a doc oficial confirme que timeout de hook `PreToolUse` ja significa `deny` |

> Nota de implementacao: para um arquivo **sourceable** o teste `-x` do
> `_pbg_resolve_dep` original nao e apropriado (helpers `_*.sh` do runtime
> nao sao executaveis — verificado: `_state-read.sh` esta `-rw-r--r--`). A
> variante usada para o helper MUST testar `-r` (legivel), nao `-x`.
