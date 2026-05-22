# Contract: `cstk 00c <path>` (FASE 12)

Subcomando de bootstrap interativo de um projeto-alvo do agente-00C. Cria
diretorio, coleta parametros do `/agente-00c` via prompts e invoca `claude`
ja com a slash command montada.

Ref: spec.md US-5, FR-016 + FR-016a..h, SC-008/009; quickstart Scenarios 13-16.

## Sintaxe

```
cstk 00c <path> [--yes] [--help]
```

### Argumentos

| Arg     | Tipo      | Descricao                                                                          |
|---------|-----------|------------------------------------------------------------------------------------|
| `<path>`| posicional| OBRIGATORIO. Path para o novo projeto-alvo. Pode ser absoluto ou relativo ao CWD.  |

### Flags

| Flag      | Descricao                                                                          |
|-----------|------------------------------------------------------------------------------------|
| `--yes`   | Pula APENAS o prompt final de confirmacao (FR-016e) e o prompt de auto-install     |
|           | (FR-016d). NAO pula validacoes de path/TTY/deps nem o prompt de dir nao-vazio      |
|           | (que nao existe — dir nao-vazio aborta direto).                                    |
| `--help`  | Imprime ajuda inline do subcomando + pre-requisito TTY + lista de prompts esperados|

### Flags globais NAO aplicaveis

`--scope`, `--dry-run`, `--verbose` — `cstk 00c` nao opera em escopos canonicos
(skills/commands/agents) e tem semantica propria de dry-run (FR-016e ja imprime
preview obrigatorio antes da confirmacao).

## Pre-condicoes (verificadas em ordem)

| # | Pre-condicao                       | Falha = exit | Detalhe                                                       |
|---|------------------------------------|--------------|---------------------------------------------------------------|
| 1 | `<path>` arg presente              | 2            | Sem arg = uso incorreto                                       |
| 2 | TTY interativo (stdin + stdout)    | 2            | FR-016a — stderr pode ser redirecionado                       |
| 3 | `<path>` valido                    | 2            | FR-016b — sem traversal, fora de zonas de sistema             |
| 4 | `<path>` novo ou vazio             | 1            | FR-016b — dir nao-vazio NAO PROMPT, aborta direto             |
| 5 | Lock per-path adquirivel           | 1            | FR-016h — `mkdir <path>/.cstk-00c.lock/` atomico              |
| 6 | `claude` no PATH                   | 1            | FR-016d (a)                                                   |
| 7 | `jq` no PATH                       | 1            | FR-016d (b)                                                   |
| 8 | `agente-00c.md` instalado          | varia        | FR-016d (c) — auto-install via prompt Y; N = exit 1           |
| 9 | Prompts respondidos validamente    | 130 ou 1     | Ctrl+C = 130; aborto explicito = 1                            |
| 10| Confirmacao final aceita           | 0            | Prompt FR-016e — `n` = exit 0 sem mensagem de erro            |

## Sequencia de prompts

| # | Prompt                                                                          | Validacao                                                                  |
|---|---------------------------------------------------------------------------------|----------------------------------------------------------------------------|
| 1 | (apenas se agente-00c.md ausente) `Comando agente-00c nao instalado. Instalar agora via 'cstk install'? [Y/n]` | `Y/y/yes/s/S/sim/Enter` = Y; `n/N/no/nao/Ctrl+D` = N            |
| 2 | `Descricao curta do POC/MVP (10-500 chars):`                                    | >=10, <=500, sem `\n`/`$`/`` ` ``; loop ate valido                         |
| 3 | `Stack-sugerida em JSON (Enter para pular):`                                    | Linha vazia = skip; senao validado por `jq -e .` (loop ate valido)         |
| 4 | `Whitelist de URLs externas (uma por linha, linha vazia para terminar):`        | Cada URL: `^https?://[A-Za-z0-9._/?-]+$` E nao-overly-broad; loop ate valida|
| 5 | (resumo dry-run de FR-016e) `Confirmar invocacao do claude com /agente-00c '...' --stack '...' --whitelist <file> --projeto-alvo-path <abs>? [Y/n]` | `Y/y/yes/s/S/sim/Enter` = confirma; senao = exit 0 limpo (cancelado)       |

## Acoes e efeitos colaterais

| Etapa | Efeito                                                                             |
|-------|------------------------------------------------------------------------------------|
| Validacao de path | Resolve `<path>` via `realpath -m` (com fallback POSIX) e checa zonas proibidas |
| Lock | `mkdir <path>/.cstk-00c.lock/` (atomico). `trap '_00c_release_lock' EXIT INT TERM`        |
| Mkdir alvo | `mkdir -p <path>` + `chmod 700 <path>` (sensitive content)                        |
| Install aninhado | Apenas se necessario: `cstk install` em foreground (NAO `--force`)         |
| Whitelist | Escreve `<path>/.agente-00c-whitelist.txt` com `chmod 600` apos validacao + dry-run|
| Spawn | `_00c_release_lock` explicito; `cd <path>`; `exec claude "<slash command>"` (substitui processo cstk) |

## Exit codes

| Code | Significado                                                                                  |
|------|----------------------------------------------------------------------------------------------|
| 0    | Operador cancelou no prompt final OU `exec claude` rodou e claude retornou 0                 |
| 1    | Erro de runtime: dir nao-vazio, dependencia ausente, install aninhado falhou, lock conflito  |
| 2    | Uso incorreto: arg faltando, path invalido, TTY ausente                                      |
| 130  | Ctrl+C durante prompts (convencao POSIX `128 + SIGINT`)                                      |

## Saida (stdout / stderr)

- **stdout**: `claude` heredita stdout via `exec` no caminho feliz. Nada antes do exec.
- **stderr**: prompts (FR-016c, FR-016d, FR-016e), warnings, erros, dry-run preview de FR-016e, mensagens de aborto.
- **stdin**: lido pelos prompts ate `exec claude` assumir.

## Arquivos criados (caminho feliz)

| Path                                  | Modo | Persistencia                              | Conteudo                  |
|---------------------------------------|------|-------------------------------------------|---------------------------|
| `<path>/`                             | 700  | Persistente                               | Diretorio do projeto      |
| `<path>/.agente-00c-whitelist.txt`    | 600  | Persistente (consumido pelo orquestrador) | URLs whitelistadas, 1/linha |
| `<path>/.cstk-00c.lock/`              | 755  | Removido antes do `exec claude` (lock)    | Diretorio vazio           |

## Arquivos NAO criados (caminho infeliz)

Em qualquer abort (codes 1, 2, 130) ANTES do `mkdir <path>`, **nenhum byte** e
escrito (SC-009). Em abort APOS o `mkdir <path>` mas ANTES do exec, o diretorio
permanece (consistente com regra "sem rollback automatico"). Lock per-path
sempre liberado via trap.

## Helper invocado

Quando `cstk 00c` faz auto-install em foreground (FR-016d c):

```
cstk install
```

Sem flags. Respeita o lockfile global de FR-015 (se outro `cstk install` esta
rodando, falha imediatamente — `cstk 00c` proxia o erro).

## Anti-affordances explicitas

- `cstk 00c` NAO aceita arg `--projeto-alvo-path` (e gerado a partir de `<path>`)
- `cstk 00c` NAO oferece modo nao-interativo (use `/agente-00c` direto via claude)
- `cstk 00c` NAO retoma execucao existente (use `/agente-00c-resume` direto via claude)
- `cstk 00c` NAO opera em paths nao-vazios (sem `--force`, sem prompt — recusa direta)
- `cstk 00c` NAO faz cleanup automatico de `<path>` em abort (operador remove se quiser)
