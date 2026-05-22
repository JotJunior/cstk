# cstk — Claude Specs Toolkit CLI

CLI em POSIX sh para instalar, atualizar e auditar skills do toolkit. Este
diretorio contem o codigo fonte do CLI; a documentacao de design completa
vive em [`../docs/specs/cstk-cli/`](../docs/specs/_archived/cstk-cli/).

**Status atual**: FASES 0-9.2 do backlog concluidas — todos os subcomandos
(`install`, `update`, `self-update`, `list`, `doctor`) implementados e
testados, com pipeline de release automatizado. Pendentes: FASES 9.3
(coverage check), 10 (testes de integracao end-to-end) e 11 (docs +
primeira release publica).

## Layout

```
cli/
├── cstk         # executavel principal (POSIX sh)
├── VERSION      # tag de versao (dev: "0.0.0-dev"; release: preenchida pelo build)
├── lib/         # bibliotecas modulares por subcomando
└── README.md    # este arquivo
```

## Uso em dev (antes de release)

```sh
# Da raiz do repo:
./cli/cstk --version        # → cstk 0.0.0-dev
./cli/cstk --help
./cli/cstk help install     # aponta para o contrato
```

## Instalacao via one-liner

Apos uma release publica estar disponivel, instalar o `cstk` em uma maquina
nova com:

```sh
curl -fsSL https://github.com/JotJunior/claude-ai-tips/releases/latest/download/install.sh | sh
```

O bootstrap baixa o tarball da ultima release, valida o SHA-256 (FR-010a),
copia `cstk` para `~/.local/bin/` e `cli/lib/` para `~/.local/share/cstk/lib/`.
Depois disso:

```sh
cstk --version           # confirma instalacao
cstk install             # instala perfil sdd em ~/.claude/skills/
cstk self-update         # atualiza o proprio binario quando houver release nova
```

## Processo de release

A pipeline em [`.github/workflows/release.yml`](../.github/workflows/release.yml)
publica releases automaticamente quando uma tag SemVer e empurrada.

```sh
# Local: criar e empurrar a tag
git tag -a v0.1.0 -m "cstk v0.1.0"
git push origin v0.1.0
```

A pipeline (em `ubuntu-latest`):

1. Valida o formato da tag (`vX.Y.Z[-suffix]`)
2. Roda `./tests/run.sh` (suite global) — falha aborta o release
3. Roda cada `tests/cstk/test_*.sh` — falha aborta o release
4. Executa `./scripts/build-release.sh <tag>` (build deterministico —
   ver [scripts/build-release.sh](../scripts/build-release.sh))
5. Cria o GitHub Release via `gh release create` com upload de:
   - `cstk-<bare-version>.tar.gz`
   - `cstk-<bare-version>.tar.gz.sha256`
   - `cli/install.sh` (asset standalone para o one-liner)

Release notes sao geradas automaticamente pelo `gh release create
--generate-notes` (lista de PRs/commits desde a ultima tag).

**Re-rodar uma release ja publicada falha** — `gh release create` nao
sobrescreve. Para corrigir, deletar o release no GitHub UI e re-empurrar
a tag (ou usar uma nova tag, preferencial).

## Convencoes

- POSIX sh: `#!/bin/sh`, `set -eu`, sem bash-isms (Constitution 1.1.0 §II).
- Saida de dados em stdout; mensagens humanas + summaries em stderr.
- Exit codes: 0 OK, 1 erro geral, 2 uso, 3 lock, 4 edit local, 10 check-available.
- `$CSTK_LIB` override localiza lib/ durante testes.
- `$CSTK_VERSION_FILE` override localiza VERSION durante testes.

## Desenvolvimento

Veja [`../docs/specs/cstk-cli/tasks.md`](../docs/specs/_archived/cstk-cli/tasks.md) para
o backlog. Rodar testes:

```sh
sh tests/cstk/test_cstk-main.sh    # direto (FASE 1.1)
./tests/run.sh cstk                # via suite (apos FASE 9.3.1)
```
