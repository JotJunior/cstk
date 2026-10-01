# Contract: `orchestrator-refs.sh` [PROPOSTA — a validar na implementacao]

Script novo do runtime:
`plugins/cstk/skills/agente-00c-runtime/scripts/orchestrator-refs.sh`
(POSIX sh, `#!/bin/sh`, `set -eu`, sem `jq`/`sqlite3`).

## Resolucao da raiz

Sourceia `_resolve-root.sh` (mesmo diretorio) e chama
`resolve_runtime_root strict` — ordem B do contrato existente
(`_resolve-root.sh:34-41`): diretorio-irmao do script PRIMEIRO, depois
`${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime`, depois
`$HOME/.claude/skills/agente-00c-runtime`.

Motivo da ordem `strict`: o conteudo resolvido vira INSTRUCAO carregada no
contexto do orquestrador. Priorizar a ancora do proprio processo impede que
uma variavel de ambiente exportada por processo pai redirecione a leitura
para um arquivo de outra origem (mesma ameaca documentada no achado F3/dec-027
citado em `_resolve-root.sh:34-41`).

## Subcomandos

### `path --orchestrator <root|feature> --phase <phase>`

- stdout: caminho absoluto de `<root>/references/orchestrators/<orchestrator>/<phase>.md`.
- exit 0: arquivo existe e e legivel.
- exit 1: raiz nao resolvida OU arquivo ausente/ilegivel. stderr = diagnostico
  com os candidatos tentados. stdout vazio.
- exit 2: uso incorreto (flag ausente, `orchestrator` fora do enum, `phase`
  fora de `[a-z0-9-]+` — rejeita `/`, `.`, espaco: bloqueia path traversal).
- Confinamento (gate owasp-security, achado S1): o arquivo resolvido MUST ser
  arquivo regular que NAO e symlink e cujo diretorio fisico (`cd -P`) esta sob
  `<root>/references/orchestrators/`; caso contrario exit 1 (nunca seguir link
  para fora da raiz — o conteudo vira instrucao do agente).

### `list [--orchestrator <root|feature>]`

- stdout: uma linha `<orchestrator>\t<phase>\t<absolute-path>` por arquivo
  existente, ordenado (`sort`).
- exit 0 sempre que a raiz resolve (lista vazia e valida); exit 1 se a raiz
  nao resolve; exit 2 uso incorreto.

## Uso pelo orquestrador (normativo para o ponteiro)

```bash
REF=$("$RUNTIME_SCRIPTS"/orchestrator-refs.sh path --orchestrator root --phase clarify) \
  || REF=""
# REF vazio => FR-010: nao executar a fase; Decisao + bloqueio humano.
# REF preenchido => tool Read em "$REF" ANTES dos passos da fase.
```

## Testes (a implementar)

- `path` resolve cada `(orchestrator, phase)` citado em marcadores
  `ORCH-REF` dos prompts-base (FR-009).
- `path` com fase inexistente => exit 1, stdout vazio.
- `phase` com `../` => exit 2.
- Execucao a partir do subtree do repositorio (`plugins/cstk/...`) e a partir
  de uma copia instalada em `$HOME` temporario (`cp -R` do skill dir) resolvem
  para o arquivo do proprio subtree (ancora irma).
- `tests/test_doc-subcommands.sh` valida `orchestrator-refs.sh path|list`
  contra os labels reais do dispatch.
