# Contract: invocacao da skill e dos scripts

[PROPOSTA — a validar na implementacao] — interfaces novas. Scripts sob
`plugins/cstk/skills/cstk-init/scripts/`, todos `#!/bin/sh` + `set -eu`, sem `jq`, erros
em stderr, dados em stdout (TSV, campos por TAB, sem cabecalho). Exit codes base: 0
sucesso, 1 erro geral, 2 uso incorreto (Principio II); codigos >= 3 sao especificos e
listados por script. Nenhum script le conteudo de arquivo `secret-bearing` nem faz
acesso de rede (FR-012, FR-019).

## 1. Skill

```
/cstk-init [<caminho-do-projeto>] [--non-interactive]
```

| Argumento | Regra |
|-----------|-------|
| `<caminho-do-projeto>` | opcional; default = diretorio corrente (FR-001) |
| `--non-interactive` | sem perguntas; ver research Decision 9. Implicito quando `AGENTE_00C_STATE_DIR` esta definido. Arvore suja ou fora de VCS = zero escritas (so relatorio); nenhum principio e ratificado sem operador, entao a constitution nao e criada com principios (FR-004, FR-018, dec-023) |

Fluxo (SKILL.md): `preflight` → `artifacts` + `version` → `inventory` (apresentado ao
operador antes de qualquer escrita, FR-002) → briefing (criar ou revisar) → constitution
(criar ou revisar) → pergunta de registro de features (FR-013) → `evidence` → lotes de
candidatas → por confirmada: `name` → spec → `requirement-coverage.sh` → oferta de
complementares (FR-017) → resumo (`templates/summary.md`, FR-020).
Toda escrita: `init-guard.sh check` → Write/Edit → `init-guard.sh scan` →
`init-provenance.sh lint`. Antes da PRIMEIRA escrita: `init-guard.sh scan --probe` (scanner indisponivel → zero escritas, so relatorio; FR-027, dec-026 D2). A imposicao do guarda e PROCEDIMENTAL nesta feature (FR-026, dec-026 D1=c): nenhuma ferramenta bloqueia um Write/Edit sem `check`; o hook `PreToolUse` `Write|Edit` e escopo de feature futura. Idioma do conteudo gerado = idioma predominante do README, confirmado ao operador (FR-033); titulos de secao seguem o template. Perguntas em rodadas de ate 5 (FR-005); candidatas em lotes de ate 5 (FR-014); lote declarado = lista explicita caminho+operacao, sem confirmacao generica (FR-031).

Frontmatter: `name: cstk-init`, `description` como trigger (Principio III),
`argument-hint`, `allowed-tools` (Read, Glob, Grep, Bash, Write, Edit, AskUserQuestion,
Skill) — mesmas chaves usadas por `reconcile-docs/SKILL.md` e `briefing/SKILL.md`.

## 2. `init-probe.sh`

```
init-probe.sh preflight --root <dir>
init-probe.sh artifacts --root <dir>
init-probe.sh version  --skill-dir <dir>
```

| Subcomando | stdout | exit |
|------------|--------|------|
| `preflight` | `ROOT\t<abs>`, `WRITE\t<ok|denied-missing|denied-not-dir|denied-readonly>`, `VCS\t<git-clean|git-dirty|none>` | 0 se `WRITE ok`; 3 se negado |
| `artifacts` | linhas `ArtifactState` (`briefing\t<state>\t<path>\t-`, `constitution\t<state>\t<path>\t<versao|->`, `spec\tpresent\t<path>\t<short>`) | 0; 1 raiz inexistente |
| `version` | `CSTK_VERSION\t<versao|unknown>\t<plugin-json|manifest|unknown>` | 0 sempre (inclusive `unknown`) |

Unico script que invoca `git` (carve-out 1.1.0): `git -c core.fsmonitor=false status
--porcelain` com `GIT_OPTIONAL_LOCKS=0`; `git` ausente, fora de repositorio ou falha →
`VCS\tnone`. Ordem de busca do briefing: `docs/briefing.md`, depois
`docs/01-briefing-discovery/briefing.md`. Specs: `docs/specs/*/spec.md` exceto
`_archived/` e `current/`.

## 3. `init-inventory.sh`

```
init-inventory.sh inventory --root <dir> [--max-items <n>]
```

`--max-items` default **1000** (valor de design, sem medicao empirica; FR-030a, dec-026 D5); `--help` documenta o default.

Classificacao so por NOME/caminho (nunca le conteudo; tarefa 4.2, decisao operacional do orquestrador, score 2): `secret-bearing` (`.env`, `.env.*`, `*.pem`, `*.key`, `id_rsa*`, `*.p12`, `credentials*`) tem precedencia; depois `readme`, `license`, `changelog`, `ci`, `doc` (sob `docs/` ou `*.md|*.rst|*.adoc|*.txt`), `test` (sob `tests/`, `test/`, `__tests__/` ou nome `*.test.*|*.spec.*|*_test.*|*_spec.*|test_*`), `manifest` (`package.json`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `requirements.txt`, `composer.json`, `pom.xml`, `build.gradle*`, `Gemfile`, `Makefile`, ...), `config` (`*.yml|*.yaml|*.toml|*.ini|*.json|*.conf|*.cfg`, `Dockerfile*`, `docker-compose*`); arquivo de codigo-fonte (extensoes conhecidas) nao e listado: emite-se `source-dir\t<diretorio-pai>` uma vez por diretorio (`.` = raiz). Symlink interno valido para arquivo e classificado pelo nome do link; symlink para diretorio, symlink interno pendente e nomes com TAB/newline sao omitidos; destino irresoluvel ou ciclo = `symlink-escape`.

stdout: `<kind>\t<path>` (data-model §InventoryItem), ordenado por path; symlink cujo destino resolvido (`cd -P`/`pwd -P`, sem `realpath`) sai da raiz e emitido como `symlink-escape\t<path>` sem ser lido nem seguido (FR-023, dec-021); nenhuma linha carrega valor de configuracao (FR-024); linha final
`TRUNCATED\t<n>` quando o inventario e PARCIAL: teto de itens (`--max-items`; n = omitidos, exato se a varredura terminou), teto de varredura (50 x `--max-items` arquivos visitados, valor de design sem medicao empirica; a varredura PARA e n e limite inferior) ou erro de varredura (permissao negada, `find`/emissor com exit != 0; n = erros, >= 1) — o motivo vai em stderr (tarefas 7.5.3 e 7.5.4); o SKILL.md MUST apresentar aviso explicito ao operador e nao afirmar completude do inventario, do briefing nem da lista de candidatas (FR-030a). Exit: 0; 1 raiz inexistente; 2 uso.

## 4. `init-conformance.sh`

```
init-conformance.sh check --root <dir> --catalog-root <dir-de-skills>
```

`--catalog-root` = diretorio que contem `briefing/`, `constitution/`, `specify/` da mesma
raiz de catalogo da skill. stdout: `<artifact>\t<rule>\t<detail>\t<proposal>`
(data-model §Divergence) + linha final `STATUS\t<conformant|divergent>`. Exit: 0 (com ou
sem divergencias); 1 raiz inexistente; 4 template de irma ausente (mensagem cita o caminho
e `cstk install`).

Detalhes de implementacao do `check` (tarefa 4.5, decisao operacional do orquestrador, score 2, sem alterar os tokens do contrato): os titulos exigidos (`missing-section`) sao LIDOS dos templates instalados — titulos de nivel 2 (briefing, constitution) ou 2 e 3 (spec) sem placeholder (`[`/`<`), menos `## Delta Requirements` (coberto por CR-007) e `### Key Entities` (condicional) —, e os rotulos de cabecalho de CR-003 sao as linhas `**X**:` do template antes do primeiro `## `; a comparacao e por titulo exato, fora de bloco de codigo. Os tres templates sao verificados antes de qualquer leitura (qualquer um ausente = exit 4). Briefing: so legado = CR-001 (+ regras sobre o legado); os dois = CR-002 (+ regras sobre o canonico); nenhum briefing nao gera divergencia. CR-004 = nenhuma linha `**Version**: v | **Ratified**: v | **Last Amended**: v` com os tres valores nao vazios e sem placeholder; CR-005 = nenhum titulo contendo `Veracidade de Dados`; CR-006 = `### ` sob `## Core Principles` sem linha `**MUST:**` no bloco. Specs: `docs/specs/<short>/spec.md`, sem `_*` nem `current`; diretorio/arquivo symlink que escape, `docs/specs`/diretorio de spec symlink ou artefato nao regular/legivel NAO e lido, gera aviso em stderr e o achado `CR-008` (`manual`), e o `STATUS` e `divergent` (tarefa 7.5.2: "nao avaliado" nunca e `conformant`). Somente leitura, nenhum arquivo temporario. [PROPOSTA — a validar na implementacao]

## 5. `init-candidates.sh`

```
init-candidates.sh evidence --root <dir>
init-candidates.sh name --root <dir> --name <short>
```

| Subcomando | stdout | exit |
|------------|--------|------|
| `evidence` | `<signal>\t<key>\t<path>` | 0; 1 raiz inexistente |
| `name` | `NAME\t<short>\t<free|exists-active|exists-archived>` | 0 `free`; 3 colisao; 5 nome invalido (nao kebab-case `^[a-z0-9]+(-[a-z0-9]+)*$`) |

Detalhes de implementacao (tarefa 4.6, decisao operacional do orquestrador, score 2, sem alterar os tokens do contrato): `evidence` DERIVA os sinais da saida de `init-inventory.sh inventory` (so caminhos; nunca le conteudo; seam `INIT_CANDIDATES_INVENTORY_BIN`) com teto proprio de 100000 itens (valor de design sem medicao; `TRUNCATED\t<n>` e repassado como ultima linha e torna o resultado parcial, FR-030a). `source-module` = diretorio de 1o e 2o nivel que contem codigo (nao tests/docs); `test-group` = `tests/<X>` (ou o proprio `tests` para arquivo direto) sob `tests|test|__tests__`, ou o diretorio do arquivo para teste ao lado do codigo; `doc-page` = pagina sob `docs/`, exceto `briefing.md`, `constitution.md`, `01-briefing-discovery/` e `specs/`; `workspace` = manifesto em subdiretorio (path = o manifesto, key = diretorio pai) — os workspaces NAO sao lidos do conteudo do manifesto (texto do projeto e dado hostil e exigiria parser; fica registrado como limite do sinal). `name`: o nome e validado ANTES de tocar o disco (exit 5 independe da raiz); colisao ativa = qualquer entrada `docs/specs/<short>` (diretorio, arquivo ou symlink); arquivada = `docs/specs/_archived/<short>` ou `docs/specs/_archived/AAAA-MM-DD-<short>` (o glob `*<short>` do texto antigo casaria `enforced-guards` ao consultar `guards`; a forma exata evita falso positivo de sufixo parcial). [PROPOSTA — a validar na implementacao]

## 6. `init-guard.sh`

```
init-guard.sh check --root <dir> --path <rel> --op <create|amend|migrate> [--confirmed]
init-guard.sh scan  --file <path> [--catalog-root <dir-de-skills>]
init-guard.sh scan  --probe [--catalog-root <dir-de-skills>]
init-guard.sh migrate --root <dir> --confirmed
```

| Subcomando | stdout | exit |
|------------|--------|------|
| `check` | `ALLOW\t<path>` ou `DENY\t<path>\t<reason>` | 0 allow; 3 deny |
| `scan --file` | `SCAN\t<clean|secret-found|unavailable>` | 0 clean; 3 secret-found; 4 unavailable (fail-closed, FR-027) |
| `scan --probe` | `SCAN\t<available|unavailable>` | 0 available; 4 unavailable |
| `migrate` | `MIGRATED\tdocs/01-briefing-discovery/briefing.md\tdocs/briefing.md` ou `DENY\t<path>\t<reason>` | 0 movido; 3 deny (`unconfirmed`, `exists` quando `docs/briefing.md` ja existe, `not-allowlisted` quando a origem nao existe) |

Razoes de `DENY`: `outside-root`, `symlink-escape`, `not-allowlisted`, `exists`
(`create` sobre arquivo existente), `unconfirmed` (`amend`/`migrate` sem `--confirmed`).
Allowlist: `docs/briefing.md`, `docs/constitution.md`, `docs/specs/<short>/spec.md`,
`docs/specs/<short>/data-model.md`, `docs/specs/<short>/checklists/<dominio>.md`;
`migrate` aceita somente origem `docs/01-briefing-discovery/briefing.md` → destino
`docs/briefing.md`. `scan` delega a `<catalog-root>/agente-00c-runtime/scripts/secrets-filter.sh
check` (stdin = arquivo); script ausente → `unavailable` com exit 4: FAIL-CLOSED (FR-027, dec-026 D2) — o SKILL.md verifica com `scan --probe` antes da primeira escrita e, se indisponivel, nao grava documento algum (aviso `secrets-scan-unavailable` + `cstk install`, perfil `sdd`). Qualquer saida do `secrets-filter.sh check` diferente de exit 0 (limpo) e exit 1 (segredo) — por exemplo 2 (uso incorreto) ou falha do proprio script — e tratada como `unavailable` (exit 4), pois FR-027 e fail-closed. Os matches nunca vao para stdout NEM para stderr do `scan`: o `secrets-filter.sh check` imprime o conteudo dos matches em stderr, que o `scan` descarta (FR-024). Piso de deteccao do scanner declarado em FR-027 (issue #169).

Detalhes de implementacao do `check` (tarefa 4.3, decisao operacional do orquestrador, score 2, sem alterar os tokens do contrato): qualquer symlink em QUALQUER componente do caminho (inclusive o arquivo final) e negado como `symlink-escape`, mesmo quando o destino fica dentro da raiz, porque o Write seguiria o link para fora da allowlist; `..` e caminho absoluto = `outside-root`; `.`/componente vazio/barra final/TAB/newline = `not-allowlisted`; `docs/specs/current/` e nomes fora de `^[a-z0-9][a-z0-9-]*$` nao estao na allowlist; `--op migrate` so aceita `--path docs/01-briefing-discovery/briefing.md` (origem existente, destino ausente, `--confirmed`). Erro do proprio mecanismo (raiz inexistente, arquivo ilegivel) sai com exit 1 sem `ALLOW`/`clean` (fail-closed). `scan --probe` nao so verifica a existencia do scanner: roda uma amostra limpa (deve dar exit 0) e uma amostra sintetica com segredo (deve dar exit 1); scanner quebrado ou "sempre limpo" = `unavailable` (exit 4).

`migrate` e o UNICO subcomando que altera o sistema de arquivos alem de Write/Edit: `mv` de origem fixa `docs/01-briefing-discovery/briefing.md` para destino fixo `docs/briefing.md` (FR-032, dec-026 D6), recusado sem `--confirmed` e quando o destino existe. Uma invocacao por caminho (FR-031); `--confirmed` so apos confirmacao nominal do operador. O `migrate` valida POR CONTA PROPRIA, sem depender de `check` previo, `outside-root` e `symlink-escape` na origem e no destino (o diretorio `docs/` e a origem sao resolvidos com `cd -P`/`pwd -P`), alem da regra de allowlist; sem remocao de qualquer outro arquivo. [PROPOSTA — a validar na implementacao]

## 7. `init-provenance.sh`

```
init-provenance.sh lint --root <dir> --file <rel>
```

stdout: `PENDING\t<linha>\t<pergunta>`, `DANGLING\t<linha>\t<path-citado-inexistente>`,
`BAD-MARKER\t<linha>\t<trecho>` (contracts/markers.md; inclui citacao `(fonte: ...)` com `..`, caminho absoluto ou symlink que escapa da raiz — FR-023) + linha final
`STATUS\t<ok|pending|invalid>`. Exit: 0 `ok`/`pending`; 3 `invalid` (DANGLING ou
BAD-MARKER — o documento nao e dado como concluido). Para spec reconstituida verifica
tambem a presenca do marcador `<!-- cstk-init:reconstructed -->` e a ausencia de
`MUST`/`SHOULD` sob `### Inferido (nao confirmado)`. Em spec reconstituida: Success Criterion com digito (meta numerica) sem `(fonte: ...)` na mesma linha e prioridade/cenario de aceite sem `(fonte: ...)` nem `[PENDENTE: ...]` sao `BAD-MARKER` (FR-028). `lint` `invalid` apos o arquivo gravado NAO apaga o arquivo: reporta e oferece corrigir (FR-034c).

Detalhes de implementacao do `lint` (tarefa 4.4, decisao operacional do orquestrador, score 2, sem alterar os tokens do contrato): "spec reconstituida" = caminho `docs/specs/<short>/spec.md` OU presenca do marcador (a ausencia do marcador em `docs/specs/*/spec.md` e `BAD-MARKER` na linha `0`; o marcador deve vir antes do primeiro `## `); `(informado pelo operador)` conta como origem de fato tambem para Success Criterion numerico, prioridade e cenario (e uma origem rastreavel, markers.md §1); item `- **FR-NNN**` fora de `### Inferido` sem origem nem `[PENDENTE: ...]` e `BAD-MARKER` (formato "Observado" de markers.md §3, SC-002); Success Criterion = item de lista sob `## Success Criteria`, e o digito e procurado depois de remover IDs (`SC-`/`FR-`/`INF-`), `(fonte: ...)`, `(informado pelo operador)` e `[PENDENTE: ...]` (um valor presumido ao lado de `[PENDENTE]` continua `BAD-MARKER`; metas por extenso, sem digito, nao sao detectaveis); cenario = item de lista sob `**Acceptance Scenarios**` ou item com `Given`+`When|Then` / `Dado`+`Quando|Entao`; `MUST`/`SHOULD` sob Inferido sao detectados como palavra inteira, sem distincao de caixa; `(fonte:` fora da gramatica (sem crases, sem fechamento, linha `0`/invalida) e `[PENDENTE` sem pergunta ou sem `]` sao `BAD-MARKER`; `:<linha>` alem do fim do arquivo, ou sobre diretorio, e `DANGLING`; `--file` fora da raiz (absoluto, `..`, symlink que escapa), inexistente ou nao regular = exit 1 (erro do mecanismo, nunca `ok`). Linhas dentro de bloco de codigo cercado nao alteram a estrutura de secoes, mas seus marcadores sao verificados. [PROPOSTA — a validar na implementacao]
