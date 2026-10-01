# Contract: invocacao da skill e dos scripts

[PROPOSTA — a validar na implementacao] — interfaces novas. Scripts sob
`plugins/cstk/skills/reconcile-docs/scripts/`, todos `#!/bin/sh` + `set -eu`, sem
`jq`, erros em stderr, dados em stdout. Exit codes base: 0 sucesso, 1 erro geral,
2 uso incorreto (Principio II); codigos >= 3 sao especificos e listados por script.

## 1. Skill

```
/reconcile-docs <feature> [--dry-run]
/reconcile-docs --all [--dry-run]
```

| Argumento | Regra |
|-----------|-------|
| `<feature>` | nome kebab-case, com ou sem prefixo `AAAA-MM-DD-` (FR-001, FR-002) |
| `--all` | mutuamente exclusivo com `<feature>` (FR-003) |
| `--dry-run` | nenhuma escrita, inclusive `reconciliation.md` (FR-011, SC-007) |
| nenhum argumento | erro de uso: mostra a sintaxe e encerra sem alterar nada |

Raiz do projeto: diretorio de trabalho corrente; deve conter `docs/specs/`. Ausente →
encerra informando (US2 cenario 3 cobre `docs/specs/` vazio).

Saida: relatorio na conversa conforme `templates/report.md` (data-model
§ReconciliationReport). Escritas permitidas: so as validadas por `doc-guard.sh check`.

Politica de gravacao (dec-035): (a) **sem git** (`git-probe.sh can-write` com exit != 0,
inclusive script ausente) a skill RECUSA gravar: executa como `--dry-run` forcado e o
relatorio traz o aviso `no-git-write-refused` (FR-016); (b) **`--all` sem `--dry-run`**:
depois da analise de todas as features a skill exibe o resumo do que mudara e pede UMA
confirmacao antes de gravar; sem confirmacao afirmativa ou sem operador presente, cai em
`--dry-run` (FR-020). Feature unica em projeto com git continua gravando direto.

Constitution do projeto (`docs/constitution.md`): insumo de FR-007, nao pre-requisito.
Se ausente ou ilegivel, a execucao prossegue e o relatorio traz o aviso
`constitution-unavailable` em `notices`; `possible-regression` passa a considerar apenas
MUST/MUST NOT da propria feature (nenhum principio e presumido — Constitution VI).

Nao-copia de segredos (FR-019): a evidencia em documentos, marcadores e relatorio e sempre
`arquivo:linha` ou `absent:<caminho>`; valores sensiveis do codigo (chaves, tokens,
credenciais) NUNCA sao reproduzidos. E regra da skill (`references/classification.md` +
Gotcha), sem checagem deterministica em script — os 6 scripts nao mudam de contrato; o
marcador ja so aceita `<path>:<line>` (markers.md §1).

## 2. `locate-feature.sh`

```
locate-feature.sh --root <dir> --name <feature>
locate-feature.sh --root <dir> --all
```

stdout TSV: `<location>\t<name>\t<dir>` com `<location>` ∈
`active | archived | archived-shadowed | candidate`.

| Caso | stdout | exit |
|------|--------|------|
| `--name` casa exatamente uma ativa | `active` (+ linhas `archived-shadowed` para arquivadas de mesmo nome) | 0 |
| `--name` casa exatamente uma arquivada (sem ativa) | `archived` | 0 |
| nenhum casamento exato | linhas `candidate` (substring, ordenadas; pode ser vazio) | 3 |
| mais de um casamento exato na mesma classe | linhas `candidate` com todos | 4 |
| `--all` | todas as ativas, depois todas as arquivadas (arquivada com ativa homonima sai como `archived-shadowed`) | 0 |
| `docs/specs/` ausente | mensagem em stderr | 1 |

Nunca lista `docs/specs/current/` nem `docs/specs/_archived/` como feature. `--name`
fora de `^([0-9]{4}-[0-9]{2}-[0-9]{2}-)?[a-z0-9][a-z0-9-]*$` → exit 2 (rejeita `..`,
`/`, espacos e metacaracteres).

## 3. `extract-anchors.sh`

```
extract-anchors.sh --root <dir> --feature-dir <dir>
```

stdout TSV: `<kind>\t<token>\t<doc>:<line>\t<presence>` (data-model §Anchor), dedupe
por (`kind`, `token`, `doc:line`) preservando a ordem. Varre so os documentos da
allowlist presentes. exit 0 (0+ linhas); 1 feature-dir inexistente ou documento da
allowlist presente mas ilegivel (fail-closed, diagnostico em stderr, nenhuma linha
parcial e tratada como completa); 2 uso.

## 4. `doc-guard.sh`

```
doc-guard.sh check --root <dir> --feature-dir <dir> <path>
```

exit 0 = escrita permitida; exit 1 = negada (motivo em stderr: `outside-feature`,
`not-in-allowlist`, `living-corpus`, `symlink-escape`); exit 2 = uso. Allowlist:
`spec.md`, `plan.md`, `data-model.md`, `quickstart.md`, `reconciliation.md`,
`contracts/*.md` (um nivel), relativos ao `--feature-dir` resolvido com `pwd -P`.
`--feature-dir` sob `docs/specs/current/` → sempre exit 1. Destino que ja existe
como simlink → exit 1 (`symlink-escape`), independente do alvo. Fail-closed: o
chamador trata QUALQUER exit != 0 (inclusive script ausente) como negacao.

## 5. `markers.sh`

```
markers.sh lint <file>        # exit 0 ok; 1 marcador mal formado (linha em stdout); arquivo inexistente ou ilegivel = exit 2
markers.sh list <file>        # TSV <line>\t<kind>\t<date>\t<ref>
markers.sh next-fr <spec.md>  # imprime FR-NNN seguinte (FR-001 se nenhum)
markers.sh verify --root <dir> <file>  # exit 0 se toda evidencia confere; 1 lista <line>\t<ref>\t<motivo>
```

`verify`: `<path>:<line>` exige arquivo existente com pelo menos `<line>` linhas;
`absent:<path>` exige que o caminho NAO exista; motivo ∈ `missing-file`,
`line-out-of-range`, `not-absent`.

Contrato de sintaxe: [markers.md](./markers.md).

## 6. `reconciliation-log.sh`

```
reconciliation-log.sh append --feature-dir <dir> --date <YYYY-MM-DD> --summary-file <file>
```

Cria `<feature-dir>/reconciliation.md` com cabecalho se ausente e anexa
`## <date>` + conteudo do `--summary-file`. exit 3 se `--summary-file` vazio (nada e
escrito — FR-018); exit 1 se o destino nao passar em `doc-guard.sh check`; nunca edita
entradas existentes.

## 7. `git-probe.sh` (unico arquivo que invoca `git` — carve-out 1.1.0)

```
git-probe.sh changed-since --root <dir> --feature-dir <dir>
git-probe.sh status --root <dir>
git-probe.sh can-write --root <dir>
```

`changed-since`: caminhos alterados em commits posteriores ao ultimo commit que tocou
os documentos da feature (um por linha). `status`: snapshot `git status --porcelain`
normalizado e ordenado. `can-write`: pre-condicao de escrita (dec-035) — em repositorio git
`WRITE\tallowed`, exit 0; sem git `WRITE\tdenied-no-git`, exit 3 (o chamador trata
qualquer exit != 0 como recusa e forca `--dry-run`). Toda invocacao usa `git -c core.fsmonitor=false ...` e apenas
subcomandos de leitura (`status --porcelain`, `log --name-only`, `rev-parse`). Com git: dados + linha final `STATUS\tok`. Sem `git` ou fora de
repositorio: nenhuma linha de dados, so a linha `STATUS\tno-git`, exit 0 (fallback —
FR-016); a excecao e `can-write`, que recusa com exit 3 (nao ha escrita sem git).
