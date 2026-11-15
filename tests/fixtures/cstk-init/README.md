# Fixtures de `cstk-init`

Carregadas com `fixture cstk-init/<nome>` de `tests/lib/harness.sh` (copia para `$TMPDIR_TEST`).
Todo valor em formato de chave e SINTETICO e obviamente falso (`FIXTURE_FAKE_KEY_...`); nunca
credencial real. O repositorio ignora `.env` e `.env.*` (exceto `.env.example`), por isso a
fixture `secrets` usa `.env.example` (casa `.env*` da classificacao `secret-bearing`).

| Fixture | Conteudo | Cenarios |
|---------|----------|----------|
| `bare` | README, manifesto, `src/`, `tests/`; sem `docs/` | 1, 2, 3, 13, 18, 20, 22 |
| `conformant` | `bare` + briefing e constitution no padrao vigente, sem pendencia | 5 |
| `pending` | `conformant` com um `[PENDENTE: ...]` no briefing | 5, 19 |
| `legacy` | briefing so no caminho legado; constitution sem o titulo fixo `## Governance` e sem o principio "Veracidade de Dados" | 4, 6 |
| `both-briefings` | briefing canonico e legado coexistindo | 4 |
| `three-features` | tres modulos (`billing`, `catalog`, `notifications`) com testes | 9, 10, 11, 20 |
| `secrets` | `.env.example` (secret-bearing) e `config/app.yml` (nao secret-bearing) com valor sintetico; o symlink para fora da raiz e criado em tempo de teste | 8, 17 |
| `hostile` | `bare` com texto imperativo em README, `docs/guide.md` e `config/app.yml` | 14 |

## Variantes montadas em tempo de teste (nao versionadas)

- Symlink para fora da raiz (Scenario 17): `ln -s <dir-fora-da-copia> link-out` na copia de `secrets`.
- Catalogo sem scanner (Scenario 18): copia temporaria de `plugins/cstk/skills` sem
  `agente-00c-runtime/scripts/secrets-filter.sh`.
- README em ingles / inventario insuficiente / quase sem codigo (Scenarios 20 e 22): derivados de
  `bare` removendo `README.md` e `package.json` (insuficiente) ou `src/` e `tests/` (quase sem codigo).
