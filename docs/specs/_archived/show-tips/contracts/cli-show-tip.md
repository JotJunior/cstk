# Contract: `cstk show-tip` / `cli/lib/show-tip.sh`

**Feature**: `show-tips` | **Interface**: CLI (POSIX sh) | **Date**: 2026-05-27

O mecanismo de exibicao de dicas. Implementado em `cli/lib/show-tip.sh`
(POSIX sh, `#!/bin/sh`, `set -eu`), despachado por `cli/cstk` seguindo o mesmo
padrao de `cstk recall` (`_dispatch` resolve `cli/lib/<cmd>.sh`, source, chama
`show_tip_main "$@"`).

> Despacho: hifens no nome do subcomando viram underscores na funcao
> (`show-tip` → `show_tip_main`), conforme convencao de `cli/cstk` (`sed
> 's/-/_/g'`). O subcomando `show-tip` deve ser adicionado a lista do `case`
> em `_dispatch` e em `_cmd_help`.

---

## Command: `cstk show-tip [SKILL] [FLAGS]`

**Invocacao**: `cstk show-tip [SKILL] [--phase FASE] [--audit] [--catalog PATH]`
**Auth**: N/A (local, sem rede — Principio IV)
**Side effects**: nenhum (read-only sobre `tips/catalog.md`)

### Argumentos posicionais

| Arg | Type | Required | Descricao |
|-----|------|----------|-----------|
| `SKILL` | string | nao | nome da skill alvo. Se ausente, selecao aleatoria global (FR-010) |

### Flags

| Flag | Type | Default | Descricao |
|------|------|---------|-----------|
| `--phase FASE` | string | (vazio) | fase corrente do pipeline (modo automatico US1/US4). Pode mapear para uma skill relevante; sem mapeamento → aleatorio global |
| `--audit` | bool | false | modo auditoria de cobertura (SC-004); nao exibe dica, valida o catalogo |
| `--catalog PATH` | path | `tips/catalog.md` (relativo a raiz do repo) | override do caminho do catalogo (testes) |
| `-h`/`--help` | bool | — | uso |

> `--phase` e `SKILL` sao mutuamente complementares: se ambos ausentes →
> aleatorio global; se `SKILL` presente → dica daquela skill; se so `--phase` →
> dica mapeada da fase, com fallback aleatorio.

---

## Modo exibicao (default)

### Saida de sucesso (stdout)

Bloco visual destacado (FR-004), exemplo:

```
========================================================
 Dica: skill `review-task`  [uso]
--------------------------------------------------------
 Use /review-task para um relatorio completo do
 andamento da feature, com tarefas prontas para iniciar.

 Exemplo:
   /review-task nome-da-skill
========================================================
```

### Selecao da dica (FR-003 — RNG POSIX)

1. Determinar conjunto candidato:
   - `SKILL` dado → entradas com `skill: SKILL`.
   - `--phase FASE` com mapeamento → entradas da skill mapeada.
   - nenhum → todas as entradas (FR-010).
2. `N = numero de candidatos`.
3. `IDX = rng(N)` onde `rng` usa `od -An -N4 -tu4 /dev/urandom` como seed para
   `awk 'BEGIN{srand(SEED); print int(rand()*N)}'`. Fallback: `awk
   'BEGIN{srand(); ...}'` (research.md Decision 1, dec-012). **NUNCA `$RANDOM`**
   (bash-ism, viola Principio II).
4. Emitir a entrada `IDX` formatada como Tip Block.

### Exit codes (modo exibicao)

| Exit | Significado |
|------|-------------|
| 0 | sucesso (dica exibida OU string vazia por fail-silent) |

**FR-006 — fail-silent absoluto**: em modo exibicao, o comando SEMPRE retorna
exit 0. Catalogo ausente/ilegivel, skill sem dicas (modo automatico), erro de
parse → stdout vazio, exit 0. NUNCA propaga erro que interrompa a onda (SC-003).

### Caso: skill sem dicas

| Modo | Comportamento |
|------|---------------|
| automatico (`--phase`) ou sem args | stdout vazio, exit 0 |
| explicito (`SKILL` dado pelo usuario, US3 cenario 2) | mensagem amigavel em stdout: "Sem dicas cadastradas para `<skill>`." + sugestao de skills com dicas disponiveis; exit 0 |

---

## Modo `--audit` (SC-004)

Valida cobertura do catalogo. NAO exibe dica.

### Saida

- stdout: relatorio de cobertura (skills sem >= 2 dicas, categorias faltantes).
- exit 0: catalogo completo (todas as skills do universo com >= 2 dicas e
  categorias `uso`+`gotcha`).
- exit 1: catalogo incompleto; stdout lista os gaps (skill → contagem atual,
  categorias faltantes).

Universo de skills descoberto dinamicamente (research.md Decision 4):
`find global/skills -maxdepth 1 -mindepth 1 -type d` +
`find language-related -name SKILL.md` (deriva o nome da skill do diretorio pai).

### Exit codes (modo audit)

| Exit | Significado |
|------|-------------|
| 0 | catalogo completo |
| 1 | gaps de cobertura (listados em stdout) |
| 2 | uso incorreto (flag invalida) |

> Diferenca de contrato vs modo exibicao: em `--audit` o exit 1 e SIGNIFICATIVO
> (gaps), pois auditoria nao roda no caminho critico de onda — pode falhar sem
> interromper pipeline.

---

## Convencoes herdadas (Principio II)

- Shebang `#!/bin/sh`, `set -eu`.
- Mensagens de erro/diagnostico em stderr; dados (Tip Block, relatorio) em stdout.
- Zero dependencia externa: `awk`, `grep`, `od`, `find`, `printf`, `sed`.
- Sem bash-isms (sem `$RANDOM`, sem arrays, sem `[[ ]]`, sem `local`).

## Seguranca: injecao via argumentos CLI (OWASP A05 — gate de plan)

Threat model do gate owasp-security (onda-003). Superficie REAL: os argumentos
`SKILL` e `--catalog PATH` fluem para `awk`/`grep`/`find`. Mitigacao = restricao
de design OBRIGATORIA na implementacao (`execute-task`), severidade MEDIA
(mitigada por construcao — nenhum finding critical/high):

- **Passar valores de usuario como variavel `awk`, NUNCA interpolar no texto do
  programa awk**: usar `awk -v skill="$SKILL" '...'` e referenciar `skill`
  dentro do programa. Concatenar `$SKILL` no corpo do programa awk e injecao de
  codigo awk. Padrao espelhado de `cli/lib/recall.sh` (`printf '%s'` + escaping).
- **Match literal de nome de skill com `grep -F`** (fixed-string), nunca regex
  derivada de input — evita regex-DoS e metacaractere interpretado.
- **Aspas em TODA expansao de variavel** (`"$SKILL"`, `"$CATALOG"`); usar `--`
  antes de paths em `find`/operacoes de arquivo.
- **PROIBIDO `eval`, backticks com input, `$(...)` sobre input** — ja vetado por
  Principio II, reforcado aqui como controle de seguranca.
- **Path traversal via `--catalog` (severidade BAIXA)**: o script roda no
  contexto do proprio usuario (sem fronteira de privilegio — o usuario ja tem
  acesso ao filesystem). Ler arquivo arbitrario apontado por `--catalog` NAO e
  escalacao. Default fixo `tips/catalog.md`. Sem controle hard necessario;
  documentado para consciencia.
- **A10 / fail-silent (FR-006) NAO e fail-open de seguranca**: o caminho de
  exibicao nao toma nenhuma decisao de autorizacao; retornar vazio em erro e o
  comportamento correto e seguro.

> Sem rede (Principio IV) → A01/A07/SSRF N/A. Sem auth/token/cripto/MCP/LLM no
> caminho → A02/A03/A04/A07/A08 e LLM/ASI Top 10 N/A. Unico vetor acionavel e
> A05, mitigado pela disciplina POSIX acima.

## Contrato de integracao com orquestrador (US4)

O orquestrador (agente-00c / feature-00c) invoca:

```sh
TIP=$(cstk show-tip --phase "$FASE" 2>/dev/null) || TIP=""
[ -n "$TIP" ] && printf '%s\n' "$TIP"
```

O orquestrador NUNCA precisa conhecer a estrutura do catalogo (FR-008). Recebe
bloco pronto ou vazio. Falha do mecanismo nunca interrompe a onda (FR-006/SC-003).
