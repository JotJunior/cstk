# Contract: guard de composicao de allowlist dos orquestradores

**Feature**: `orchestrator-mcp-allowlist` | **Date**: 2026-08-16

> **[PROPOSTA — a validar na implementacao]** — este contrato descreve um
> artefato que AINDA NAO EXISTE no repo. Nada abaixo deve ser lido como
> comportamento atual. O que ja existe hoje e o guard revogado por FR-001,
> descrito em `research.md` Decision 1.

**Artefato**: `tests/test_orchestrator-allowlist-guard.sh`
**Tipo**: scenario-based POSIX sh, harness do repo (`tests/run.sh`)
**Dependencias externas**: nenhuma (sem `jq` — ver research Decision 4)

## Descoberta de alvos

```sh
# glob, nunca lista hardcodeada (dec-016 / FR-002)
plugins/cstk/agents/*-orchestrator.md
```

Hoje resolve para 2 arquivos [FONTE: `ls plugins/cstk/agents/`]:
`agente-00c-orchestrator.md`, `agente-00c-feature-orchestrator.md`.

## Scenarios e vereditos

| Scenario | Assert | Requisito |
|----------|--------|-----------|
| `scenario_orchestrator_glob_nao_vazio` | o glob casa >= 1 arquivo; falha com `no_orchestrator_found` se 0 | anti-ponto-cego (research Decision 3) |
| `scenario_allowlist_nunca_vazia_nem_so_mcp` | para CADA alvo: `tools:` presente E `native_entries` nao-vazio | FR-002, FR-004 [FONTE: spec.md:212-229] |
| `scenario_allowlist_declara_as_7_tools_mcp` | para CADA alvo: as 7 entradas `mcp__cstk-state__*` presentes | FR-003 [FONTE: spec.md:221-224] |
| `scenario_allowlist_preserva_bash` | para CADA alvo: `Bash` presente em `native_entries` | FR-004 ("no minimo, a tool de execucao de comandos") [FONTE: spec.md:225-229] |
| `scenario_guidance_block_presente` | para CADA alvo: par de marcadores `MCP-VS-BASH` presente, `body` nao-vazio | FR-005 [FONTE: spec.md:230-235] |
| `scenario_guidance_block_conteudo_minimo` | `body` cobre os 9 itens obrigatorios de `data-model.md` §Conteudo minimo | FR-006 [FONTE: spec.md:236-246] |
| `scenario_guidance_block_regra_nao_exfiltracao` | `body` contem a regra de nao-exfiltracao do `session_id` (item 9) | gate `owasp-security` F1 (LLM02/LLM07/ASI03) |
| `scenario_guidance_block_paridade` | `body` dos 2 alvos e byte-identico (apos trim de whitespace terminal) | FR-011 [FONTE: spec.md:280-284] |

### Casos negativos exercitados por fixture

O guard MUST ser exercitado contra frontmatters sinteticos (arquivos
temporarios em `mktemp -d`, nunca editando os agentes reais), cobrindo os
Acceptance Scenarios 2 e 3 da User Story 1 [FONTE: spec.md:38-43]:

| Fixture | Allowlist | Veredito esperado |
|---------|-----------|-------------------|
| so-MCP inline | `tools: mcp__cstk-state__open_wave, mcp__cstk-state__get_status` | fail `mcp_only_allowlist` |
| so-MCP lista | `tools:` + `- mcp__cstk-state__open_wave` | fail `mcp_only_allowlist` |
| vazia | `tools:` sem entradas | fail `empty_allowlist` |
| ausente | frontmatter sem chave `tools:` | fail `tools_key_absent` |
| mista inline | `tools: Bash, mcp__cstk-state__open_wave` | pass |
| mista lista | `tools:` + `- Bash` + `- mcp__cstk-state__open_wave` | pass |
| so-nativa | `tools: Agent, Skill, Bash` | pass |

> A cobertura das DUAS formas (inline e lista) e obrigatoria: o guard
> revogado so casava a forma de lista e por isso era inerte contra a forma
> inline realmente usada no repo (research Decision 1). Sem fixture das
> duas formas, o mesmo ponto cego reaparece.

## Contrato de parsing

```
ENTRADA: caminho de um arquivo .md com frontmatter YAML
SAIDA:   lista de entradas normalizadas (uma por linha em stdout interno)

1. Delimitar o bloco de frontmatter: da 1a linha `---` ate a proxima `---`.
   Fora desse bloco, NADA e lido (evita casar `mcp__` na prosa do agente —
   que esta feature vai adicionar na secao de orientacao).
2. Localizar a chave `tools:` dentro do bloco.
   - ausente            -> declared = false
3. Se ha valor na MESMA linha: split por virgula.
4. Senao: coletar linhas seguintes que casem `^[[:space:]]*-[[:space:]]+`
   ate a proxima chave de frontmatter ou o fim do bloco.
5. Normalizar cada entrada: trim de espacos; descartar entradas vazias.
6. Classificar: prefixo `mcp__` -> mcp_entries; senao -> native_entries.
```

## Exit codes

Segue a convencao do harness do repo (`tests/run.sh`): scenario retorna
`0` = PASS, `1` = FAIL, `2` = ERROR (pre-condicao ausente, ex.: diretorio
`plugins/cstk/agents` inexistente). O `--check-coverage` do runner sai com
`1` quando detecta orfao [FONTE: tests/run.sh:72].

## Integracao com o harness (FR-012)

1. O arquivo termina com `run_all_scenarios "$0"` — descoberta automatica
   das funcoes `scenario_*` [FONTE: tests/test_orchestrator-mcp-fallback.sh:245].
2. `tests/run.sh` `_is_internal_test` ganha um ramo para
   `test_orchestrator-allowlist-guard.sh`, existence-guarded ao diretorio
   `plugins/cstk/agents` — sem esse ramo o arquivo e reportado como "test
   sem script" e o `--check-coverage` sai com `1`
   [FONTE: tests/run.sh:612-624 (laco "Tests sem script") e :616-618 (pulo
   dos internos)].
