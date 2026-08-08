# Fixtures de testes do `cstk`

Este diretorio contem fixtures usadas pelos tests em `tests/cstk/`. Toda
fixture e **gerada sob demanda** via [`regen.sh`](./regen.sh) — os artefatos
binarios (`*.tar.gz`, `*.sha256`, `install.sh`) NAO sao versionados.

## Layout

```
tests/cstk/fixtures/
├── README.md              # este arquivo
├── regen.sh               # reconstroi releases/ a partir do catalog atual
└── releases/
    ├── v0.1.0/
    │   ├── cstk-0.1.0.tar.gz       # gerado por scripts/build-release.sh
    │   ├── cstk-0.1.0.tar.gz.sha256
    │   └── install.sh              # copia de cli/install.sh
    └── v0.2.0/
        ├── cstk-0.2.0.tar.gz       # idem v0.1.0 + sentinel marker
        ├── cstk-0.2.0.tar.gz.sha256
        └── install.sh
```

## Quando rodar `regen.sh`

- Sempre que `tests/cstk/fixtures/releases/` estiver vazio (clone fresh,
  pos-`git clean`).
- Quando `plugins/cstk/skills/`, `cli/lib/`, `cli/cstk` ou `language-related/`
  mudar e voce quiser fixtures atualizadas.
- O proprio `regen.sh` e idempotente; rodar 2x produz exatamente os mesmos
  bytes (build-release.sh garante determinismo).

```sh
sh tests/cstk/fixtures/regen.sh
```

## Diferenca v0.1.0 vs v0.2.0

| Aspecto                       | v0.1.0           | v0.2.0                            |
|-------------------------------|------------------|-----------------------------------|
| `cli/` + lib                  | identico         | identico                          |
| `plugins/cstk/skills/specify/`      | catalog atual    | catalog + sentinel HTML comment   |
| Demais skills + `language/`   | identico         | identico                          |
| `catalog/VERSION`             | `0.1.0`          | `0.2.0`                           |

A unica diferenca de **conteudo de skill** entre as duas e o sentinel
appendado em `plugins/cstk/skills/specify/SKILL.md`. Isso simula uma release que
modificou apenas a skill `specify` — habilita testes de:

- Update detection (hash mismatch detectado em `specify`, demais clean)
- Idempotencia (skills nao modificadas nao sao re-escritas — SC-002)
- Self-update sem afetar manifest (FR-006a)

## Override `CSTK_RELEASE_URL`

Tests apontam o CLI para fixture local via:

```sh
CSTK_RELEASE_URL="file://$REPO_ROOT/tests/cstk/fixtures/releases/v0.1.0/cstk-0.1.0.tar.gz" \
  cstk install --scope global
```

ou usando `--from`:

```sh
cstk install --from "file://.../v0.1.0/cstk-0.1.0.tar.gz"
```

A logica de override esta em `cli/lib/install.sh` e `cli/lib/update.sh`
(`_install_resolve_urls` / `_update_resolve_urls`) — ja existente desde
FASE 3.1; FASE 10.1.2 e a confirmacao de uso por fixtures, nao introducao
do mecanismo.

## Tamanho

Cada tarballe tem ~200 KB. Total ~400 KB para v0.1.0 + v0.2.0. NAO sao
commitados — `.gitignore` filtra `*.tar.gz`, `*.sha256` e `install.sh`
neste subdir.
