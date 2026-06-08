# Contracts: cstk-plugins — Pipeline integration (`--llm`)

Integracao entre o plugin store e os entrypoints SDD (`feature-00c`,
`agente-00c`). Implementa FR-013..FR-016. Path-prepending (dec-006, score 3):
nenhuma copia/symlink no catalogo core.

---

## Flag: `--llm <name>` (default `claude`)

Aceito pelos entrypoints da pipeline 00c:
- CLI: `cstk 00c <path> [--llm <name>]` (`cli/lib/00c-bootstrap.sh` — ja tem
  parser de flags `while ... case`, vide linha ~110).
- Slash commands: `/feature-00c` e `/agente-00c` aceitam `--llm <name>`.

| Value | Behavior |
|-------|----------|
| `claude` (ou flag ausente) | Comportamento IDENTICO ao atual (FR-013, SC-003 — zero regressao) |
| `<name>` instalado e integro | Path-prepending ativado (FR-014) |
| `<name>` nao instalado | Exit imediato ANTES de criar state (FR-015) |
| `<name>` instalado mas checksum falha | Recusa ativacao, integrity error (US2-AS4) |

### Pre-start gate (FR-015)

Antes de `state-rw.sh init` (antes de criar QUALQUER estado):

1. Se `--llm` == `claude` → seguir normal.
2. Senao, `plugin_common_is_installed <name>`:
   - nao instalado → stderr `Plugin '<name>' nao instalado — rode 'cstk
     plugin-add <name>' primeiro.`; exit 1 (FR-015).
   - instalado → re-verificar checksum (FR-005). Falha → stderr
     `Plugin '<name>' falhou verificacao de integridade (tampered); ativacao
     recusada.`; exit 1 (US2-AS4).
3. Gravar `execution.llm_plugin = "<name>"` no state via init (FR-016).

---

## Skill resolution: path-prepending (FR-014)

Funcao `plugin_resolve_skill_dir <skill>` em `cli/lib/plugin-common.sh`,
consultada pelo dispatcher quando `execution.llm_plugin != "claude"`.

### Resolution order

```
1. ~/.claude/cstk/plugins/<llm_plugin>/skills/<skill>/   (se existe → usar)
2. ~/.claude/skills/<skill>/                             (fallback core)
```

| Caso | Resultado |
|------|-----------|
| Plugin provê `<skill>` | Usa a versao do plugin (US2-AS1) |
| Plugin NAO provê `<skill>` | Fallback p/ core (US2-AS1) |
| `llm_plugin == "claude"` | Sempre core (sem prepending; US2-AS2) |
| Dois plugins provêm a mesma skill | So o selecionado por `--llm` ativa (Edge Case; um unico plugin ativo por invocacao) |

**Read-only**: a resolucao so faz `stat`/`test -d`. Nenhuma escrita no
filesystem. Edge Case "plugin-remove durante pipeline": skills ja resolvidas
em contexto continuam; o store some, a execucao em memoria termina.

---

## Resume contract (FR-016)

No `/feature-00c-resume` e `/agente-00c-resume`, antes da proxima onda:

1. Ler `execution.llm_plugin` do state.
2. Se `claude` → seguir normal.
3. Senao:
   - plugin nao instalado (foi removido entre ondas) → **bloqueio humano**
     (`bloqueios.sh register`): "Plugin '<name>' registrado no state nao esta
     mais instalado. Reinstalar via 'cstk plugin-add <name>' e retomar, ou
     abortar?"
   - re-verificacao de integridade falha → **bloqueio humano**: "Plugin
     '<name>' falhou integridade (tampered) na retomada. Reinstalar ou
     abortar?"
   - ok → re-ativar path-prepending e prosseguir.

Auditoria: o valor de `execution.llm_plugin` torna a escolha de LLM
reproduzivel e rastreavel entre ondas (FR-016).
