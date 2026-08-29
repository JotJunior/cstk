# Testes de Integracao — apps/server

## Fixture do banco de dados

Os testes de integracao requerem `test/knowledge-fixture.db` — uma copia minimal
da `knowledge.db` real para validar queries SQL e mappers.

### Criar a fixture (apos `npm install`)

```bash
# Na raiz do monorepo, apos npm install:
node scripts/create-fixture.mjs
```

O script:
1. Copia `~/.claude/cstk/knowledge.db` para `test/knowledge-fixture.db` (read-only)
2. Abre em modo read-only para verificar schema v2
3. Confirma que `schema_meta` tem `key='schema_version', value='2'`

### Rodar os testes

```bash
# Na raiz:
npm run test --workspace apps/server

# Ou diretamente:
cd apps/server && npx vitest run
```

## Convencoes

- Testes de integracao NUNCA escrevem no DB (read-only constitucional)
- Fixture pode ser recriada a qualquer momento via `node scripts/create-fixture.mjs`
- Se `~/.claude/cstk/knowledge.db` nao existe, os testes de integracao sao pulados
  (degradacao de 1a classe — os testes unitarios de mapeamento continuam funcionando)
