# Auditoria de Paths nos Scripts do Runtime (FASE 1, task 1.1)

**Data**: 2026-05-20
**Origem**: feature-00c FASE 1 — parametrizacao retrocompativel
**Comando empirico de descoberta**:
```sh
grep -l "agente-00c-state" global/skills/agente-00c-runtime/scripts/*.sh
grep -h "^# " global/skills/agente-00c-runtime/scripts/*.sh | grep -i "state-dir"
```

## Resultado da Categorizacao

| Categoria | Quantidade | Scripts |
|-----------|-----------|---------|
| **ARG-AWARE** (ja aceitam `--state-dir`) | 18/21 | bash-guard, bloqueios, budget, circular, cycles, drift, path-guard, pipeline, retro, sanitize, secrets-filter (parcial), spawn-tracker, state-decisions, state-lock, state-ondas, state-rw, state-validate, whitelist-validate |
| **HARDCODED em template/string** | 3/21 | issue.sh:179, report.sh:318-319, secrets-filter.sh:75 |
| **NO-PATH** (sem referencia a state) | 0/21 | — |

## Detalhamento das 3 ocorrencias HARDCODED

### 1. `secrets-filter.sh:75`

```sh
_proj_ignore="$_proj_dir/.claude/agente-00c-state/secrets-filter-ignore"
```

**Contexto**: caminho do arquivo de allow-list que define quais chaves
NAO devem ser redacted. `$_proj_dir` ja e parametrizado (vem do dirname
de $ENV_FILE). O segmento `agente-00c-state` e hardcoded.

**Impacto para feature-00c**: ambiguo. Duas opcoes:
- (a) **SHARED**: ambos orquestradores leem do mesmo arquivo
  `.claude/agente-00c-state/secrets-filter-ignore` — config no nivel
  do projeto, nao do orquestrador. Reduz duplicacao + ambos operam ao
  mesmo nivel de confianca.
- (b) **SPLIT**: feature-00c le de
  `.claude/feature-00c-state/<short>/secrets-filter-ignore` — config
  por feature. Mais flexivel mas duplica.

**Decisao**: SHARED (opcao a). Razao: secrets-filter-ignore e config
do projeto-alvo, nao do orquestrador — operadores definem o que e
"sensivel localmente" no projeto, e ambos orquestradores precisam
respeitar isso identicamente.

**Acao**: NENHUMA mudanca em secrets-filter.sh:75. Path permanece como
esta. Documentar a decisao SHARED em SKILL.md.

### 2. `issue.sh:175,177,179`

```sh
# Linha 175
$_ISH_PAP/.claude/agente-00c-report.md
# Linha 177
$_ISH_PAP/.claude/agente-00c-suggestions.md#$_sug
# Linha 179
$_ISH_PAP/.claude/agente-00c-state/state-history/$_ISH_ONDA-<timestamp>.json
```

**Contexto**: string template do corpo da issue (Markdown renderizado
para o usuario no GitHub). Paths sao apenas REFERENCIAS para o leitor
encontrar localmente — nao sao operacoes I/O do script.

**Impacto para feature-00c**: o body da issue precisa mencionar paths
COERENTES com a feature que originou. Para issues abertas pelo
feature-00c, paths devem usar `feature-00c-report.md`,
`feature-00c-suggestions.md`, `feature-00c-state/<short>/`.

**Acao**: introduzir flag opcional `--flavor=agente-00c|feature-00c`
(default `agente-00c`); paths derivados do flavor.

### 3. `report.sh:318-322`

```sh
"- Estado: ${PAP}/.claude/agente-00c-state/state.json"
"- Backups de estado: ${PAP}/.claude/agente-00c-state/state-history/"
"- Sugestoes detalhadas: ${PAP}/.claude/agente-00c-suggestions.md"
"- Whitelist: ${PAP}/.claude/agente-00c-whitelist"
```

**Contexto**: Apendice A do relatorio final, listando caminhos
relevantes para o leitor.

**Impacto para feature-00c**: relatorio precisa apontar para paths
da feature, nao do agente-00c global.

**Acao**: idem a issue.sh — flag `--flavor` + paths derivados.

## Contrato Final de Parametrizacao

### 1. Argumento posicional `--state-dir DIR` (ja existente, sem mudanca)

Continua sendo a forma canonica de passar o diretorio de estado para
QUALQUER script do runtime. Backward-compat 100%.

### 2. Variavel de ambiente `AGENTE_00C_STATE_DIR` (nova, opcional)

Helper sourceable `_state-dir.sh` resolve `${AGENTE_00C_STATE_DIR:-}`
quando `--state-dir` nao for fornecido. Permite invocacoes mais
concisas no contexto do feature-00c-orchestrator. Default = vazio
(sem fallback), forcando erro claro em vez de comportamento
silencioso.

### 3. Flag `--flavor=agente-00c|feature-00c` (nova, opcional)

Aplicada apenas aos 3 scripts que renderizam paths em
templates/relatorios (issue.sh, report.sh). Default `agente-00c` para
preservar comportamento atual sem mudanca em `/agente-00c`. Quando
`--flavor=feature-00c`, paths sao derivados como:
- report: `<projeto>/.claude/feature-00c-state/<short>/feature-00c-report.md`
- suggestions: `<projeto>/.claude/feature-00c-suggestions.md` (compartilhada per-projeto)
- state-history: `<projeto>/.claude/feature-00c-state/<short>/backups/`

O nome `<short>` e passado adicionalmente via `--short-name STR` quando
`--flavor=feature-00c`.

## Resumo

| Acao | Quantidade |
|------|------------|
| Scripts intocados (ja parametrizados) | 18 |
| Scripts com mudanca minima (1-3 linhas, novo flag opcional) | 2 (issue.sh, report.sh) |
| Scripts com decisao documentada mas sem mudanca | 1 (secrets-filter.sh — SHARED) |
| Helpers novos | 1 (`_state-dir.sh` sourceable) |
| Testes novos | 1 (`tests/test_state-dir-parametrization.sh`) |

**Conclusao**: a estimativa original do plan ("refactor 21 scripts") foi
sobre-estimada. A realidade empirica e que os scripts ja foram
desenhados com `--state-dir` desde o inicio. Apenas 2 scripts precisam
de pequenas adicoes (flag opcional), e 1 decisao de design (SHARED) e
documentada sem mudanca de codigo. FASE 1 e majoritariamente
documentacao + helper conveniente + testes de regressao.
